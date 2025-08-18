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

class ImageCacheManager: ObservableObject {
    static let shared = ImageCacheManager()
    @Published var cacheInvalidationTrigger = UUID()
    func invalidateCache() { cacheInvalidationTrigger = UUID() }
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
    
    private var savePath: URL {
        FileManager.documentsDirectory.appendingPathComponent("items.json")
    }
    private let selectionHaptic = UISelectionFeedbackGenerator()

    var categoryNames: [String] {
        var names = ["All"]; names.append(contentsOf: categoryStore.categories.map { $0.name }); return names
    }
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
                                if !didPrepareHaptic,
                                   abs(value.translation.width) > abs(value.translation.height),
                                   abs(value.translation.width) > 8 {
                                    HapticsManager.shared.prepare()
                                    didPrepareHaptic = true
                                }
                            }
                            .onEnded { value in
                                let dx = value.predictedEndTranslation.width - value.translation.width
                                let approxSpeed = min(1.0, max(0.0, Double(abs(dx) / 140.0)))
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
                case .settings: SettingsView(categoryStore: categoryStore)
                }
            }
        }
        .sheet(isPresented: $showManageCategories) { ManageCategoriesView(categoryStore: categoryStore) }
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
                if let idx = items.firstIndex(where: { $0.id == editing.id }) { items[idx] = newItem }
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
            if let idx = categoryNames.firstIndex(of: selectedCategory) { selectedPage = idx }
        }
        .onChange(of: selectedPage) { _, newValue in
            if categoryNames.indices.contains(newValue) {
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




struct ListItemImageView: View {
    let imageName: String
    @StateObject private var cacheManager = ImageCacheManager.shared
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image = image {
                ZStack {
                    Color(.systemGray6)
                    Image(uiImage: image).resizable().scaledToFit()
                }
                .frame(width: 80, height: 80)
            } else {
                ZStack {
                    Color(.systemGray6)
                    Image(systemName: "photo")
                        .resizable().scaledToFit()
                        .frame(width: 30).foregroundColor(.gray)
                }
                .frame(width: 80, height: 80)
            }
        }
        .onAppear(perform: loadImage)
        .onChangeCompat(of: cacheManager.cacheInvalidationTrigger) { loadImage() }
        .onChangeCompat(of: imageName) { loadImage() }
    }
    private func loadImage() {
        let imagePath = FileManager.documentsDirectory.appendingPathComponent(imageName).path
        image = UIImage(contentsOfFile: imagePath)
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
            if let image = image {
                ZStack {
                    Color(.systemGray6)
                    Image(uiImage: image).resizable().scaledToFit().frame(height: 120)
                }
                .frame(height: 150).cornerRadius(8)
            } else {
                ZStack {
                    Color(.systemGray6)
                    Image(systemName: "photo").resizable().scaledToFit().frame(height: 60).foregroundColor(.gray)
                }
                .frame(height: 150).cornerRadius(8)
            }
        }
        .onAppear(perform: loadImage)
        .onChangeCompat(of: cacheManager.cacheInvalidationTrigger) { loadImage() }
        .onChangeCompat(of: imageName) { loadImage() }
    }
    private func loadImage() {
        let imagePath = FileManager.documentsDirectory.appendingPathComponent(imageName).path
        image = UIImage(contentsOfFile: imagePath)
    }
}



#Preview {
    ContentView(categoryStore: CategoryStore())
}
