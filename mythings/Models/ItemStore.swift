//
//  ItemStore.swift
//  mythings
//

import Foundation
import SwiftUI

// ✅ 取代 NSMutableDictionary，避免 Sendable 問題
// decode 時用來收集 itemID → oldCategoryName 的對照
final class NameMapRef: @unchecked Sendable {
    var storage: [String: String] = [:]
}

class ItemStore: ObservableObject {
    @Published var items: [Item] = []

    private var savePath: URL {
        FileManager.documentsDirectory.appendingPathComponent("items.json")
    }

    init() {
        loadItems()
    }

    // MARK: - CRUD

    func addItem(item: Item) {
        var newItem = item
        newItem.updatedAt = Date()
        items.insert(newItem, at: 0)
        saveItems()
    }

    func addItems(_ newItems: [Item]) {
        for item in newItems.reversed() {
            var newItem = item
            newItem.updatedAt = Date()
            items.insert(newItem, at: 0)
        }
        saveItems()
    }

    func updateItem(item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            var updated = item
            updated.updatedAt = Date()
            items[index] = updated
            saveItems()
        }
    }

    func deleteItem(id: UUID) {
        items.removeAll { $0.id == id }
        saveItems()
    }

    func deleteItems(at indexSet: IndexSet) {
        items.remove(atOffsets: indexSet)
        saveItems()
    }

    // MARK: - Filter

    func filteredItems(for categoryID: UUID?) -> [Item] {
        guard let categoryID else { return items }
        return items.filter { $0.categoryID == categoryID }
    }

    // MARK: - Persistence

    func saveItems() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: savePath)
        } catch {
            print("Failed to save items: \(error)")
        }
    }

    func loadItems() {
        guard FileManager.default.fileExists(atPath: savePath.path) else { return }
        do {
            let data = try Data(contentsOf: savePath)
            items = try JSONDecoder().decode([Item].self, from: data)
        } catch {
            print("Failed to load items or no data yet: \(error)")
        }
    }

    // MARK: - Migration（舊格式：category 字串 → 新格式：categoryID UUID）

    /// 呼叫端在 MainActor context 先取好 categories 快照再傳入，避免 actor isolation 問題
    func migrateIfNeeded(using categories: [Category]) {
        let nilUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        guard items.contains(where: { $0.categoryID == nilUUID }) else { return }

        guard let data = try? Data(contentsOf: savePath) else { return }

        // ✅ 用 NameMapRef（class）透過 userInfo 傳入 decoder，取回 itemID → oldName 對照
        let nameMapRef = NameMapRef()
        let decoder = JSONDecoder()
        decoder.userInfo[ItemMigrationKey.categoryNameKey] = nameMapRef

        guard let rawItems = try? decoder.decode([Item].self, from: data) else { return }

        // ✅ 使用傳入的快照，不直接存取 @MainActor 的 categoryStore.categories
        var nameToID: [String: UUID] = [:]
        for cat in categories {
            nameToID[cat.name] = cat.id
        }

        var migrated = rawItems
        for i in migrated.indices {
            if migrated[i].categoryID == nilUUID {
                let oldName = nameMapRef.storage[migrated[i].id.uuidString] ?? ""
                migrated[i].categoryID = nameToID[oldName] ?? nilUUID
            }
        }

        items = migrated
        saveItems()
        print("✅ ItemStore migration complete: \(migrated.count) items updated")
    }
}
