//
//  ContentView.swift
//  mythings
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
    @ViewBuilder
    func onChangeCompat<V: Equatable>(of value: V, perform action: @escaping () -> Void) -> some View {
        if #available(iOS 17, *) {
            self.onChange(of: value) { action() }
        } else {
            self.onChange(of: value, perform: { _ in action() })
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
    // ✅ selectedCategory 改為存 UUID?（nil = "All"）
    @State private var selectedCategoryID: UUID? = nil
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

    @State private var sortKey: SortKey = .none
    @State private var sortOrder: SortOrder = .descending

    @State private var pendingPhoto: PendingPhoto?
    @EnvironmentObject private var iCloudSync: iCloudSyncManager

    @EnvironmentObject private var pm: PurchasesManager
    @State private var showPaywall = false

    @AppStorage("pref.removeBG") private var prefRemoveBG: Bool = true
    @AppStorage("sort.key")   private var storedSortKey: String   = SortKey.none.rawValue
    @AppStorage("sort.order") private var storedSortOrder: String = SortOrder.descending.rawValue

    private var savePath: URL {
        FileManager.documentsDirectory.appendingPathComponent("items.json")
    }
    private let selectionHaptic = UISelectionFeedbackGenerator()

    // ✅ category 頁面清單：用 (id: UUID?, name: String) tuple
    // id == nil 代表 "All"
    private var categoryPages: [(id: UUID?, name: String)] {
        var pages: [(id: UUID?, name: String)] = [(nil, "All")]
        pages += categoryStore.categories.map { (Optional($0.id), $0.name) }
        return pages
    }

    // 向下相容：給 CategoryScrollView / CategoryPager 用的純字串陣列
    var categoryNames: [String] {
        categoryPages.map { $0.name }
    }

    // 目前選中分類的顯示名稱（給 CategoryScrollView binding 用）
    private var selectedCategoryName: String {
        guard let id = selectedCategoryID else { return "All" }
        return categoryStore.name(for: id)
    }

    // MARK: - 排序後的顯示清單
    private var displayedItems: [Item] {
        if sortKey == .none {
            return items.sorted { $0.createdAt > $1.createdAt }
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

                        // ✅ CategoryScrollView 仍接受字串，binding 橋接
                        CategoryScrollView(
                            categoryNames: categoryNames,
                            selectedCategory: Binding(
                                get: { selectedCategoryName },
                                set: { name in
                                    selectedCategoryID = categoryPages.first(where: { $0.name == name })?.id ?? nil
                                }
                            )
                        )

                        // ✅ CategoryPager 用 UUID? 做 filter
                        CategoryPager(
                            categoryPages: categoryPages,
                            selectedPage: $selectedPage,
                            selectedCategoryID: $selectedCategoryID,
                            viewMode: viewMode,
                            allItems: displayedItems,
                            searchText: searchText,
                            selectedItem: $selectedItem,
                            editingItem: $editingItem,
                            items: $items,
                            saveItems: saveItems,
                            categoryStore: categoryStore
                        )
                    } else {
                        CanvasBoardView(items: displayedItems,
                                        imageLoader: ImageMemoryCache.shared)
                    }
                }

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

        .onReceive(iCloudSync.$syncStatus) { status in
            if case .success = status {
                // ✅ Fix: Preserve recently updated items to prevent iCloud from overwriting local edits
                // Store items that were updated in the last 10 seconds (likely from user edits)
                let recentThreshold = Date().addingTimeInterval(-10)
                let recentlyUpdated = items.filter { $0.updatedAt > recentThreshold }
                
                loadItemsFromLocal()
                
                // ✅ Restore recently updated items that might have been overwritten
                // This prevents the race condition where iCloud sync overwrites local edits
                for recentItem in recentlyUpdated {
                    if let index = items.firstIndex(where: { $0.id == recentItem.id }) {
                        // Only restore if the recent item is actually newer
                        if recentItem.updatedAt > items[index].updatedAt {
                            items[index] = recentItem
                            print("✅ Preserved recent edit for item: \(recentItem.name)")
                        }
                    }
                }
                
                // Save the preserved changes back to disk
                if !recentlyUpdated.isEmpty {
                    saveItems()
                }
                
                // ✅ Bug 2 fix：iCloud sync 成功後也需要跑 migration
                // 否則從其他裝置 pull 回來的舊格式 item 會顯示 "Unknown" category
                let snapshot = categoryStore.categories
                migrateItemsIfNeeded(using: snapshot)
            }
        }

        .onReceive(NotificationCenter.default.publisher(for: .iCloudLocalStoreWiped)) { _ in
            items = []
        }

        .onAppear {
            loadItems()
            // 恢復 selectedPage
            if let idx = categoryPages.firstIndex(where: { $0.id == selectedCategoryID }) {
                selectedPage = idx
            }
            sortKey   = SortKey(rawValue: storedSortKey) ?? .none
            sortOrder = SortOrder(rawValue: storedSortOrder) ?? .descending
            HapticsManager.shared.prepare()
            selectionHaptic.prepare()
        }

        .onChange(of: sortKey)   { _, v in storedSortKey = v.rawValue }
        .onChange(of: sortOrder) { _, v in storedSortOrder = v.rawValue }

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

        // Manage Categories sheet（從 ContentView 層觸發的）
        .sheet(isPresented: $showManageCategories) {
            ManageCategoriesView(categoryStore: categoryStore)
                .environmentObject(pm)
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
                    new.updatedAt = Date()
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
                    new.updatedAt = Date()
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
                if pm.canAddItem(currentCount: items.count) {
                    var stamped = newItem
                    stamped.updatedAt = Date()
                    items.insert(stamped, at: 0)
                    selectedImage = nil
                    isAddingNewItem = false
                    saveItems()
                    ImageCacheManager.shared.invalidateCache(for: stamped.imageName)
                } else {
                    showPaywall = true
                }
            }
        }

        .sheet(item: $pendingPhoto) { payload in
            EditPhotoView(
                original: payload.image,
                removeBG: { img in await removeBackground(from: img) },
                onDone: { finalImage in
                    if pm.canAddItem(currentCount: items.count) {
                        selectedImage = finalImage
                        DispatchQueue.main.async { isAddingNewItem = true }
                    } else {
                        showPaywall = true
                    }
                    pendingPhoto = nil
                },
                onCancel: { pendingPhoto = nil }
            )
            .presentationDetents([.large])
            .presentationCornerRadius(24)
        }

        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(pm)
        }

        // ✅ 頁面切換：用 categoryPages index
        .onChange(of: selectedPage) { _, newValue in
            if categoryPages.indices.contains(newValue) {
                HapticsManager.shared.pageSnap(strength: lastSwipeStrength)
                let page = categoryPages[newValue]
                if page.id != selectedCategoryID { selectedCategoryID = page.id }
            }
            HapticsManager.shared.prepare()
            selectionHaptic.prepare()
        }
        .onChange(of: selectedCategoryID) { _, newValue in
            if let idx = categoryPages.firstIndex(where: { $0.id == newValue }), idx != selectedPage {
                selectedPage = idx
            }
        }
        // ✅ Bug 3 fix：監聽 categories 變化，若目前選中的 category 被刪除，重置回 All
        // 避免 selectedCategoryID 成為 dangling reference，造成 TabView 顯示空白或錯頁
        .onChange(of: categoryStore.categories) { _, newCategories in
            if let id = selectedCategoryID {
                let stillExists = newCategories.contains(where: { $0.id == id })
                if !stillExists {
                    selectedCategoryID = nil  // 回到 All
                    selectedPage = 0
                }
            }
        }
    }

    // MARK: - Persistence

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
        loadItemsFromLocal()
        // ✅ 舊資料遷移：在 MainActor 上取得 categories 快照後執行
        let categoriesSnapshot = categoryStore.categories
        migrateItemsIfNeeded(using: categoriesSnapshot)
        if iCloudSync.isEnabled {
            iCloudSync.schedule(.full)
        }
    }

    private func loadItemsFromLocal() {
        do {
            let data = try Data(contentsOf: savePath)
            var decoded = try JSONDecoder().decode([Item].self, from: data)
            decoded = decoded.map { item in
                Item(
                    id: item.id,
                    imageName: item.imageName,
                    brand: item.brand,
                    categoryID: item.categoryID,
                    name: item.name,
                    price: normalizedPriceString(item.price),
                    date: item.date,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt
                )
            }
            items = decoded
        } catch {
            print("讀取失敗或尚無資料：\(error)")
        }
    }

    /// 舊格式遷移：若 item 的 categoryID 為 nilUUID，用 category 名稱對照傳入的 categories 快照取回 UUID
    /// categories 快照在呼叫前於 MainActor context 取得，避免 actor isolation 錯誤
    private func migrateItemsIfNeeded(using categories: [Category]) {
        let nilUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        guard items.contains(where: { $0.categoryID == nilUUID }) else { return }

        guard let data = try? Data(contentsOf: savePath) else { return }

        // ✅ NameMapRef（純 Swift class）取代 NSMutableDictionary，避免 Sendable 警告
        let nameMapRef = NameMapRef()
        let decoder = JSONDecoder()
        decoder.userInfo[ItemMigrationKey.categoryNameKey] = nameMapRef

        guard var rawItems = try? decoder.decode([Item].self, from: data) else { return }

        var nameToID: [String: UUID] = [:]
        for cat in categories {
            nameToID[cat.name] = cat.id
        }

        for i in rawItems.indices {
            if rawItems[i].categoryID == nilUUID {
                let oldName = nameMapRef.storage[rawItems[i].id.uuidString] ?? ""
                rawItems[i].categoryID = nameToID[oldName] ?? nilUUID
            }
        }

        items = rawItems
        saveItems()
        print("✅ Migration complete: \(rawItems.count) items migrated")
    }
}

