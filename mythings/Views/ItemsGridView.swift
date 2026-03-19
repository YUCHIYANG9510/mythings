//
//  ItemsGridView.swift
//  mythings
//

import SwiftUI

struct ItemsGridView: View {
    let filteredItems: [Item]
    let categoryStore: CategoryStore          // ✅ 新增
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
                            categoryStore: categoryStore, // ✅ 往下傳
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
