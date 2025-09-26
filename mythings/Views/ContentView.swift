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

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
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
    @State private var editingImageForSheet: UIImage? = nil

    // MARK: - 新增：排序狀態
    @State private var sortKey: SortKey = .none
    @State private var sortOrder: SortOrder = .descending

    @State private var pendingPhoto: PendingPhoto?
    @EnvironmentObject private var iCloudSync: iCloudSyncManager

    // 🔑 RevenueCat（用於功能 gating）
    @EnvironmentObject private var pm: PurchasesManager
    @State private var showPaywall = false

    @AppStorage("pref.removeBG") private var prefRemoveBG: Bool = true

    // ✅ 永久化儲存
    @AppStorage("sort.key")   private var storedSortKey: String   = SortKey.none.rawValue
    @AppStorage("sort.order") private var storedSortOrder: String = SortOrder.descending.rawValue

    private var savePath: URL {
        FileManager.documentsDirectory.appendingPathComponent("items.json")
    }
    private let selectionHaptic = UISelectionFeedbackGenerator()

    var categoryNames: [String] {
        var names = ["All"]; names.append(contentsOf: categoryStore.categories.map { $0.name }); return names
    }

    // MARK: - 排序後的顯示清單
    private var displayedItems: [Item] {
        if sortKey == .none {
            return items
        } else {
            return sort(items, by: sortKey, order: sortOrder)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottomTrailing) {
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

                // FloatingAddMenu
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
                case .settings:
                    SettingsView(
                        categoryStore: categoryStore,
                        items: $items,
                        saveItems: saveItems
                    )
                }
            }
        }
        // 初次載入
        .onAppear {
            loadItems()
            if let idx = categoryNames.firstIndex(of: selectedCategory) {
                selectedPage = idx
            }
            sortKey   = SortKey(rawValue: storedSortKey) ?? .none
            sortOrder = SortOrder(rawValue: storedSortOrder) ?? .descending
            HapticsManager.shared.prepare()
            selectionHaptic.prepare()
        }

        // 🔁 寫回排序偏好
        .onChange(of: sortKey) { _, newValue in storedSortKey = newValue.rawValue }
        .onChange(of: sortOrder) { _, newValue in storedSortOrder = newValue.rawValue }

        // ✅ 在開啟相簿/相機前，先檢查是否超過免費上限；不符 → 關閉並彈付費牆
        .onChange(of: showImagePicker) { _, newValue in
            guard newValue == true else { return }
            if !pm.canAddItem(currentCount: items.count) {
                showImagePicker = false
                showPaywall = true
            }
        }
        .onChange(of: showCamera) { _, newValue in
            guard newValue == true else { return }
            if !pm.canAddItem(currentCount: items.count) {
                showCamera = false
                showPaywall = true
            }
        }

        // 各種 Sheet
        .sheet(isPresented: $showManageCategories) {
            ManageCategoriesView(categoryStore: categoryStore)
                .environmentObject(pm) // 若裡面要做分類 gating，可取用 pm
        }

        .sheet(isPresented: $showImagePicker) {
            PhotoPicker(selectedImage: $selectedImage, shouldRemoveBackground: false)
                .onDisappear {
                    guard let img = selectedImage else { return }
                    pendingPhoto = PendingPhoto(image: img)
                    selectedImage = nil
                }
        }

        .sheet(isPresented: $showCamera) {
            CameraPicker(selectedImage: $selectedImage)
                .onDisappear {
                    guard let img = selectedImage else { return }
                    pendingPhoto = PendingPhoto(image: img)
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
                    var new = updated
                    new.updatedAt = Date()   // ⭐ 新增：只要有改就刷新時間
                    items[idx] = new
                    saveItems()
                }
            }
            .presentationDetents(UIDevice.isIPad ? [.large] : [.fraction(0.7)])
            .presentationCornerRadius(UIDevice.isIPad ? 20 : 40)
            .if(UIDevice.isIPad) { view in
                view.presentationBackground(.regularMaterial)
            }
        }


        .sheet(item: $editingItem, onDismiss: { editingImageForSheet = nil }) { editing in
            AddItemView(
                selectedImage: $editingImageForSheet,
                existingItem: editing,
                categoryStore: categoryStore,
                brandStore: brandStore,
                showManageCategories: $showManageCategories
            ) { newItem in
                if let idx = items.firstIndex(where: { $0.id == editing.id }) {
                    var new = newItem
                    new.updatedAt = Date()     // ⭐ 新增：編輯完成刷新時間
                    items[idx] = new
                }
                ImageCacheManager.shared.invalidateCache(for: editing.imageName)
                if editing.imageName != newItem.imageName {
                    ImageCacheManager.shared.invalidateCache(for: newItem.imageName)
                }
                editingItem = nil
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
                // ✅ 第二道防線：新增前再檢查一次
                if pm.canAddItem(currentCount: items.count) {
                    items.insert(newItem, at: 0)
                    selectedImage = nil
                    isAddingNewItem = false
                    saveItems()
                    ImageCacheManager.shared.invalidateCache(for: newItem.imageName)
                } else {
                    // 仍不符合 → 顯示付費牆（不自動關閉 AddItemView，讓使用者決定）
                    showPaywall = true
                }
            }
        }

        .sheet(item: $pendingPhoto) { payload in
            EditPhotoView(
                original: payload.image,
                removeBG: { img in
                    await removeBackground(from: img)
                },
                onDone: { finalImage in
                    // ✅ 第一道防線：完成剪圖時先檢查上限
                    if pm.canAddItem(currentCount: items.count) {
                        selectedImage = finalImage
                        DispatchQueue.main.async { isAddingNewItem = true }
                    } else {
                        showPaywall = true
                    }
                    pendingPhoto = nil
                },
                onCancel: {
                    pendingPhoto = nil
                }
            )
            .presentationDetents([.large])
            .presentationCornerRadius(24)
        }

        // 付費牆
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(pm)
        }

        // 分頁切換
        .onChange(of: selectedPage) { _, newValue in
            if categoryNames.indices.contains(newValue) {
                HapticsManager.shared.pageSnap(strength: lastSwipeStrength)
                let cat = categoryNames[newValue]
                if cat != selectedCategory { selectedCategory = cat }
            }
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
            if iCloudSync.isEnabled {
                iCloudSync.schedule(.itemsChanged)
            }
        } catch {
            print("儲存失敗：\(error)")
        }
    }

    private func loadItems() {
        // 立即離線可用
        loadItemsFromLocal()

        if iCloudSync.isEnabled {
            iCloudSync.schedule(.full)
            // 可選：監聽狀態回到 success 時再 loadItemsFromLocal()
            // .onReceive 或用 .onChange 監控 iCloudSync.syncStatus
        }
    }
    
    private func loadItemsFromLocal() {
        do {
            let data = try Data(contentsOf: savePath)
            var decoded = try JSONDecoder().decode([Item].self, from: data)
            // 規一化價格
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

// MARK: - 排序工具
private func sort(_ items: [Item], by key: SortKey, order: SortOrder) -> [Item] {
    var sorted = items.sorted { a, b in
        switch key {
        case .purchaseDate:
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

/// 將字串價格轉成 Double 用於排序
private func priceValue(_ s: String) -> Double {
    let cleaned = s
        .replacingOccurrences(of: ",", with: "")
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "NT$", with: "")
        .replacingOccurrences(of: "$", with: "")
    return Double(cleaned) ?? 0
}

// MARK: - Thumbnails

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
        VStack {
            Image("emptyState")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)

            Text("It's empty here...").foregroundColor(.gray).font(.subheadline)
        }
        .padding(.top, 180)
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
            .fill(isOn ? Color.black.opacity(0.7) : Color.clear)         // Color only
            .frame(width: 56, height: 56)
            .overlay(
                Image(systemName: isOn ? "cube.fill" : "cube")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isOn ? .white : .primary)
            )
     
            .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 4)
    }

    private func eyes(isOn: Bool) -> some View {
        Circle()
            .fill(isOn ? Color.black.opacity(0.7) : Color.clear)         // Color only
            .frame(width: 56, height: 56)
            .overlay(
                Image(systemName: "eyes")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isOn ? .white : .primary)
            )
            .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 4)
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                 generator.impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    selected = .default
                }
            } label: {
                circle(isOn: selected == .default)
            }
            .accessibilityLabel("Default View")

            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                 generator.impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    selected = .canvas
                }
            } label: {
                eyes(isOn: selected == .canvas)
            }
            .accessibilityLabel("Canvas View")
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.6), Color.white.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .blendMode(.overlay)
        )
        .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 8)
        .shadow(color: .white.opacity(0.06), radius: 1, x: 0, y: 1)
    }
}

#Preview {
    // 預覽時注入必要的 EnvironmentObject，避免崩潰
    let previewSync = iCloudSyncManager()
    return ContentView(categoryStore: CategoryStore())
        .environmentObject(previewSync)
        .environmentObject(PurchasesManager())
}
