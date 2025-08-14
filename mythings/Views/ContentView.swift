//
//  ContentView.swift
//  mythings
//
//  Created by Designer on 2025/4/23.
//

import SwiftUI
import PhotosUI
import UIKit
import Foundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

enum NavigationTarget: Hashable {
    case settings
}

enum ViewMode {
    case grid
    case list
}

class ImageCacheManager: ObservableObject {
    static let shared = ImageCacheManager()
    @Published var cacheInvalidationTrigger = UUID()
    
    func invalidateCache() {
        cacheInvalidationTrigger = UUID()
    }
}

struct ContentView: View {
    @State private var selectedCategory = "All"
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var showActionSheet = false
    @State private var selectedImage: UIImage?
    @State private var items: [Item] = []
    @State private var selectedItem: Item?
    @State private var editingItem: Item?
    @State private var showManageCategories = false
    @State private var isAddingNewItem = false
    @State private var path: [NavigationTarget] = []
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var viewMode: ViewMode = .grid
    @ObservedObject var categoryStore: CategoryStore
    @StateObject private var brandStore = BrandStore()
    @State private var isRemovingBackground = false
    // 拖曳時預熱 Core Haptics
    @State private var didPrepareHaptic = false
    // 根據滑動速度估算的力度（0.5~1.0）
    @State private var lastSwipeStrength: Double = 0.75

    
    // 🔹 用於原生分頁的索引，會與 selectedCategory 互相同步
    @State private var selectedPage: Int = 0
    
    private var savePath: URL {
        FileManager.documentsDirectory.appendingPathComponent("items.json")
    }
    
    // Haptic：選擇型回饋（適合分頁、選項切換）
    private let selectionHaptic = UISelectionFeedbackGenerator()
   


    var categoryNames: [String] {
        var names = ["All"]
        names.append(contentsOf: categoryStore.categories.map { $0.name })
        return names
    }
    
    // 依分類與搜尋字過濾
    private func itemsFor(category: String) -> [Item] {
        let categoryFiltered = (category == "All") ? items : items.filter { $0.category == category }
        guard !searchText.isEmpty else { return categoryFiltered }
        return categoryFiltered.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.brand.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                VStack {
                    HeaderView(
                        isSearching: $isSearching,
                        text: $searchText,
                        viewMode: $viewMode,
                        navigateToSettings: { path.append(.settings) }
                    )
                    
                    CategoryScrollView(
                        categoryNames: categoryNames,
                        selectedCategory: $selectedCategory
                    )
                    
                    // ✅ 原生分頁：左右滑動超順
                    CategoryPager(
                        categoryNames: categoryNames,
                        selectedPage: $selectedPage,
                        selectedCategory: $selectedCategory,
                        viewMode: viewMode,
                        allItems: items,
                        searchText: searchText,
                        selectedItem: $selectedItem,
                        editingItem: $editingItem,
                        items: $items,
                        saveItems: saveItems
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 6, coordinateSpace: .local)
                            .onChanged { value in
                                // 偵測明顯水平拖曳 → 預熱一次 Haptics
                                if !didPrepareHaptic,
                                   abs(value.translation.width) > abs(value.translation.height),
                                   abs(value.translation.width) > 8 {
                                    HapticsManager.shared.prepare()
                                    didPrepareHaptic = true
                                }
                            }
                            .onEnded { value in
                                // 估算「速度」→ 轉成強度（0.5~1.0）
                                let dx = value.predictedEndTranslation.width - value.translation.width
                                let approxSpeed = min(1.0, max(0.0, Double(abs(dx) / 140.0))) // 140 可微調
                                lastSwipeStrength = 0.5 + 0.5 * approxSpeed
                                didPrepareHaptic = false
                            }
                    )
                }
                
