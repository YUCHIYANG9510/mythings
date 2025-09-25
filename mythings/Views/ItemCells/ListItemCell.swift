//
//  ListItemCell.swift
//  mythings
//
//  Created by Designer on 2025/8/15.
//

import SwiftUI
import UniformTypeIdentifiers

struct ListItemCell: View {
    let item: Item
    @Binding var selectedItem: Item?
    @Binding var editingItem: Item?
    @Binding var items: [Item]
    let saveItems: () -> Void

    // ⭐️ 新增：注入 iCloud 同步管理器，刪除時要排程雲端刪除
    @EnvironmentObject private var iCloudSync: iCloudSyncManager

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // 縮圖：統一用 Images 資料夾 + 記憶體快取
            ListItemImageView(imageName: item.imageName)
                .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(item.brand) · \(item.category)")
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
                // 先移除本機資料並落盤
                items.removeAll { $0.id == item.id }
                saveItems()

                // 清縮圖快取，避免殘影
                if !item.imageName.isEmpty {
                    ImageCacheManager.shared.invalidateCache(for: item.imageName)
                }

                // ⭐️ 關鍵：排程雲端刪除，避免同步時被拉回
                if iCloudSync.isEnabled {
                    iCloudSync.schedule(.deleteItem(item.id))
                    iCloudSync.kickoffIfNeeded()   // ⭐️ 新增這行
                }
            }
        }
        // 拖曳排序
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
