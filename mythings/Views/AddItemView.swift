import SwiftUI
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - FlowLayout (iOS 16+)
@available(iOS 16.0, *)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var runSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(ProposedViewSize(width: nil, height: nil))
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += lineHeight + runSpacing
                lineHeight = 0
            }
            x += size.width + (x > 0 ? spacing : 0)
            lineHeight = max(lineHeight, size.height)
        }

        y += lineHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(ProposedViewSize(width: nil, height: nil))
            if x > bounds.minX && x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += lineHeight + runSpacing
                lineHeight = 0
            }
            sub.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - AddItemView
struct AddItemView: View {
    @Binding var selectedImage: UIImage?
    var existingItem: Item? = nil
    @ObservedObject var categoryStore: CategoryStore
    @ObservedObject var brandStore: BrandStore
    @Binding var showManageCategories: Bool
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    var onComplete: (Item) -> Void

    // form states
    @State private var name: String = ""
    @State private var brand: String = ""

    // ✅ 核心改動：改用 UUID? 儲存選擇的 category
    // UI 顯示仍用 categoryStore.name(for:)，完全不影響現有外觀
    @State private var categoryID: UUID? = nil

    @State private var price: String = ""
    @State private var showValidationAlert = false

    @State private var showImagePicker = false
    @State private var showCategorySheet = false

    @State private var showImageSourceMenu = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false

    @State private var pendingPhoto: UIImage?
    @AppStorage("pref.removeBG") private var prefRemoveBG: Bool = true

    @State private var useDate = false
    @State private var selectedDate = Date()

    // ✅ 便利屬性：取目前選中 category 的 name（顯示用）
    private var selectedCategoryName: String {
        guard let id = categoryID else { return "" }
        return categoryStore.name(for: id)
    }

