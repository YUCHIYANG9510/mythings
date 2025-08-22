//
//  ListItemCell.swift
//  mythings
//
//  Created by Designer on 2025/8/15.
//

// ListItemCell.swift
import SwiftUI
import UniformTypeIdentifiers

struct ListItemCell: View {
    let item: Item
    @Binding var selectedItem: Item?
    @Binding var editingItem: Item?
    @Binding var items: [Item]
    let saveItems: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ListItemImageView(imageName: item.imageName)
                .frame(width: 80, height: 80)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(item.brand) · \(item.category)")
                    .font(.caption).foregroundColor(.gray)
                Text(item.name)
                    .font(.subheadline).fontWeight(.medium)
                    .lineLimit(1)
            }
            Spacer()
            Text(item.displayPrice)
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .onTapGesture { selectedItem = item }
        .contextMenu {
            Button("編輯") { editingItem = item }
            Button("刪除", role: .destructive) {
                items.removeAll { $0.id == item.id }
                saveItems()
            }
        }
        // ✅ 加上拖曳&放置
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