                FloatingAddMenu(
                    isOpen: $showActionSheet,
                    showCamera: $showCamera,
                    showImagePicker: $showImagePicker
                )
            }
            .navigationDestination(for: NavigationTarget.self) { target in
                switch target {
                case .settings:
                    SettingsView(categoryStore: categoryStore)
                }
            }
        }
        .accentColor(.primary)
        .sheet(isPresented: $showManageCategories) {
            ManageCategoriesView(categoryStore: categoryStore)
        }
        .sheet(isPresented: $showImagePicker) {
            PhotoPicker(selectedImage: $selectedImage, shouldRemoveBackground: false)
                .onDisappear {
                    guard let img = selectedImage else { return }
                    Task {
                        isRemovingBackground = true
                        if let cut = await removeBackground(from: img) { selectedImage = cut }
                        isRemovingBackground = false
                        isAddingNewItem = (selectedImage != nil)
                    }
                }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker(selectedImage: $selectedImage)
                .onDisappear {
                    guard let img = selectedImage else { return }
                    Task {
                        isRemovingBackground = true
                        if let cut = await removeBackground(from: img) { selectedImage = cut }
                        isRemovingBackground = false
                        isAddingNewItem = (selectedImage != nil)
                    }
                }
        }
        .sheet(item: $selectedItem) { item in
            ItemDetailView(item: item)
                .presentationDetents([.fraction(0.7)])
                .presentationCornerRadius(40)
        }
        .sheet(item: $editingItem) { editing in
            AddItemView(
                selectedImage: $selectedImage,
                existingItem: editing,
                categoryStore: categoryStore,
                brandStore: brandStore,
                showManageCategories: $showManageCategories
            ) { newItem in
                if let index = items.firstIndex(where: { $0.id == editing.id }) {
                    items[index] = newItem
                }
                editingItem = nil
                selectedImage = nil
                saveItems()
            }
        }
        .sheet(isPresented: $isAddingNewItem) {
            AddItemView(
                selectedImage: $selectedImage,
                existingItem: nil,
                categoryStore: categoryStore,
                brandStore: brandStore,
                showManageCategories: $showManageCategories
            ) { newItem in
                items.append(newItem)
                selectedImage = nil
                isAddingNewItem = false
                saveItems()
            }
        }
        .onAppear {
            loadItems()
            if let idx = categoryNames.firstIndex(of: selectedCategory) {
                selectedPage = idx
            }
        }
        .onChange(of: selectedPage) { _, newValue in
            if categoryNames.indices.contains(newValue) {
                // ✅ 分頁 settle 的瞬間：用 Core Haptics 播放更沉的觸感
                HapticsManager.shared.pageSnap(strength: lastSwipeStrength)

                let cat = categoryNames[newValue]
                if cat != selectedCategory { selectedCategory = cat }
            }
        }
        .onChange(of: selectedCategory) { _, newValue in
            if let idx = categoryNames.firstIndex(of: newValue), idx != selectedPage {
                selectedPage = idx
            }
        }
    }
    
    private func saveItems() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: savePath)
        } catch {
            print("儲存失敗：\(error)")
        }
    }
    
    private func loadItems() {
        do {
            let data = try Data(contentsOf: savePath)
            items = try JSONDecoder().decode([Item].self, from: data)
        } catch {
            print("讀取失敗或尚無資料：\(error)")
        }
    }
    
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

struct CategoryPager: View {
    let categoryNames: [String]
    @Binding var selectedPage: Int
    @Binding var selectedCategory: String
    let viewMode: ViewMode
    let allItems: [Item]
    let searchText: String
    
    @Binding var selectedItem: Item?
    @Binding var editingItem: Item?
    @Binding var items: [Item]
    let saveItems: () -> Void
    
    private func itemsFor(category: String) -> [Item] {
        let base = (category == "All") ? allItems : allItems.filter { $0.category == category }
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.brand.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        TabView(selection: $selectedPage) {
            ForEach(Array(categoryNames.enumerated()), id: \.offset) { index, category in
                Group {
                    if viewMode == .grid {
                        ItemsGridView(
                            filteredItems: itemsFor(category: category),
                            selectedItem: $selectedItem,
                            editingItem: $editingItem,
                            items: $items,
                            saveItems: saveItems,
                            isScrollDisabled: false
                        )
                    } else {
                        ItemsListView(
                            filteredItems: itemsFor(category: category),
                            selectedItem: $selectedItem,
                            editingItem: $editingItem,
                            items: $items,
                            saveItems: saveItems,
                            isScrollDisabled: false
                        )
                    }
                }
                .tag(index)
                .contentShape(Rectangle())
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: selectedPage) { _, newValue in
            if categoryNames.indices.contains(newValue) {
                let cat = categoryNames[newValue]
                if cat != selectedCategory { selectedCategory = cat }
            }
        }
        .onChange(of: selectedCategory) { _, newValue in
            if let idx = categoryNames.firstIndex(of: newValue), idx != selectedPage {
                selectedPage = idx
            }
        }

        .background(TabViewScrollConfigurator())
    }
}


/// 微調 TabView(.page) 的 UIScrollView 手感（可依喜好調整）
private struct TabViewScrollConfigurator: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        DispatchQueue.main.async { tune(in: v) }
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async { tune(in: uiView) }
    }
    private func tune(in holder: UIView) {
        var p: UIView? = holder.superview
        while let cur = p {
            if let scroll = cur as? UIScrollView {
                scroll.isPagingEnabled = true
                scroll.showsHorizontalScrollIndicator = false
                scroll.showsVerticalScrollIndicator = false
                scroll.alwaysBounceVertical = false
                scroll.bounces = true              // 若喜歡邊緣彈性可改 true
                scroll.decelerationRate = .fast     // 更俐落
                break
            }
            p = cur.superview
        }
    }
}
struct HeaderView: View {
    @Binding var isSearching: Bool
    @Binding var text: String
    @Binding var viewMode: ViewMode
    var navigateToSettings: () -> Void
    
