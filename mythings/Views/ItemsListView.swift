//
//  ItemsListView.swift
//  mythings
//
//  Created by Designer on 2025/8/15.
//

import SwiftUI

struct ItemsListView: View {
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
