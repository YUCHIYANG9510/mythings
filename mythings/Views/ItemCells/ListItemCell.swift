//
//  ListItemCell.swift
//  mythings
//

import SwiftUI
import UniformTypeIdentifiers

struct ListItemCell: View {
    let item: Item
    let categoryStore: CategoryStore          // ✅ 新增：用來查 category 名稱
    @Binding var selectedItem: Item?
    @Binding var editingItem: Item?
    @Binding var items: [Item]
    let saveItems: () -> Void

    @EnvironmentObject private var iCloudSync: iCloudSyncManager

    // MARK: - Delete Item
    
    private func deleteItem() {
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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ListItemImageView(imageName: item.imageName)
                .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 4) {
                // ✅ 改用 categoryStore.name(for:) 取得分類名稱
                Text("\(item.brand) · \(categoryStore.name(for: item.categoryID))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }

            Spacer()

            Text(item.displayPrice)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { selectedItem = item }
        .contextMenu {
            Button(L("edit")) { editingItem = item }
            Button(L("delete"), role: .destructive) {
                deleteItem()
            }
        }
        .onDrag {
            ItemDragStore.shared.draggingID = item.id
            return NSItemProvider(object: item.id.uuidString as NSString)
        }
        .onDrop(of: [.text],
                delegate: ItemReorderDropDelegate(items: $items,
                                                  currentID: item.id,
                                                  onCommit: saveItems))
    }
}
