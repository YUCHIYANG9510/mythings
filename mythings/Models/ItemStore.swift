//
//  ItemStore.swift
//  mythings
//
//  Created by Designer on 2025/4/29.
//

import Foundation
import SwiftUI

class ItemStore: ObservableObject {
    @Published var items: [Item] = []
    
    private var savePath: URL {
        FileManager.documentsDirectory.appendingPathComponent("items.json")
    }
    
    init() {
        loadItems()
    }
    
    func addItem(item: Item) {
        items.append(item)
        saveItems()
    }
    
    func updateItem(item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
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
    
    func saveItems() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: savePath)
        } catch {
            print("Failed to save items: \(error)")
        }
    }
    
    func loadItems() {
        do {
            let data = try Data(contentsOf: savePath)
            items = try JSONDecoder().decode([Item].self, from: data)
        } catch {
            print("Failed to load items or no data yet: \(error)")
        }
    }
    
    func filteredItems(for category: String) -> [Item] {
        category == "All" ? items : items.filter { $0.category == category }
    }
}
