import SwiftUI

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
    @State private var showImagePicker = false
    @State private var showCategorySheet = false

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
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage)
        }
        .sheet(isPresented: $showCategorySheet) {
            categorySheet
        }
        .sheet(isPresented: $showManageCategories) {
            ManageCategoriesView(categoryStore: categoryStore)
                .presentationDetents([.large])
        }
        .onAppear(perform: configureInitialValues)
        .alert("請填寫所有欄位", isPresented: $showValidationAlert) {
            Button("OK", role: .cancel) {}
        }
    }
}

// MARK: - Sections (split to avoid type-check explosion)
private extension AddItemView {
    var fieldBG: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
    }

    var categoryButton: some View {
        Button { showCategorySheet = true } label: {
            HStack(spacing: 8) {
                Text(categoryEmoji(for: category))
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
                .onTapGesture { showImagePicker = true }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo").font(.system(size: 40))
                Text("Tap to add image").font(.subheadline).foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture { showImagePicker = true }
        }
    }

    var titleField: some View {
        LabeledTextField(title: "Title", placeholder: "", text: $name)
    }

    var priceField: some View {
        // 輸入時沒有 $，左邊固定顯示 label；儲存時補一個 $
        LabeledTextField(title: "Price",
                         placeholder: "",
                         text: $price,
                         keyboard: .decimalPad,
                         prefix: "$")
    }

    @ViewBuilder
    var brandSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Brand").font(.footnote).foregroundColor(.secondary)
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

    @ViewBuilder
    var categorySheet: some View {
        NavigationView {
            List {
                ForEach(categoryStore.categories) { c in
                    Button {
                        category = c.name
                        showCategorySheet = false
                    } label: {
                        HStack {
                            Text(categoryEmoji(for: c.name))
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
            }
            
        }
        .presentationDetents([.medium, .large])
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
            // ✅ 日期：有存就打開 toggle 並顯示
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

    func categoryEmoji(for name: String) -> String {
        let key = name.lowercased()
        if key.contains("top") || key.contains("shirt") { return "👕" }
        if key.contains("pant") || key.contains("jean") { return "👖" }
        if key.contains("shoe") || key.contains("sneaker") { return "👟" }
        if key.contains("dress") { return "👗" }
        if key.contains("bag") { return "👜" }
        return "🧩"
    }

    func priceWithDollar(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("$") ? trimmed : "$" + trimmed
    }

    func saveTapped() {
        if isFormValid() {
            guard let selectedImage else { return }
            let fileName = existingItem?.imageName ?? UUID().uuidString + ".png"
            let fileURL = FileManager.documentsDirectory.appendingPathComponent(fileName)
            if let data = selectedImage.pngData() { try? data.write(to: fileURL) }

            let item = Item(
                id: existingItem?.id ?? UUID(),
                imageName: fileName,
                brand: brand,
                category: category,
                name: name,
                price: priceWithDollar(price),
                date: useDate ? selectedDate : nil     // ✅ 寫入日期（或 nil）
            )
            ImageCacheManager.shared.invalidateCache()
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

    // Add Tag 的顏色（可改成你的品牌色）
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

            // Add Tag 也作為 chip，會跟著換行
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
                .stroke(isSelected ? Color.black : Color.clear, lineWidth: 2) // 🔥選取時黑色框線
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
                if let prefix { Text(prefix).foregroundColor(.gray) } // 固定顯示的符號
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

// MARK: - Preview
#Preview {
    AddItemView(
        selectedImage: .constant(UIImage(systemName: "photo")),
        existingItem: nil,
        categoryStore: {
            let s = CategoryStore()
            s.categories = [Category(name: "Tops"), Category(name: "Pants"), Category(name: "Shoes")]
            return s
        }(),
        brandStore: {
            let s = BrandStore()
            s.brands = ["Uniqlo", "MUJI", "Apple"]
            return s
        }(),
        showManageCategories: .constant(false)
    ) { item in
        print("Saved: \(item)")
    }
}
