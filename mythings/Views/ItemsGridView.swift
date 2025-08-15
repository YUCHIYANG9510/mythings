//
//  ItemsGridView.swift
//  mythings
//
//  Created by Designer on 2025/8/15.
//

import SwiftUI

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
