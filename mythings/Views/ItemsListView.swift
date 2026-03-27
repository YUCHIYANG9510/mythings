//
//  ItemsListView.swift
//  mythings
//

import SwiftUI

struct ItemsListView: View {
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
                LazyVStack(spacing: 8) {
                    ForEach(filteredItems) { item in
                        ListItemCell(
                            item: item,
                            categoryStore: categoryStore, // ✅ 往下傳
                            selectedItem: $selectedItem,
                            editingItem: $editingItem,
                            items: $items,
                            saveItems: saveItems
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteItem(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .scrollDisabled(isScrollDisabled)
        .padding(.top, 16)
    }
    
    // MARK: - Delete Item
    
    @EnvironmentObject private var iCloudSync: iCloudSyncManager
    
    private func deleteItem(_ item: Item) {
        // 1. Delete physical image file from disk
        if !item.imageName.isEmpty {
            let imageURL = FileManager.imagesDirectory
                .appendingPathComponent((item.imageName as NSString).lastPathComponent)
            try? FileManager.default.removeItem(at: imageURL)
            
            // 2. Invalidate memory cache
            ImageCacheManager.shared.invalidateCache(for: item.imageName)
        }
        
        // 3. Remove from items array
        items.removeAll { $0.id == item.id }
        
        // 4. Save to local storage
        saveItems()
        
        // 5. Sync deletion to iCloud
        if iCloudSync.isEnabled {
            iCloudSync.schedule(.deleteItem(item.id))
        }
    }
}