// MARK: - Background Removal

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

// MARK: - Sort

private func sort(_ items: [Item], by key: SortKey, order: SortOrder) -> [Item] {
    var sorted = items.sorted { a, b in
        switch key {
        case .purchaseDate:
            let da = a.date ?? .distantPast
            let db = b.date ?? .distantPast
            return da < db
        case .price:
            return priceValue(a.price) < priceValue(b.price)
        case .name:
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        case .none:
            return false
        }
    }
    if order == .descending { sorted.reverse() }
    return sorted
}

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
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)

    init(selected: Binding<PageMode>) {
        self._selected = selected
        feedbackGenerator.prepare()
    }

    private func circle(isOn: Bool) -> some View {
        Circle()
            .fill(isOn ? Color.black.opacity(0.7) : Color.clear)
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
            .fill(isOn ? Color.black.opacity(0.7) : Color.clear)
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
                feedbackGenerator.impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { selected = .default }
            } label: { circle(isOn: selected == .default) }
            .accessibilityLabel("Default View")

            Button {
                feedbackGenerator.impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { selected = .canvas }
            } label: { eyes(isOn: selected == .canvas) }
            .accessibilityLabel("Canvas View")
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 8)
    }
}

#Preview {
    let previewSync = iCloudSyncManager()
    return ContentView(categoryStore: CategoryStore())
        .environmentObject(previewSync)
        .environmentObject(PurchasesManager())
}