    var body: some View {
        HStack {
            if isSearching {
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        TextField("搜尋名稱或品牌", text: $text)
                            .textFieldStyle(PlainTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        if !text.isEmpty {
                            Button(action: {
                                text = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    
                    Button("Cancel") {
                        withAnimation {
                            isSearching = false
                            text = ""
                        }
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
                .padding(.horizontal)
                
            } else {
                Button(action: {
                    navigateToSettings()
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .padding(.leading)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Text("My Things")
                    .font(.title3)
                    .bold()
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        viewMode = viewMode == .grid ? .list : .grid
                    }
                }) {
                    Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
                .padding(.trailing, 8)
                
                Button(action: {
                    withAnimation {
                        isSearching = true
                    }
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .padding(.trailing)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.vertical)
    }
}


struct ItemsListView: View {
    let filteredItems: [Item]
    @Binding var selectedItem: Item?
    @Binding var editingItem: Item?
    @Binding var items: [Item]
    let saveItems: () -> Void
    var isScrollDisabled: Bool = false
    var body: some View {
        ScrollView {
            if filteredItems.isEmpty {
                EmptyStateView()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredItems) { item in
                        ListItemCell(
                            item: item,
                            selectedItem: $selectedItem,
                            editingItem: $editingItem,
                            items: $items,
                            saveItems: saveItems
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .scrollDisabled(isScrollDisabled)
        .padding(.top, 16)
    }
}

struct ListItemCell: View {
    let item: Item
    @Binding var selectedItem: Item?
    @Binding var editingItem: Item?
    @Binding var items: [Item]
    let saveItems: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ListItemImageView(imageName: item.imageName)
                .frame(width: 80, height: 80)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(item.brand) · \(item.category)")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            
            Spacer()

            if let price = Double(item.price) {
                Text("$\(formattedPrice(price))")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            } else {
                Text("$\(item.price)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .onTapGesture {
            selectedItem = item
        }
        .contextMenu {
            Button("編輯") {
                editingItem = item
            }
            Button("刪除", role: .destructive) {
                items.removeAll { $0.id == item.id }
                saveItems()
            }
        }
    }
    
    private func formattedPrice(_ price: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: price)) ?? "\(price)"
    }
}

struct ListItemImageView: View {
    let imageName: String
    @StateObject private var cacheManager = ImageCacheManager.shared
    @State private var image: UIImage?
    
    var body: some View {
        Group {
            if let image = image {
                ZStack {
                    Color(.systemGray6)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                       
                }
                .frame(width: 80, height: 80)
            } else {
                ZStack {
                    Color(.systemGray6)
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30)
                        .foregroundColor(.gray)
                }
                .frame(width: 80, height: 80)
            }
        }
        .onAppear(perform: loadImage)
        .onChange(of: cacheManager.cacheInvalidationTrigger) {
            loadImage()
        }
        .onChange(of: imageName) {
            loadImage()
        }
    }
    
    private func loadImage() {
        let imagePath = FileManager.documentsDirectory.appendingPathComponent(imageName).path
        image = UIImage(contentsOfFile: imagePath)
    }
}

struct CategoryScrollView: View {
    let categoryNames: [String]
    @Binding var selectedCategory: String
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categoryNames, id: \.self) { category in
                    Button(action: {
                        selectedCategory = category
                    }) {
                        Text(category)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .font(.caption)
                            .background(
                                selectedCategory == category ? Color.primary : Color.gray.opacity(0.2)
                            )
                            .foregroundColor(
                                selectedCategory == category ? Color.textcolor : Color.primary
                            )
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct ItemsGridView: View {
    let filteredItems: [Item]
    @Binding var selectedItem: Item?
    @Binding var editingItem: Item?
    @Binding var items: [Item]
    let saveItems: () -> Void
    var isScrollDisabled: Bool = false
    
    var body: some View {
        ScrollView {
            if filteredItems.isEmpty {
                EmptyStateView()
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(filteredItems) { item in
                        ItemCell(
                            item: item,
                            selectedItem: $selectedItem,
                            editingItem: $editingItem,
                            items: $items,
                            saveItems: saveItems
                        )
                    }
                }
                .padding()
            }
        }
        .scrollDisabled(isScrollDisabled)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "tray")
                .resizable()
                .frame(width: 40, height: 30)
                .foregroundColor(.gray)
            Text("It's empty here...")
                .foregroundColor(.gray)
                .font(.subheadline)
        }
        .padding(.top, 250)
    }
}

struct ItemCell: View {
    let item: Item
    @Binding var selectedItem: Item?
    @Binding var editingItem: Item?
    @Binding var items: [Item]
    let saveItems: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ItemImageView(imageName: item.imageName)
            
            Text("\(item.brand) · \(item.category)")
                .font(.caption)
                .foregroundColor(.gray)
            
            HStack {
                Text(item.name)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                if let price = Double(item.price) {
                    Text("$\(formattedPrice(price))")
                        .font(.caption2)
                        .foregroundColor(.gray)
                } else {
                    Text("$\(item.price)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .onTapGesture {
            selectedItem = item
        }
        .contextMenu {
            Button("編輯") {
                editingItem = item
            }
            Button("刪除", role: .destructive) {
                items.removeAll { $0.id == item.id }
                saveItems()
            }
        }
    }
    
    private func formattedPrice(_ price: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: price)) ?? "\(price)"
    }
}

struct ItemImageView: View {
    let imageName: String
    @StateObject private var cacheManager = ImageCacheManager.shared
    @State private var image: UIImage?
    
    var body: some View {
        Group {
            if let image = image {
                ZStack {
                    Color(.systemGray6)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 120)
                }
                .frame(height: 150)
                .cornerRadius(8)
            } else {
                ZStack {
                    Color(.systemGray6)
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 60)
                        .foregroundColor(.gray)
                }
                .frame(height: 150)
                .cornerRadius(8)
            }
        }
        .onAppear(perform: loadImage)
        .onChange(of: cacheManager.cacheInvalidationTrigger) {
            loadImage()
        }
        .onChange(of: imageName) {
            loadImage()
        }
    }
    
    private func loadImage() {
        let imagePath = FileManager.documentsDirectory.appendingPathComponent(imageName).path
        image = UIImage(contentsOfFile: imagePath)
    }
}




struct FloatingAddMenu: View {
    @Binding var isOpen: Bool
    @Binding var showCamera: Bool
    @Binding var showImagePicker: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var showFirstButton = false
    @State private var showSecondButton = false

    var body: some View {
        ZStack {
            if isOpen {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { toggle(false) }
            }

            VStack {
                Spacer()
                
                HStack {
                    VStack(spacing: 16) {
                        // 展開的選單按鈕
                        if isOpen {
                            HStack(spacing: 12) {
                                // 第一個按鈕 - 相簿
                                CircularIconButton(
                                    system: "photo.on.rectangle",
                                    label: "相簿",
                                    isVisible: showFirstButton
                                ) {
                                    toggle(false)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    showImagePicker = true
                                }
                                
                                // 第二個按鈕 - 拍照
                                CircularIconButton(
                                    system: "camera.fill",
                                    label: "拍照",
                                    isVisible: showSecondButton
                                ) {
                                    toggle(false)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    showCamera = true
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            ))
                        }
                        
                        // 主 FAB
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            toggle(!isOpen)
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2.bold())
                                .frame(width: 60, height: 60)
                                .foregroundStyle(colorScheme == .dark ? .black : .white)
                                .background(colorScheme == .dark ? Color.white : Color.black)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                                .scaleEffect(isOpen ? 0.9 : 1.0) // 點擊時微縮
                                .rotationEffect(.degrees(isOpen ? 45 : 0)) // 加號旋轉45度變成 X 形狀
                        }
                    }
                    .frame(width: 60)
                    .frame(width: 60)
                }
                
                Spacer()
                    .frame(height: 30)
            }
        }
        .onChange(of: isOpen) { _, newValue in
            if newValue {
                // 展開時的錯開動畫
                showFirstButton = false
                showSecondButton = false
                
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.1)) {
                    showFirstButton = true
                }
                
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.2)) {
                    showSecondButton = true
                }
            } else {
                // 收起時同時隱藏
                showFirstButton = false
                showSecondButton = false
            }
        }
    }

    private func toggle(_ open: Bool) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isOpen = open
        }
    }
}

private struct CircularIconButton: View {
    let system: String
    let label: String
    let isVisible: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.title3.bold())
                .frame(width: 60, height: 60)
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                .background(colorScheme == .dark ? Color.black : Color.white)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
        }
        .accessibilityLabel(Text(label))
        .scaleEffect(isVisible ? (isPressed ? 0.9 : 1.0) : 0.1)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isVisible)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}





#Preview {
    ContentView(categoryStore: CategoryStore())
}
