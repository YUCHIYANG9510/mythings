import SwiftUI
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - FlowLayout (iOS 16+)
@available(iOS 16.0, *)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var runSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(ProposedViewSize(width: nil, height: nil))
            if x > 0 && x + size.width > maxWidth { x = 0; y += lineHeight + runSpacing; lineHeight = 0 }
            x += size.width + (x > 0 ? spacing : 0)
            lineHeight = max(lineHeight, size.height)
        }
        y += lineHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(ProposedViewSize(width: nil, height: nil))
            if x > bounds.minX && x + size.width > bounds.minX + maxWidth { x = bounds.minX; y += lineHeight + runSpacing; lineHeight = 0 }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
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
    @EnvironmentObject private var pm: PurchasesManager
    var onComplete: (Item) -> Void

    @State private var name: String = ""
    @State private var brand: String = ""
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

    // ✅ 快速新增 category 用的狀態
    @State private var newCategoryName: String = ""
    @State private var newCategoryEmoji: String = "📦"
    @State private var showEmojiPickerForNew = false
    @State private var showPaywallFromCategory = false  // ✅ 從 category sheet 觸發的付費牆

    private var selectedCategoryName: String {
        guard let id = categoryID else { return "" }
        return categoryStore.name(for: id)
    }

    private var selectedCategoryEmoji: String {
        guard let id = categoryID else { return "🧩" }
        return categoryStore.category(for: id)?.emoji ?? "🧩"
    }
    
    // MARK: - Quick Add Category Helper
    
    /// 快速新增：存入 CategoryStore 並自動選中（含免費版數量限制）
    private func addQuickCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // ✅ 內聯重複檢查邏輯（繞過方法調用問題）
        // 若名稱已存在，直接選中，不重複新增
        if let existing = categoryStore.categories.first(where: { 
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed.lowercased() 
        }) {
            categoryID = existing.id
            newCategoryName = ""
            showCategorySheet = false
            return
        }

        // ✅ 免費版上限檢查（同 ManageCategoriesView 邏輯）
        guard pm.canAddCategory(currentCount: categoryStore.categories.count) else {
            // 先關 category sheet，再開付費牆（避免 sheet 衝突）
            showCategorySheet = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                showPaywallFromCategory = true
            }
            return
        }

        // ✅ 內聯新增邏輯（繞過方法調用問題）
        let newCategory = Category(name: trimmed, emoji: newCategoryEmoji)
        categoryStore.categories.append(newCategory)
        
        categoryID = categoryStore.categories.last?.id
        newCategoryName = ""
        newCategoryEmoji = "📦"
        showCategorySheet = false
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
            .navigationTitle(existingItem == nil ? L("add_item") : L("edit_item"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L("cancel")) { dismiss() }.foregroundColor(.secondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("save")) { saveTapped() }.foregroundColor(.secondary)
                }
            }
        }

        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker(
                selectedImage: Binding<UIImage?>(get: { nil }, set: { if let img = $0 { pendingPhoto = img } }),
                shouldRemoveBackground: false
            )
        }

        .sheet(isPresented: $showCamera) {
            CameraPicker(
                selectedImage: Binding<UIImage?>(get: { nil }, set: { if let img = $0 { pendingPhoto = img } })
            )
        }

        .sheet(isPresented: Binding(get: { pendingPhoto != nil }, set: { if !$0 { pendingPhoto = nil } })) {
            if let img = pendingPhoto {
                EditPhotoView(
                    original: img,
                    removeBG: { image in await removeBackground(from: image) },
                    onDone: { finalImage in selectedImage = finalImage; pendingPhoto = nil },
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

        // ✅ 付費牆：掛在主 body，不受 categorySheet dismiss 影響
        .sheet(isPresented: $showPaywallFromCategory) {
            PaywallView().environmentObject(pm)
        }

        .onAppear(perform: configureInitialValues)

        .alert(L("required_fields"), isPresented: $showValidationAlert) {
            Button(L("ok"), role: .cancel) {}
        } message: {
            Text(L("please_fill_required"))
        }

        .sheet(isPresented: $showCategorySheet) {
            categorySheet
        }

        .onChange(of: showManageCategories) {
            if !showManageCategories {
                if let id = categoryID {
                    if !categoryStore.categories.contains(where: { $0.id == id }) {
                        categoryID = categoryStore.categories.first?.id
                    }
                } else {
                    categoryID = categoryStore.categories.first?.id
                }
            }
        }

        .confirmationDialog(L("change_image"), isPresented: $showImageSourceMenu, titleVisibility: .visible) {
            Button(L("choose_from_library")) { showPhotoPicker = true }
            Button(L("take_photo")) { showCamera = true }
            if selectedImage != nil {
                Button(L("delete"), role: .destructive) { selectedImage = nil }
            }
            Button(L("cancel"), role: .cancel) {}
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
                Text(selectedCategoryEmoji)
                Text(categoryID == nil ? L("select_category") : selectedCategoryName)
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
                .resizable().scaledToFit()
                .frame(maxWidth: .infinity).frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .onTapGesture { showImageSourceMenu = true }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo").font(.system(size: 40))
                Text(L("select_image")).font(.subheadline).foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity).frame(height: 220)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture { showImageSourceMenu = true }
        }
    }

    var titleField: some View { 
        LabeledTextField(title: L("item_name"), placeholder: L("item_name_placeholder"), text: $name) 
    }

    var priceField: some View {
        LabeledTextField(title: L("price"), placeholder: L("price_placeholder"), text: $price, keyboard: .decimalPad, prefix: "$")
    }

    @ViewBuilder var brandSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("brand")).font(.footnote).foregroundColor(.secondary)
            VStack(spacing: 16) {
                TextField(L("brand_placeholder"), text: $brand)
                    .textInputAutocapitalization(.words)
                    .padding(.horizontal, 14).frame(height: 48)
                    .background(fieldBG).clipShape(RoundedRectangle(cornerRadius: 14))
                BrandChipsView(brandStore: brandStore, selectedBrand: $brand)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    var dateSection: some View {
        VStack(spacing: 12) {
            HStack {
                Label(L("purchase_date"), systemImage: "calendar").labelStyle(.titleAndIcon)
                Spacer()
                Toggle("", isOn: $useDate).labelsHidden()
            }
            .padding().background(fieldBG).clipShape(RoundedRectangle(cornerRadius: 14))
            if useDate {
                DatePicker(L("purchase_date"), selection: $selectedDate, displayedComponents: [.date])
                    .datePickerStyle(.graphical).tint(.appPrimary).padding(.top, -8)
            }
        }
    }

    var saveButton: some View {
        Button { saveTapped() } label: {
            Text(L("save")).font(.headline)
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(Color(UIColor.label))
                .foregroundColor(Color(UIColor.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 28))
        }
        .padding(.top, 10)
    }

    // MARK: - Category Sheet（含快速新增）
    @ViewBuilder
    var categorySheet: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── 現有分類清單 ──
                // ✅ 若無分類，不顯示 List（移除空狀態）
                if !categoryStore.categories.isEmpty {
                    List {
                        ForEach(categoryStore.categories) { c in
                            Button {
                                categoryID = c.id
                                showCategorySheet = false
                            } label: {
                                HStack(spacing: 12) {
                                    Text(c.emoji)
                                    Text(c.name).foregroundColor(.primary)
                                    if c.id == categoryID {
                                        Spacer()
                                        Image(systemName: "checkmark").foregroundColor(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.insetGrouped)
                }

                // ── 快速新增列 ──
                // ✅ 若無分類，此區塊會自動成為主要內容
                QuickAddCategoryRow(
                    emoji: $newCategoryEmoji,
                    name: $newCategoryName,
                    showEmojiPicker: $showEmojiPickerForNew,
                    isAtLimit: !pm.canAddCategory(currentCount: categoryStore.categories.count),
                    onAdd: { addQuickCategory() },
                    onUpgrade: {
                        // ✅ 關 category sheet，延後開付費牆（避免 sheet 轉場衝突）
                        showCategorySheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showPaywallFromCategory = true
                        }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                // ✅ 當沒有分類時，使用 Spacer 讓快速新增列保持在頂部
                if categoryStore.categories.isEmpty {
                    Spacer()
                }
            }
            .navigationTitle(L("category"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("done")) { showCategorySheet = false }
                }
            }
        }
        .presentationDetents([.fraction(0.7)])
        .presentationCornerRadius(40)
        .sheet(isPresented: $showEmojiPickerForNew) {
            EmojiPickerView(selected: $newCategoryEmoji)
                .presentationDetents([.fraction(0.7)])
                .presentationCornerRadius(40)
        }
    }
}

// MARK: - QuickAddCategoryRow
/// 底部的快速新增列：
/// - 免費版已達上限 → 顯示 "Upgrade to add new category" 提示，輸入框 disable
/// - 否則正常顯示 emoji + 輸入框 + 新增按鈕
private struct QuickAddCategoryRow: View {
    @Binding var emoji: String
    @Binding var name: String
    @Binding var showEmojiPicker: Bool
    let isAtLimit: Bool
    let onAdd: () -> Void
    let onUpgrade: () -> Void   // ✅ 達到上限時點擊觸發付費牆
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if isAtLimit {
            // ── 已達上限：顯示升級提示 + 保留 + 按鈕觸發付費牆 ──
            HStack(spacing: 10) {
                Button(action: onUpgrade) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.subheadline)
                        Text(L("upgrade") + " " + L("add_category"))
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                // ✅ + 按鈕點了直接觸發付費牆
                Button(action: onUpgrade) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
            }
        } else {
            // ── 正常新增列 ──
            HStack(spacing: 10) {
                Button { showEmojiPicker = true } label: {
                    Text(emoji)
                        .font(.system(size: 22))
                        .frame(width: 50, height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                }
                .buttonStyle(.plain)

                TextField(L("category_name_placeholder"), text: $name)
                    .submitLabel(.done)
                    .onSubmit { if !name.trimmingCharacters(in: .whitespaces).isEmpty { onAdd() } }
                    .padding(.horizontal, 12)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )

                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(name.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.primary)
                }
                .buttonStyle(.plain)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

// MARK: - Logic
private extension AddItemView {
    func configureInitialValues() {
        if let item = existingItem {
            name = item.name
            brand = item.brand
            categoryID = item.categoryID
            price = item.price.replacingOccurrences(of: "$", with: "")
            if let img = loadImage(named: item.imageName) { selectedImage = img } else { selectedImage = nil }
            if let d = item.date { useDate = true; selectedDate = d } else { useDate = false }
        } else if !categoryStore.categories.isEmpty {
            categoryID = categoryStore.categories.first?.id
            useDate = false
        }
    }

    func loadImage(named fileName: String) -> UIImage? {
        let newURL = FileManager.imagesDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: newURL.path), let img = UIImage(contentsOfFile: newURL.path) { return img }
        let oldURL = FileManager.documentsDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: oldURL.path), let img = UIImage(contentsOfFile: oldURL.path) { return img }
        if !fileName.lowercased().hasSuffix(".png") {
            let withExt = fileName + ".png"
            let newURL2 = FileManager.imagesDirectory.appendingPathComponent(withExt)
            if FileManager.default.fileExists(atPath: newURL2.path), let img = UIImage(contentsOfFile: newURL2.path) { return img }
            let oldURL2 = FileManager.documentsDirectory.appendingPathComponent(withExt)
            if FileManager.default.fileExists(atPath: oldURL2.path), let img = UIImage(contentsOfFile: oldURL2.path) { return img }
        }
        return nil
    }

    func priceWithDollar(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("$") ? trimmed : "$" + trimmed
    }
    
    func isFormValid() -> Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !brand.trimmingCharacters(in: .whitespaces).isEmpty &&
        categoryID != nil &&
        !price.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func saveTapped() {
        guard isFormValid() else { showValidationAlert = true; return }
        let itemId = existingItem?.id ?? UUID()
        var finalImageName = existingItem?.imageName ?? "\(itemId.uuidString).png"

        if let newImage = selectedImage {
            let fileName = "\(itemId.uuidString).png"
            let fileURL = FileManager.imagesDirectory.appendingPathComponent(fileName)
            do {
                try FileManager.default.createDirectory(at: FileManager.imagesDirectory, withIntermediateDirectories: true)
                guard let imageData = newImage.pngData() else { showValidationAlert = true; return }
                if let existingItem, existingItem.imageName != fileName {
                    let oldURL = FileManager.imagesDirectory.appendingPathComponent(existingItem.imageName)
                    if FileManager.default.fileExists(atPath: oldURL.path) { try? FileManager.default.removeItem(at: oldURL) }
                }
                try imageData.write(to: fileURL)
                finalImageName = fileName
                ImageCacheManager.shared.invalidateCache(for: fileName)
            } catch { showValidationAlert = true; return }
        }

        // ✅ Bug 1 fix：避免 force unwrap crash
        // isFormValid() 確保 categoryID != nil，但 categories 可能是空陣列
        guard let resolvedCategoryID = categoryID ?? categoryStore.categories.first?.id else {
            showValidationAlert = true
            return
        }

        let item = Item(
            id: itemId,
            imageName: finalImageName,
            brand: brand,
            categoryID: resolvedCategoryID,
            name: name,
            price: priceWithDollar(price),
            date: useDate ? selectedDate : existingItem?.date,
            createdAt: existingItem?.createdAt ?? Date(),
            updatedAt: Date()
        )
        
        // ✅ Category 更新問題修正：
        // 在呼叫 onComplete 之前，先確保 JSON 檔案已經更新
        // 這樣當 iCloud sync 完成後觸發 loadItemsFromLocal() 時，
        // 會載入到最新的資料，而不是覆蓋掉剛才的更改
        saveItemDirectlyToFile(item)
        
        onComplete(item)
    }
    
    /// 直接將 item 寫入 JSON 檔案，確保持久化儲存與記憶體同步
    /// 這樣可以避免 iCloud sync 完成後重新載入時覆蓋掉未儲存的更改
    func saveItemDirectlyToFile(_ updatedItem: Item) {
        let savePath = FileManager.documentsDirectory.appendingPathComponent("items.json")
        
        do {
            // 讀取現有的所有 items
            var items: [Item] = []
            if FileManager.default.fileExists(atPath: savePath.path) {
                let data = try Data(contentsOf: savePath)
                items = try JSONDecoder().decode([Item].self, from: data)
            }
            
            // 更新或新增這個 item
            if let index = items.firstIndex(where: { $0.id == updatedItem.id }) {
                // ✅ Ensure the updatedAt timestamp is very recent to prevent overwrite during sync
                var freshItem = updatedItem
                freshItem.updatedAt = Date()
                items[index] = freshItem
                
                print("✅ Updated existing item: \(freshItem.name) with category \(categoryStore.name(for: freshItem.categoryID))")
                print("   Category ID: \(freshItem.categoryID)")
                print("   Updated at: \(freshItem.updatedAt)")
            } else {
                items.insert(updatedItem, at: 0)
                print("✅ Added new item: \(updatedItem.name) with category \(categoryStore.name(for: updatedItem.categoryID))")
            }
            
            // 寫回檔案
            let encoded = try JSONEncoder().encode(items)
            try encoded.write(to: savePath)
            
        } catch {
            print("❌ Failed to save item directly to file: \(error)")
        }
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
                    title: b, isSelected: selectedBrand == b, colorScheme: colorScheme,
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
                HStack(spacing: 8) { Image(systemName: "plus"); Text(L("add_tag")) }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(addColor)
                    .foregroundColor(Color(UIColor.systemBackground))
                    .clipShape(Capsule()).shadow(radius: 1, y: 1)
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
        guard !brandStore.brands.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        brandStore.brands.append(trimmed)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

private struct RemovableChip: View {
    let title: String; let isSelected: Bool; let colorScheme: ColorScheme
    let onSelect: () -> Void; let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) { Text(title).font(.subheadline) }.buttonStyle(.plain)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.gray)
                    .accessibilityLabel("Remove \(title)")
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.gray.opacity(colorScheme == .dark ? 0.25 : 0.18))
        .foregroundColor(colorScheme == .dark ? .white : .black)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(isSelected ? Color.black : Color.clear, lineWidth: 2))
    }
}

private struct LabeledTextField: View {
    let title: String; let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var prefix: String? = nil
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote).foregroundColor(.secondary)
            HStack(spacing: 8) {
                if let prefix { Text(prefix).foregroundColor(.gray) }
                TextField(placeholder, text: $text).keyboardType(keyboard)
            }
            .padding(.horizontal, 14).frame(height: 48)
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
            let maskCI = CIImage(cvPixelBuffer: maskBuffer)
            let extent = ciImage.extent
            let clearBG = CIImage(color: .clear).cropped(to: extent)
            let cut = CIFilter.blendWithMask()
            cut.inputImage = ciImage; cut.maskImage = maskCI; cut.backgroundImage = clearBG
            guard let output = cut.outputImage else { return nil }
            let ctx = CIContext()
            guard let cg = ctx.createCGImage(output, from: output.extent) else { return nil }
            return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
        } catch { return nil }
    }
}
