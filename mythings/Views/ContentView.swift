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
    @State private var dragOffset = CGSize.zero
    @State private var path: [NavigationTarget] = []
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var viewMode: ViewMode = .grid
    @ObservedObject var categoryStore: CategoryStore
    @StateObject private var brandStore = BrandStore()
    @State private var isRemovingBackground = false
    @State private var dragVelocity: CGFloat = 0
    @State private var isDragging = false
    @State private var verticalScrollDisabled = false
    
    private enum PanLock { case none, horizontal, vertical }
    @State private var panLock: PanLock = .none
    
    // 新增的狀態變量用於傳送帶效果
    @State private var categoryTransition: CategoryTransition = .none
    @State private var nextCategory: String = ""
    @State private var previousCategory: String = ""
    
    enum CategoryTransition {
        case none
        case toNext
        case toPrevious
    }
    
    private var savePath: URL {
        FileManager.documentsDirectory.appendingPathComponent("items.json")
    }
    
    var categoryNames: [String] {
        var names = ["All"]
        names.append(contentsOf: categoryStore.categories.map { $0.name })
        return names
    }
    
    var filteredItems: [Item] {
        let categoryFiltered = selectedCategory == "All" ? items : items.filter { $0.category == selectedCategory }

        if searchText.isEmpty {
            return categoryFiltered
        } else {
            return categoryFiltered.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.brand.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var nextCategoryItems: [Item] {
        if nextCategory.isEmpty { return [] }
        let categoryFiltered = nextCategory == "All" ? items : items.filter { $0.category == nextCategory }
        return searchText.isEmpty ? categoryFiltered : categoryFiltered.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.brand.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var previousCategoryItems: [Item] {
        if previousCategory.isEmpty { return [] }
        let categoryFiltered = previousCategory == "All" ? items : items.filter { $0.category == previousCategory }
        return searchText.isEmpty ? categoryFiltered : categoryFiltered.filter {
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
                    
                    ConveyorBeltContainer(
                        viewMode: viewMode,
                        currentItems: filteredItems,
                        nextItems: nextCategoryItems,
                        previousItems: previousCategoryItems,
                        selectedItem: $selectedItem,
                        editingItem: $editingItem,
                        items: $items,
                        saveItems: saveItems,
                        dragOffset: dragOffset,
                        categoryTransition: categoryTransition,
                        verticalScrollDisabled: verticalScrollDisabled
                    )
                    .simultaneousGesture(createConveyorDragGesture())
                }
                
                FloatingAddMenu(
                    isOpen: $showActionSheet,
                    showCamera: $showCamera,
                    showImagePicker: $showImagePicker
                )
            }
            .navigationDestination(for: NavigationTarget.self) { target in
                if case .settings = target {
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
        .onAppear { loadItems() }
    }
    
    // 傳送帶拖拽手勢（方向鎖）
    private func createConveyorDragGesture() -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { gesture in
                if panLock == .none {
                    let dx = abs(gesture.translation.width)
                    let dy = abs(gesture.translation.height)
                    if dx > 10 || dy > 10 {
                        panLock = dx >= dy ? .horizontal : .vertical
                        verticalScrollDisabled = (panLock == .horizontal)
                    }
                }
                guard panLock == .horizontal else {
                    dragOffset = .zero
                    categoryTransition = .none
                    return
                }
                isDragging = true
                dragOffset = CGSize(width: gesture.translation.width, height: 0)
                dragVelocity = gesture.velocity.width
                updatePreviewCategories(for: gesture.translation.width)
            }
            .onEnded { gesture in
                let wasHorizontal = (panLock == .horizontal)
                panLock = .none
                verticalScrollDisabled = false
                isDragging = false
                guard wasHorizontal else {
                    dragOffset = .zero
                    categoryTransition = .none
                    return
                }
                let swipeThreshold: CGFloat = UIScreen.main.bounds.width * 0.2
                let velocityThreshold: CGFloat = 300
                let shouldSwipe = abs(gesture.translation.width) > swipeThreshold ||
                                  abs(gesture.velocity.width) > velocityThreshold
                if shouldSwipe && abs(gesture.translation.width) > abs(gesture.translation.height) {
                    performConveyorTransition(translationX: gesture.translation.width)
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        dragOffset = .zero
                        categoryTransition = .none
                    }
                }
            }
    }
    
    private func updatePreviewCategories(for translationX: CGFloat) {
        guard let currentIndex = categoryNames.firstIndex(of: selectedCategory) else { return }
        if translationX < -20 {
            let nextIndex = (currentIndex + 1) % categoryNames.count
            nextCategory = categoryNames[nextIndex]
            categoryTransition = .toNext
        } else if translationX > 20 {
            let prevIndex = (currentIndex - 1 + categoryNames.count) % categoryNames.count
            previousCategory = categoryNames[prevIndex]
            categoryTransition = .toPrevious
        } else {
            categoryTransition = .none
        }
    }
    
    private func performConveyorTransition(translationX: CGFloat) {
        guard let currentIndex = categoryNames.firstIndex(of: selectedCategory) else { return }
        let width = UIScreen.main.bounds.width
        let duration = 0.20
        let goingLeft = (translationX < 0)
        
        let targetCategory: String
        let transition: CategoryTransition
        if goingLeft {
            let nextIndex = (currentIndex + 1) % categoryNames.count
            targetCategory = categoryNames[nextIndex]
            transition = .toNext
        } else {
            let prevIndex = (currentIndex - 1 + categoryNames.count) % categoryNames.count
            targetCategory = categoryNames[prevIndex]
            transition = .toPrevious
        }
        
        categoryTransition = transition
        
        // 第一段：當前頁滑出（同時因為容器會渲染進場頁，所以不會空白）
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            // 進入第二段前：切資料 & 把新頁「瞬移」到另一側邊緣（不帶動畫）
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                selectedCategory = targetCategory
                nextCategory = ""
                previousCategory = ""
                dragOffset = CGSize(width: goingLeft ? width : -width, height: 0)
            }
            
            // 第二段：新頁從邊緣滑到中心
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                // 動畫完成後結束轉場狀態
                categoryTransition = .none
            }
            withAnimation(.easeInOut(duration: duration)) {
                dragOffset = .zero
            }
            CATransaction.commit()
        }
        withAnimation(.easeInOut(duration: duration)) {
            dragOffset = CGSize(width: goingLeft ? -width : width, height: 0)
        }
        CATransaction.commit()
        
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func saveItems() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: savePath)
        }
    }
    
    private func loadItems() {
        if let data = try? Data(contentsOf: savePath),
           let decoded = try? JSONDecoder().decode([Item].self, from: data) {
            items = decoded
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
            let maskCI = CIImage(cvPixelBuffer: maskBuffer)
            let extent = ciImage.extent
            let clearBG = CIImage(color: .clear).cropped(to: extent)
            let cut = CIFilter.blendWithMask()
            cut.inputImage = ciImage
            cut.maskImage = maskCI
            cut.backgroundImage = clearBG
            guard let output = cut.outputImage else { return nil }
            let ctx = CIContext()
            guard let cg = ctx.createCGImage(output, from: output.extent) else { return nil }
            return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
        } catch {
            return nil
        }
    }
}
// 傳送帶容器視圖
struct ConveyorBeltContainer: View {
    let viewMode: ViewMode
    let currentItems: [Item]
    let nextItems: [Item]
    let previousItems: [Item]
    @Binding var selectedItem: Item?
    @Binding var editingItem: Item?
    @Binding var items: [Item]
    let saveItems: () -> Void
    let dragOffset: CGSize
    let categoryTransition: ContentView.CategoryTransition
    let verticalScrollDisabled: Bool
    
    @ViewBuilder
        private func content(for items: [Item]) -> some View {
            if viewMode == .grid {
                ItemsGridView(
                    filteredItems: items,
                    selectedItem: $selectedItem,
                    editingItem: $editingItem,
                    items: $items,
                    saveItems: saveItems,
                    isScrollDisabled: verticalScrollDisabled
                )
            } else {
                ItemsListView(
                    filteredItems: items,
                    selectedItem: $selectedItem,
                    editingItem: $editingItem,
                    items: $items,
                    saveItems: saveItems,
                    isScrollDisabled: verticalScrollDisabled
                )
            }
        }
    
    var body: some View {
            GeometryReader { geometry in
                ZStack {
                    // 當前內容（跟著拖曳位移）
                    content(for: currentItems)
                        .offset(x: dragOffset.width)
                    
                   
                }
            }
        .clipped()
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
    let isScrollDisabled: Bool
    
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
    let isScrollDisabled: Bool
    
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
