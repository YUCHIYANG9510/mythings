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

enum PageMode {
    case `default`
    case canvas
}


extension View {
    /// iOS 17 之後的 onChange 使用 0 或 2 參數；iOS 16 仍是舊版 1 參數。
    @ViewBuilder
    func onChangeCompat<V: Equatable>(of value: V, perform action: @escaping () -> Void) -> some View {
        if #available(iOS 17, *) {
            self.onChange(of: value) {
                action()       // 新：零參數 closure 版本
            }
        } else {
            self.onChange(of: value, perform: { _ in
                action()       // 舊：一參數（newValue）版本
            })
        }
    }
}



struct PendingPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
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
    @State private var didPrepareHaptic = false
    @State private var lastSwipeStrength: Double = 0.75

    @State private var selectedPage: Int = 0
    @State private var pageMode: PageMode = .default

    // MARK: - 新增：排序狀態
    @State private var sortKey: SortKey = .none
    @State private var sortOrder: SortOrder = .descending
    // 預設顯示「最新在前」
    

    /*  @State private var pendingOriginal: UIImage?
    // 拍攝/選取的原始圖，準備進入 Edit Photo
    @State private var showEditPhoto = false
    // 是否顯示 Edit Photo 頁 */
    @State private var pendingPhoto: PendingPhoto?
    // 用來驅動 sheet(item:)
    
    @StateObject private var iCloudSync = iCloudSyncManager()
    
    @AppStorage("pref.removeBG") private var prefRemoveBG: Bool = true

    
    // ✅ 永久化儲存
    @AppStorage(
        "sort.key"
    )   private var storedSortKey: String   = SortKey.none.rawValue
    @AppStorage(
        "sort.order"
    ) private var storedSortOrder: String = SortOrder.descending.rawValue
    
    private var savePath: URL {
        FileManager.documentsDirectory.appendingPathComponent("items.json")
    }
    private let selectionHaptic = UISelectionFeedbackGenerator()

    var categoryNames: [String] {
        var names = ["All"]; names.append(contentsOf: categoryStore.categories.map { $0.name }); return names
    }
    // MARK: - 分類篩選後的顯示清單
    /*private func itemsFor(category: String) -> [Item] {
        let categoryFiltered = (category == "All") ? displayedItems : displayedItems.filter { $0.category == category }
        guard !searchText.isEmpty else { return categoryFiltered }
        return categoryFiltered.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.brand.localizedCaseInsensitiveContains(searchText)
        }
    } */

    // MARK: - 修正：排序後的顯示清單，sortKey == .none 時保持原始順序（最新在前）
    private var displayedItems: [Item] {
        if sortKey == .none {
            return items  // 保持原始順序（新增時用 insert(at: 0)）
        } else {
            return sort(items, by: sortKey, order: sortOrder)
        }
    }
    
    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottomTrailing) {
                // 這裡放你的主要內容（HeaderView / CategoryPager / CanvasBoardView 等）
                VStack {
                    if pageMode == .default {
                        HeaderView(
                            isSearching: $isSearching,
                            text: $searchText,
                            viewMode: $viewMode,
                            sortKey: $sortKey,
                            sortOrder: $sortOrder,
                            navigateToSettings: { path.append(.settings) }
                        )
                        CategoryScrollView(
                            categoryNames: categoryNames,
                            selectedCategory: $selectedCategory
                        )
                        CategoryPager(
                            categoryNames: categoryNames,
                            selectedPage: $selectedPage,
                            selectedCategory: $selectedCategory,
                            viewMode: viewMode,
                            allItems: displayedItems,
                            searchText: searchText,
                            selectedItem: $selectedItem,
                            editingItem: $editingItem,
                            items: $items,
                            saveItems: saveItems
                        )
                    } else {
                        CanvasBoardView(items: displayedItems,
                                        imageLoader: ImageMemoryCache.shared)
                    }
                }
                
                // FloatingAddMenu 獨立佈局
                FloatingAddMenu(
                    isOpen: $showActionSheet,
                    showCamera: $showCamera,
                    showImagePicker: $showImagePicker
                )

                VStack {
                       Spacer()
                       HStack {
                           Spacer()
                           CanvasTabToggle(selected: $pageMode)
                               .padding(.trailing, 20)
                               .padding(.bottom, 28)
                       }
                   }
            }
            .navigationDestination(for: NavigationTarget.self) { target in
                switch target {
                case .settings: SettingsView(
                    categoryStore: categoryStore,
                    items: $items,
                    saveItems: saveItems
                )

                }
            }
        }
        // 讀取現有資料（包含 items）後，同步還原排序設定
        .onAppear {
            loadItems()
            if let idx = categoryNames.firstIndex(of: selectedCategory) {
                selectedPage = idx
            }
            
            // 還原排序設定
            sortKey   = SortKey(rawValue: storedSortKey) ?? .none
            sortOrder = SortOrder(rawValue: storedSortOrder) ?? .descending

            HapticsManager.shared.prepare()
            selectionHaptic.prepare()
        }

        // 🔁 每次變更就寫回 UserDefaults
        .onChange(of: sortKey) { _, newValue in
            storedSortKey = newValue.rawValue
        }
        .onChange(of: sortOrder) { _, newValue in
            storedSortOrder = newValue.rawValue
        }
        
        .sheet(isPresented: $showManageCategories) { ManageCategoriesView(categoryStore: categoryStore) }
        .sheet(isPresented: $showImagePicker) {
            PhotoPicker(selectedImage: $selectedImage, shouldRemoveBackground: false)
                .onDisappear {
                    guard let img = selectedImage else { return }
                    pendingPhoto = PendingPhoto(image: img)   // 直接進 pendingPhoto
                    selectedImage = nil
                }
        }

        .sheet(isPresented: $showCamera) {
            CameraPicker(selectedImage: $selectedImage)
                .onDisappear {
                    guard let img = selectedImage else { return }
                    pendingPhoto = PendingPhoto(image: img)   // 直接進 pendingPhoto
                    selectedImage = nil
                }
        }

        .sheet(item: $selectedItem) { item in
            ItemDetailView(
                item: item,
                categoryStore: categoryStore,
                brandStore: brandStore
            ) { updated in
                if let idx = items.firstIndex(where: { $0.id == updated.id }) {
                    items[idx] = updated
                    saveItems()
                }
            }
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
                if let idx = items.firstIndex(where: { $0.id == editing.id }) {
                    items[idx] = newItem
                }
                // ✅ 重要：把舊的 / 新的 imageName 從快取移除
                ImageCacheManager.shared.invalidateCache(for: editing.imageName)
                if editing.imageName != newItem.imageName {
                    ImageCacheManager.shared.invalidateCache(for: newItem.imageName)
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
                items.insert(newItem, at: 0)
                selectedImage = nil
                isAddingNewItem = false
                saveItems()

                // ✅ 新增完也把該圖清掉（避免同名覆蓋的情況）
                ImageCacheManager.shared.invalidateCache(for: newItem.imageName)
            }
        }

        
        .sheet(item: $pendingPhoto) { payload in
            EditPhotoView(
                original: payload.image,
                removeBG: { img in
                    await removeBackground(from: img)
                },
                onDone: { finalImage in
                    selectedImage = finalImage
                    DispatchQueue.main.async { isAddingNewItem = true }
                    pendingPhoto = nil
                },
                onCancel: {
                    pendingPhoto = nil
                }
            )
            .presentationDetents([.large])
            .presentationCornerRadius(24)
        }


       
        .onChange(of: selectedPage) { _, newValue in
            if categoryNames.indices.contains(newValue) {
                HapticsManager.shared.pageSnap(strength: lastSwipeStrength)
                let cat = categoryNames[newValue]
                if cat != selectedCategory { selectedCategory = cat }
            }
            // 預熱下次觸覺回饋
            HapticsManager.shared.prepare()
            selectionHaptic.prepare()
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
                
                // 如果啟用了 iCloud 同步，觸發同步
                if iCloudSync.isEnabled {
                    iCloudSync.manualSync()
                }
            } catch {
                print("儲存失敗：\(error)")
            }
        }
    
    private func loadItems() {
            // 如果啟用了 iCloud 同步，先嘗試同步
            if iCloudSync.isEnabled {
                iCloudSync.manualSync()
                // 稍等同步完成後再載入
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    loadItemsFromLocal()
                }
            } else {
                loadItemsFromLocal()
            }
        }
    
    private func loadItemsFromLocal() {
            do {
                let data = try Data(contentsOf: savePath)
                var decoded = try JSONDecoder().decode([Item].self, from: data)
                // ✅ 讀取舊資料後，規一化價錢，避免舊資料有 "$$"
                decoded = decoded.map { item in
                    Item(
                        id: item.id,
                        imageName: item.imageName,
                        brand: item.brand,
                        category: item.category,
                        name: item.name,
                        price: normalizedPriceString(item.price),
                        date: item.date
                    )
                }

                items = decoded
            } catch {
                print("讀取失敗或尚無資料：\(error)")
            }
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
    
    // MARK: - 新增：排序工具
       private func sort(_ items: [Item], by key: SortKey, order: SortOrder) -> [Item] {
           var sorted = items.sorted { a, b in
               switch key {
               case .purchaseDate:
                   // 假設 Item.date 是 Date?；若是 String 請告訴我格式再幫你轉
                   let da = a.date ?? .distantPast
                   let db = b.date ?? .distantPast
                   return da < db

               case .price:
                   let pa = priceValue(a.price)
                   let pb = priceValue(b.price)
                   return pa < pb

               case .name:
                   return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                   
               case .none:
                   return false
               }
           }
           if order == .descending { sorted.reverse() }
           return sorted
       }
    
    /// 將字串價格（例如 "$1,299.50" 或 "1299"）轉成 Double 用於排序
        private func priceValue(_ s: String) -> Double {
            // 去除貨幣符號與空白，保留數字與小數點
            let cleaned = s
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "NT$", with: "")
                .replacingOccurrences(of: "$", with: "")
            return Double(cleaned) ?? 0
        }
    





