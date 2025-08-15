//
//  ItemCell.swift
//  mythings
//
//  Created by Designer on 2025/8/15.
//

import SwiftUI

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
                // ✅ 統一顯示價錢
                Text(item.displayPrice)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .onTapGesture { selectedItem = item }
        .contextMenu {
            Button("編輯") { editingItem = item }
            Button("刪除", role: .destructive) {
                items.removeAll { $0.id == item.id }
                saveItems()
            }
        }
    }
}
