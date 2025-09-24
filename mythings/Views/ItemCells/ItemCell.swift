//
//  ItemCell.swift
//  mythings
//
//  Created by Designer on 2025/8/15.
//

import SwiftUI
import UniformTypeIdentifiers

struct ItemCell: View {
    let item: Item
    @Binding var selectedItem: Item?
    @Binding var editingItem: Item?
    @Binding var items: [Item]
    let saveItems: () -> Void
    
    @EnvironmentObject private var iCloudSync: iCloudSyncManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ItemImageView(imageName: item.imageName)
            Text("\(item.brand) · \(item.category)")
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
                // 先本地刪除 + 落盤（不會直接觸發同步，僅送出 itemsChanged 事件）
                items.removeAll { $0.id == item.id }
                saveItems()

                // 再交給協調器安排雲端刪除；與 itemsChanged 會被合併處理，避免併發
                if iCloudSync.isEnabled {
                    iCloudSync.schedule(.deleteItem(item.id))
                }
            }
        }
        // ✅ 加上拖曳&放置
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