struct ListItemImageView: View {
    let imageName: String
    @StateObject private var cacheManager = ImageCacheManager.shared
    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            Color(.systemGray6)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if isLoading {
                ProgressView()
            } else {
                // 空檔名或載入失敗時的佔位
                Image(systemName: "photo")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear(perform: loadImage)
        .onChangeCompat(of: cacheManager.cacheInvalidationTrigger) { loadImage() }
        .onChangeCompat(of: imageName) { loadImage() }
    }

    private func loadImage() {
        // 防呆：只取檔名，避免整條路徑；空字串就顯示佔位不轉圈
        let fileName = (imageName as NSString).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fileName.isEmpty else {
            self.image = nil
            self.isLoading = false
            return
        }

        isLoading = true
        ImageMemoryCache.shared.loadImage(named: fileName) { img in
            self.image = img
            self.isLoading = false
        }
    }
}


struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "tray").resizable().frame(width: 40, height: 30).foregroundColor(.gray)
            Text("It's empty here...").foregroundColor(.gray).font(.subheadline)
        }
        .padding(.top, 250)
    }
}



struct ItemImageView: View {
    let imageName: String
    @StateObject private var cacheManager = ImageCacheManager.shared
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
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
                    ProgressView()
                }
                .frame(height: 150)
                .cornerRadius(8)
            }
        }
        .onAppear(perform: loadImage)
        .onChangeCompat(of: cacheManager.cacheInvalidationTrigger) { loadImage() }
        .onChangeCompat(of: imageName) { loadImage() }
    }

    private func loadImage() {
        ImageMemoryCache.shared.loadImage(named: imageName) { img in
            self.image = img
        }
    }
}


struct CanvasTabToggle: View {
    @Binding var selected: PageMode

    private func circle(isOn: Bool) -> some View {
        Circle()
            .fill(isOn ? Color.black : Color.clear)
            .frame(width: 56, height: 56)
            .overlay(
                Image(systemName: isOn ? "cube.fill" : "cube")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isOn ? .white : .black)
            )
    }

    private func eyes(isOn: Bool) -> some View {
        Circle()
            .fill(isOn ? Color.black : Color.clear)
            .frame(width: 56, height: 56)
            .overlay(
                Image(systemName: "eyes")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isOn ? .white : .black)
            )
    }

    var body: some View {
        HStack(spacing: 2) {
            // 左：Default
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    selected = .default
                }
            } label: {
                circle(isOn: selected == .default)
            }
            .accessibilityLabel("Default View")

            // 右：Canvas
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    selected = .canvas
                }
            } label: {
                eyes(isOn: selected == .canvas)
            }
            .accessibilityLabel("Canvas View")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(.white)
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
        )
    }
}



#Preview {
    ContentView(categoryStore: CategoryStore())
}