    // ✅ 便利屬性：取目前選中 category 的 emoji
    private var selectedCategoryEmoji: String {
        guard let id = categoryID else { return "🧩" }
        return categoryStore.category(for: id)?.emoji ?? "🧩"
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .center, spacing: 20) {
                    categoryButton
                    imageSection
                    titleField
                    priceField
                    brandSection
                    dateSection
                    saveButton
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle(existingItem == nil ? "Add item" : "Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.secondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveTapped() }
                        .foregroundColor(.secondary)
                }
            }
        }

        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker(
                selectedImage: Binding<UIImage?>(
                    get: { nil as UIImage? },
                    set: { (img: UIImage?) in
                        if let img { pendingPhoto = img }
                    }
                ),
                shouldRemoveBackground: false
            )
        }

        .sheet(isPresented: $showCamera) {
            CameraPicker(
                selectedImage: Binding<UIImage?>(
                    get: { nil as UIImage? },
                    set: { (img: UIImage?) in
                        if let img { pendingPhoto = img }
                    }
                )
            )
        }

        .sheet(
            isPresented: Binding(
                get: { pendingPhoto != nil },
                set: { if !$0 { pendingPhoto = nil } }
            )
        ) {
            if let img = pendingPhoto {
                EditPhotoView(
                    original: img,
                    removeBG: { image in await removeBackground(from: image) },
                    onDone: { finalImage in
                        selectedImage = finalImage
                        pendingPhoto = nil
                    },
                    onCancel: { pendingPhoto = nil }
                )
                .presentationDetents([.large])
                .presentationCornerRadius(24)
            }
        }

        .sheet(isPresented: $showManageCategories) {
            ManageCategoriesView(categoryStore: categoryStore)
                .presentationDetents([.large])
        }

        .onAppear(perform: configureInitialValues)

        .alert("Please complete all fields", isPresented: $showValidationAlert) {
            Button("OK", role: .cancel) {}
        }

        .sheet(isPresented: $showCategorySheet) {
            categorySheet
        }

        // ✅ Manage 關閉後，若目前選的 category 已被刪除，自動切到第一個
        .onChange(of: showManageCategories) {
            if !showManageCategories {
                if let id = categoryID {
                    let stillExists = categoryStore.categories.contains { $0.id == id }
                    if !stillExists {
                        categoryID = categoryStore.categories.first?.id
                    }
                } else {
                    categoryID = categoryStore.categories.first?.id
                }
            }
        }

        .confirmationDialog("Update Image", isPresented: $showImageSourceMenu, titleVisibility: .visible) {
            Button("Choose from Library") { showPhotoPicker = true }
            Button("Take Photo") { showCamera = true }
            if selectedImage != nil {
                Button("Remove Image", role: .destructive) { selectedImage = nil }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Sections
private extension AddItemView {
    var fieldBG: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
    }

    var categoryButton: some View {
        Button { showCategorySheet = true } label: {
            HStack(spacing: 8) {
                // ✅ emoji 和名稱都透過 computed property 取得，外觀完全不變
                Text(selectedCategoryEmoji)
                Text(categoryID == nil ? "Select Category" : selectedCategoryName)
                    .font(.headline)
                    .foregroundColor(.primary)
                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder var imageSection: some View {
        if let image = selectedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .onTapGesture { showImageSourceMenu = true }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo").font(.system(size: 40))
                Text("Tap to add image").font(.subheadline).foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture { showImageSourceMenu = true }
        }
    }

    var titleField: some View {
        LabeledTextField(title: "Title", placeholder: "", text: $name)
    }

    var priceField: some View {
        LabeledTextField(title: "Price",
                         placeholder: "",
                         text: $price,
                         keyboard: .decimalPad,
                         prefix: "$")
    }

    @ViewBuilder
    var brandSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Brand").font(.footnote).foregroundColor(.secondary)
            VStack(spacing: 16) {
                TextField("Brand Name", text: $brand)
                    .textInputAutocapitalization(.words)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(fieldBG)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                BrandChipsView(brandStore: brandStore, selectedBrand: $brand)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    var dateSection: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Date", systemImage: "calendar").labelStyle(.titleAndIcon)
                Spacer()
                Toggle("", isOn: $useDate).labelsHidden()
            }
            .padding()
            .background(fieldBG)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if useDate {
                DatePicker("Select Date", selection: $selectedDate, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .tint(.appPrimary)
                    .padding(.top, -8)
            }
        }
    }

    var saveButton: some View {
        Button { saveTapped() } label: {
            Text("Save")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color(UIColor.label))
                .foregroundColor(Color(UIColor.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 28))
        }
        .padding(.top, 10)
    }

    // ✅ categorySheet：選取後存 UUID，顯示用 name 比對 checkmark
    @ViewBuilder
    var categorySheet: some View {
        NavigationStack {
            List {
                if categoryStore.categories.isEmpty {
                    ContentUnavailableView("No categories",
                                           systemImage: "square.grid.2x2",
                                           description: Text("Tap Manage to add some."))
                } else {
                    ForEach(categoryStore.categories) { c in
                        Button {
                            categoryID = c.id   // ✅ 存 UUID
                            showCategorySheet = false
                        } label: {
                            HStack(spacing: 12) {
                                Text(c.emoji)
                                Text(c.name)
                                    .foregroundColor(.primary)
                                if c.id == categoryID {   // ✅ 用 UUID 比對 checkmark
                                    Spacer()
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .presentationDetents([.fraction(0.7)])
        .presentationCornerRadius(40)
    }
}

// MARK: - Logic
private extension AddItemView {
    func configureInitialValues() {
        if let item = existingItem {
            name  = item.name
            brand = item.brand
            // ✅ 編輯時：直接用 categoryID，不需要 name 轉換
            categoryID = item.categoryID
            price = item.price.replacingOccurrences(of: "$", with: "")

            if let img = loadImage(named: item.imageName) {
                selectedImage = img
                print("✅ Loaded existing image: \(item.imageName)")
            } else {
                print("⚠️ Failed to load image: \(item.imageName)")
                selectedImage = nil
            }

            if let d = item.date {
                useDate = true
                selectedDate = d
            } else {
                useDate = false
            }
        } else if !categoryStore.categories.isEmpty {
            // ✅ 新增時：預設選第一個 category 的 UUID
            categoryID = categoryStore.categories.first?.id
            useDate = false
        }
    }

    /// 優先從 Images/ 讀圖；若找不到，回退到 Documents/（舊版相容）
    func loadImage(named fileName: String) -> UIImage? {
        print("🔍 Loading image: \(fileName)")

        let newURL = FileManager.imagesDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: newURL.path) {
            if let img = UIImage(contentsOfFile: newURL.path) {
                return img
            }
        }

        let oldURL = FileManager.documentsDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: oldURL.path) {
            if let img = UIImage(contentsOfFile: oldURL.path) {
                return img
            }
        }

        if !fileName.lowercased().hasSuffix(".png") {
            let withExt = fileName + ".png"
            let newURL2 = FileManager.imagesDirectory.appendingPathComponent(withExt)
            if FileManager.default.fileExists(atPath: newURL2.path),
               let img = UIImage(contentsOfFile: newURL2.path) {
                return img
            }
            let oldURL2 = FileManager.documentsDirectory.appendingPathComponent(withExt)
            if FileManager.default.fileExists(atPath: oldURL2.path),
               let img = UIImage(contentsOfFile: oldURL2.path) {
                return img
            }
        }

        print("❌ All image loading attempts failed for: \(fileName)")
        return nil
    }

    func priceWithDollar(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("$") ? trimmed : "$" + trimmed
    }

    private func saveTapped() {
        if !isFormValid() {
            showValidationAlert = true
            return
        }

        let itemId = existingItem?.id ?? UUID()
        var finalImageName = existingItem?.imageName ?? "\(itemId.uuidString).png"

        if let newImage = selectedImage {
            let fileName = "\(itemId.uuidString).png"
            let fileURL = FileManager.imagesDirectory.appendingPathComponent(fileName)
            do {
                try FileManager.default.createDirectory(at: FileManager.imagesDirectory, withIntermediateDirectories: true)
                guard let imageData = newImage.pngData() else {
                    showValidationAlert = true
                    return
                }
                if let existingItem = existingItem, existingItem.imageName != fileName {
                    let oldURL = FileManager.imagesDirectory.appendingPathComponent(existingItem.imageName)
                    if FileManager.default.fileExists(atPath: oldURL.path) {
                        try? FileManager.default.removeItem(at: oldURL)
                    }
                }
                try imageData.write(to: fileURL)
                finalImageName = fileName
                ImageCacheManager.shared.invalidateCache(for: fileName)
            } catch {
                print("❌ Error saving image: \(error)")
                showValidationAlert = true
                return
            }
        }

        // ✅ 核心改動：傳入 categoryID（UUID）而非 category name
        // categoryID 此時一定有值（isFormValid 已確保）
        let item = Item(
            id: itemId,
            imageName: finalImageName,
            brand: brand,
            categoryID: categoryID ?? categoryStore.categories.first!.id,
            name: name,
            price: priceWithDollar(price),
            date: useDate ? selectedDate : existingItem?.date,
            createdAt: existingItem?.createdAt ?? Date(),
            updatedAt: Date()
        )

        onComplete(item)
    }

    func isFormValid() -> Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !brand.trimmingCharacters(in: .whitespaces).isEmpty &&
        categoryID != nil &&        // ✅ 改為檢查 UUID 是否有值
        !price.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - Brand Chips
@available(iOS 16.0, *)
private struct BrandChipsView: View {
    @ObservedObject var brandStore: BrandStore
    @Binding var selectedBrand: String
    @Environment(\.colorScheme) var colorScheme

    private let addColor: Color = Color(UIColor.label)

    var body: some View {
        FlowLayout(spacing: 8, runSpacing: 8) {
            ForEach(brandStore.brands, id: \.self) { b in
                RemovableChip(
                    title: b,
                    isSelected: selectedBrand == b,
                    colorScheme: colorScheme,
                    onSelect: { selectedBrand = b },
                    onRemove: {
                        if let idx = brandStore.brands.firstIndex(of: b) {
                            brandStore.brands.remove(at: idx)
                            if selectedBrand == b { selectedBrand = "" }
                        }
                    }
                )
            }

            Button(action: addTag) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Add Tag")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(addColor)
                .foregroundColor(Color(UIColor.systemBackground))
                .clipShape(Capsule())
                .shadow(radius: 1, y: 1)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: brandStore.brands)
    }

    private func addTag() {
        let trimmed = selectedBrand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let exists = brandStore.brands.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        guard !exists else { return }
        brandStore.brands.append(trimmed)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

private struct RemovableChip: View {
    let title: String
    let isSelected: Bool
    let colorScheme: ColorScheme
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                Text(title).font(.subheadline)
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .accessibilityLabel("Remove \(title)")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(colorScheme == .dark ? 0.25 : 0.18))
        .foregroundColor(colorScheme == .dark ? .white : .black)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(isSelected ? Color.black : Color.clear, lineWidth: 2)
        )
    }
}

private struct LabeledTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var prefix: String? = nil
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote).foregroundColor(.secondary)
            HStack(spacing: 8) {
                if let prefix { Text(prefix).foregroundColor(.gray) }
                TextField(placeholder, text: $text)
                    .keyboardType(keyboard)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - 內建去背
private extension AddItemView {
    @MainActor
    func removeBackground(from image: UIImage) async -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        do {
            try handler.perform([request])
            guard let obs = request.results?.first as? VNInstanceMaskObservation else { return nil }
            let maskBuffer = try obs.generateScaledMaskForImage(forInstances: obs.allInstances, from: handler)
            let maskCI  = CIImage(cvPixelBuffer: maskBuffer)
            let extent  = ciImage.extent
            let clearBG = CIImage(color: .clear).cropped(to: extent)
            let cut = CIFilter.blendWithMask()
            cut.inputImage      = ciImage
            cut.maskImage       = maskCI
            cut.backgroundImage = clearBG
            guard let output = cut.outputImage else { return nil }
            let ctx = CIContext()
            guard let cg = ctx.createCGImage(output, from: output.extent) else { return nil }
            return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
        } catch {
            print("removeBackground error: \(error)")
            return nil
        }
    }
}
