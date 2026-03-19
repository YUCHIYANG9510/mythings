//
//  ItemCell.swift
//  mythings
//

import SwiftUI
import UniformTypeIdentifiers

struct ItemCell: View {
    let item: Item
    let categoryStore: CategoryStore          // ✅ 新增：用來查 category 名稱
    @Binding var selectedItem: Item?
    @Binding var editingItem: Item?
    @Binding var items: [Item]
    let saveItems: () -> Void

    @EnvironmentObject private var iCloudSync: iCloudSyncManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ItemImageView(imageName: item.imageName)
            // ✅ 改用 categoryStore.name(for:) 取得分類名稱
            Text("\(item.brand) · \(categoryStore.name(for: item.categoryID))")
                .font(.caption).foregroundColor(.gray)
            HStack {
                Text(item.name).font(.subheadline).lineLimit(1)
                Spacer()
                Text(item.displayPrice)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onDrop(of: [.text],
                delegate: ItemReorderDropDelegate(items: $items,
                                                  currentID: item.id,
                                                  onCommit: saveItems))
    }
}
