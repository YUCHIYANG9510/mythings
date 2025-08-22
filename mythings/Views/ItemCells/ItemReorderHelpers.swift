//
//  ItemReorderHelpers.swift
//  mythings
//
//  Created by Designer on 2025/8/22.
//

import SwiftUI
import UniformTypeIdentifiers

// 共享：目前正在被拖曳的 item ID
final class ItemDragStore {
    static let shared = ItemDragStore()
    var draggingID: UUID?
}

/// 將 identifiable 陣列中，fromID 的元素移到 toID 的位置
@discardableResult
func moveItem<T: Identifiable>(_ array: inout [T], fromID: T.ID, toID: T.ID) -> Bool where T.ID: Equatable {
    guard fromID != toID,
          let fromIndex = array.firstIndex(where: { $0.id == fromID }),
          let toIndex   = array.firstIndex(where: { $0.id == toID }) else { return false }

    let element = array.remove(at: fromIndex)
    var dest = toIndex
    if fromIndex < toIndex { dest -= 1 } // 移除後索引回縮
    dest = max(0, min(dest, array.count))
    array.insert(element, at: dest)
    return true
}

/// Cell 上使用的 DropDelegate：拖曳經過當前 cell 時即時重排
struct ItemReorderDropDelegate<ItemType: Identifiable>: DropDelegate where ItemType.ID == UUID {
    @Binding var items: [ItemType]
    let currentID: UUID
    let onCommit: () -> Void  // 通常接 saveItems

    func dropEntered(info: DropInfo) {
        guard let dragging = ItemDragStore.shared.draggingID,
              dragging != currentID else { return }
        withAnimation(.snappy) {
            _ = moveItem(&items, fromID: dragging, toID: currentID)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        onCommit()
        ItemDragStore.shared.draggingID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool { true }
}
