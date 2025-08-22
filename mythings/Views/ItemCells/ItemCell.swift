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
                items.removeAll { $0.id == item.id }
                saveItems()
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


