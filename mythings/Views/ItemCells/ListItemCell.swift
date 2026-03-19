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
            Button("Edit") { editingItem = item }
            Button("Delete", role: .destructive) {
                items.removeAll { $0.id == item.id }
                saveItems()

                if !item.imageName.isEmpty {
                    ImageCacheManager.shared.invalidateCache(for: item.imageName)
                }

                if iCloudSync.isEnabled {
                    iCloudSync.schedule(.deleteItem(item.id))
                    iCloudSync.kickoffIfNeeded()
                }
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
