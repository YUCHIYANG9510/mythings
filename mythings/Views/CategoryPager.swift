//
//  CategoryPager.swift
//  mythings
//

import SwiftUI

struct CategoryPager: View {
    let categoryPages: [(id: UUID?, name: String)]
    @Binding var selectedPage: Int
    @Binding var selectedCategoryID: UUID?
    let viewMode: ViewMode
    let allItems: [Item]
    let searchText: String

    @Binding var selectedItem: Item?
    @Binding var editingItem: Item?
    @Binding var items: [Item]
    let saveItems: () -> Void
    let categoryStore: CategoryStore

    // 內部狀態：用於 TabView 的實際選中索引（包含循環的虛擬頁面）
    @State private var virtualSelectedPage: Int = 1
    @State private var isAdjusting: Bool = false
    
    // 是否啟用循環滾動（只有 category 數量 > 1 時才啟用）
    private var shouldEnableLooping: Bool {
        categoryPages.count > 1
    }
    
    // 創建虛擬頁面數組：在前後各加一個頁面實現循環
    // 例如：[A, B, C] → [C, A, B, C, A]
    private var virtualPages: [(index: Int, page: (id: UUID?, name: String))] {
        guard shouldEnableLooping && !categoryPages.isEmpty else {
            return categoryPages.enumerated().map { (index: $0, page: $1) }
        }
        
        var result: [(index: Int, page: (id: UUID?, name: String))] = []
        
        // 前綴：最後一個頁面
        result.append((index: categoryPages.count - 1, page: categoryPages[categoryPages.count - 1]))
        
        // 中間：所有原始頁面
        for (index, page) in categoryPages.enumerated() {
            result.append((index: index, page: page))
        }
        
        // 後綴：第一個頁面
        result.append((index: 0, page: categoryPages[0]))
        
        return result
    }
    
    private func itemsFor(categoryID: UUID?) -> [Item] {
        let base: [Item]
        if let id = categoryID {
            base = allItems.filter { $0.categoryID == id }
        } else {
            base = allItems
        }
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.brand.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        TabView(selection: $virtualSelectedPage) {
            ForEach(Array(virtualPages.enumerated()), id: \.offset) { virtualIndex, item in
                pageView(for: item.page)
                    .tag(virtualIndex)
                    .contentShape(Rectangle())
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onAppear {
            // 初始化：真實 index 對應到虛擬 index（需要 +1，因為前綴佔了 index 0）
            if shouldEnableLooping {
                virtualSelectedPage = selectedPage + 1
            } else {
                virtualSelectedPage = selectedPage
            }
        }
        .onChange(of: virtualSelectedPage) { _, newValue in
            guard !isAdjusting, shouldEnableLooping else {
                // 非循環模式：直接同步
                if !shouldEnableLooping {
                    selectedPage = newValue
                    if categoryPages.indices.contains(newValue) {
                        selectedCategoryID = categoryPages[newValue].id
                    }
                }
                return
            }
            
            // 循環邏輯：
            // virtualPages = [C(0), A(1), B(2), C(3), A(4)]
            // 真實頁面數 = 3
            
            if newValue == 0 {
                // 滑到虛擬第一個（實際是最後一個的副本）→ 跳到真實的最後一個
                isAdjusting = true
                let realIndex = categoryPages.count - 1
                selectedPage = realIndex
                selectedCategoryID = categoryPages[realIndex].id
                
                // 無動畫跳轉到對應的真實位置
                withAnimation(.none) {
                    virtualSelectedPage = realIndex + 1
                }
                // 使用 Task 確保在下一個 runloop 重置
                Task { @MainActor in
                    isAdjusting = false
                }
            } else if newValue == virtualPages.count - 1 {
                // 滑到虛擬最後一個（實際是第一個的副本）→ 跳到真實的第一個
                isAdjusting = true
                selectedPage = 0
                selectedCategoryID = categoryPages[0].id
                
                // 無動畫跳轉到對應的真實位置
                withAnimation(.none) {
                    virtualSelectedPage = 1
                }
                // 使用 Task 確保在下一個 runloop 重置
                Task { @MainActor in
                    isAdjusting = false
                }
            } else {
                // 正常範圍內的滑動
                let realIndex = newValue - 1
                if categoryPages.indices.contains(realIndex) {
                    selectedPage = realIndex
                    selectedCategoryID = categoryPages[realIndex].id
                }
            }
        }
        .onChange(of: selectedPage) { _, newValue in
            guard !isAdjusting, shouldEnableLooping else { return }
            let targetVirtual = newValue + 1
            if targetVirtual != virtualSelectedPage {
                virtualSelectedPage = targetVirtual
            }
        }
        .onChange(of: selectedCategoryID) { _, newValue in
            guard !isAdjusting else { return }
            if let idx = categoryPages.firstIndex(where: { $0.id == newValue }), idx != selectedPage {
                selectedPage = idx
                if shouldEnableLooping {
                    virtualSelectedPage = idx + 1
                } else {
                    virtualSelectedPage = idx
                }
            }
        }
        .background(TabViewScrollConfigurator(enableLooping: shouldEnableLooping))
    }

    // ✅ 拆出獨立 @ViewBuilder 讓編譯器能快速推斷型別
    @ViewBuilder
    private func pageView(for page: (id: UUID?, name: String)) -> some View {
        if viewMode == .grid {
            ItemsGridView(
                filteredItems: itemsFor(categoryID: page.id),
                categoryStore: categoryStore,   // ✅ 補上
                selectedItem: $selectedItem,
                editingItem: $editingItem,
                items: $items,
                saveItems: saveItems,
                isScrollDisabled: false
            )
        } else {
            ItemsListView(
                filteredItems: itemsFor(categoryID: page.id),
                categoryStore: categoryStore,   // ✅ 補上
                selectedItem: $selectedItem,
                editingItem: $editingItem,
                items: $items,
                saveItems: saveItems,
                isScrollDisabled: false
            )
        }
    }
}

private struct TabViewScrollConfigurator: UIViewRepresentable {
    let enableLooping: Bool
    
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
                // 循環模式下允許 bounce，讓用戶能夠"超滾"觸發循環
                scroll.bounces = enableLooping
                scroll.decelerationRate = .fast
                break
            }
            p = cur.superview
        }
    }
}
