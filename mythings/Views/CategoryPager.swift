//
//  CategoryPager.swift
//  mythings
//
//  Created by Designer on 2025/8/15.
//

import SwiftUI

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
