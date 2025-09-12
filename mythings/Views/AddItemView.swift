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
    @State private var category: String = ""
    @State private var price: String = ""
    @State private var showValidationAlert = false

    // 原本就有的：控制相簿 / 分類 sheet
    @State private var showImagePicker = false           // 保留，但不再直接用它；由選單控制
    @State private var showCategorySheet = false         // ✅ 點分類按鈕只開這個

    // 新增：影像來源選單 + 相機
    @State private var showImageSourceMenu = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false

    // Edit Photo（資料驅動；用 Bool sheet）
    @State private var pendingPhoto: UIImage?
    @AppStorage("pref.removeBG") private var prefRemoveBG: Bool = true

    // Date (optional)
    @State private var useDate = false
    @State private var selectedDate = Date()

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

        // 相簿
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


        // 相機
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


        // Edit Photo（可選是否去背）
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


        // ✅ 只在外部有需求時才會開 Manage 頁（不影響分類按鈕）
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
        
        // iOS 17 新式 onChange（零參數）
        .onChange(of: showManageCategories) {
            if !showManageCategories {
                let exists = categoryStore.categories.contains { $0.name == category }
                if !exists {
                    category = categoryStore.categories.first?.name ?? ""
                }
            }
        }

        // 影像來源選單：相簿 / 拍照 / 移除
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

    // ✅ 恢復原本行為：只開 categorySheet
    var categoryButton: some View {
        Button { showCategorySheet = true } label: {
            let emoji = categoryStore.categories.first(where: { $0.name == category })?.emoji ?? "🧩"
            HStack(spacing: 8) {
                Text(emoji)
                Text(category.isEmpty ? "Select Category" : category)
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
                .onTapGesture { showImageSourceMenu = true }   // ← 用選單（相簿/拍照）
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo").font(.system(size: 40))
                Text("Tap to add image").font(.subheadline).foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture { showImageSourceMenu = true }       // ← 用選單（相簿/拍照）
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
                .background(Color.primary)
                .foregroundColor(Color(UIColor.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 28))
        }
        .padding(.top, 10)
    }

    // ✅ 保持你原來的 categorySheet
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
                            category = c.name
                            showCategorySheet = false
                        } label: {
                            HStack(spacing: 12) {
                                Text(c.emoji)
                                Text(c.name)
                                    .foregroundColor(.primary)
                                if c.name == category {
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
            name = item.name
            brand = item.brand
            category = item.category
            price = item.price.replacingOccurrences(of: "$", with: "")
            if let image = UIImage(contentsOfFile: FileManager.documentsDirectory
                .appendingPathComponent(item.imageName).path) {
                selectedImage = image
            }
            if let d = item.date {
                useDate = true
                selectedDate = d
            } else {
                useDate = false
            }
        } else if !categoryStore.categories.isEmpty {
            category = categoryStore.categories[0].name
            useDate = false
        }
    }

    func priceWithDollar(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("$") ? trimmed : "$" + trimmed
    }

    // 在 AddItemView 中修正 saveTapped 方法
    private func saveTapped() {
        if isFormValid() {
            guard let selectedImage else { return }
            
            // 🔧 使用統一的檔名格式，並確保路徑正確
            let itemId = existingItem?.id ?? UUID()
            let fileName = "\(itemId.uuidString).png"  // 統一格式：UUID.png
            let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsDir.appendingPathComponent(fileName)
            
            do {
                // 🔧 確保有 PNG 資料
                guard let imageData = selectedImage.pngData() else {
                    print("❌ Failed to convert image to PNG data")
                    showValidationAlert = true
                    return
                }
                
                // 🔧 如果是編輯模式且檔名改變，刪除舊檔案
                if let existingItem = existingItem, existingItem.imageName != fileName {
                    let oldFileURL = documentsDir.appendingPathComponent(existingItem.imageName)
                    if FileManager.default.fileExists(atPath: oldFileURL.path) {
                        try? FileManager.default.removeItem(at: oldFileURL)
                        print("🗑️ Removed old image: \(existingItem.imageName)")
                    }
                }
                
                // 🔧 寫入新檔案
                try imageData.write(to: fileURL)
                print("💾 Saved image: \(fileName) (size: \(imageData.count) bytes)")
                
                // 🔧 驗證檔案確實被寫入
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
                    if let fileSize = attributes?[.size] as? Int64 {
                        print("✅ File verification passed: \(fileName) (\(fileSize) bytes)")
                    } else {
                        print("⚠️ File exists but size unknown: \(fileName)")
                    }
                } else {
                    print("❌ File save failed: \(fileName)")
                    showValidationAlert = true
                    return
                }
                
            } catch {
                print("❌ Error saving image: \(error)")
                showValidationAlert = true
                return
            }
            
            // 創建 Item 物件
            let item = Item(
                id: itemId,
                imageName: fileName,
                brand: brand,
                category: category,
                name: name,
                price: priceWithDollar(price),
                date: useDate ? selectedDate : nil
            )
            
            // 🔧 清除相關的圖片快取
            ImageCacheManager.shared.invalidateCache(for: fileName)
            
            // 完成回調
            onComplete(item)
            
        } else {
            showValidationAlert = true
        }
    }
    func isFormValid() -> Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !brand.trimmingCharacters(in: .whitespaces).isEmpty &&
        !category.isEmpty &&
        !price.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - Brand Chips（換行 + 新增/刪除；選取以黑色框線高亮）
@available(iOS 16.0, *)
private struct BrandChipsView: View {
    @ObservedObject var brandStore: BrandStore
    @Binding var selectedBrand: String
    @Environment(\.colorScheme) var colorScheme

    private let addColor: Color = .primary

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

// 一顆可刪除的 chip（選取時用黑色框線高亮）
private struct RemovableChip: View {
    let title: String
    let isSelected: Bool
    let colorScheme: ColorScheme
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                Text(title)
                    .font(.subheadline)
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

// MARK: - Reusable labeled text field
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
