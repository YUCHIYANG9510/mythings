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
        TabView(selection: $selectedPage) {
            ForEach(Array(categoryPages.enumerated()), id: \.offset) { index, page in
                pageView(for: page)
                    .tag(index)
                    .contentShape(Rectangle())
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: selectedPage) { _, newValue in
            if categoryPages.indices.contains(newValue) {
                let page = categoryPages[newValue]
                if page.id != selectedCategoryID { selectedCategoryID = page.id }
            }
        }
        .onChange(of: selectedCategoryID) { _, newValue in
            if let idx = categoryPages.firstIndex(where: { $0.id == newValue }), idx != selectedPage {
                selectedPage = idx
            }
        }
        .background(TabViewScrollConfigurator())
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
                scroll.bounces = true
                scroll.decelerationRate = .fast
                break
            }
            p = cur.superview
        }
    }
}
