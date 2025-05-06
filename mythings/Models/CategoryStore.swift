//
//  CategoryStore.swift
//  mythings
//
//  Created by Designer on 2025/4/29.
//

import Foundation
import SwiftUI

class CategoryStore: ObservableObject {
    @Published var categories: [Category] = [] {
        didSet {
            saveCategories()
        }
    }

    private var savePath: URL {
        FileManager.documentsDirectory.appendingPathComponent("categories.json")
    }

    init() {
        loadCategories()

        // Add default categories if none exist
        if categories.isEmpty {
            categories = [
                Category(name: "3C Device", color: "blue"),
                Category(name: "Furniture", color: "green"),
                Category(name: "Kitchen", color: "orange"),
                Category(name: "Clothes", color: "purple"),
                Category(name: "Shoes", color: "red"),
                Category(name: "Bags", color: "indigo")
            ]
            saveCategories()
        }
    }

    func addCategory(name: String, color: String = "blue") {
        let newCategory = Category(name: name, color: color)
        categories.append(newCategory)
    }

    func deleteCategory(at indexSet: IndexSet) {
        categories.remove(atOffsets: indexSet)
    }

    func updateCategory(category: Category) {
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
        }
    }

    private func saveCategories() {
        do {
            let data = try JSONEncoder().encode(categories)
            try data.write(to: savePath)
        } catch {
            print("Failed to save categories: \(error)")
        }
    }

    private func loadCategories() {
        do {
            let data = try Data(contentsOf: savePath)
            categories = try JSONDecoder().decode([Category].self, from: data)
        } catch {
            print("Failed to load categories or no data yet: \(error)")
        }
    }

    /// 根據儲存的顏色名稱回傳對應的 SwiftUI `Color` 物件
    func colorForName(_ name: String) -> Color {
        let colorMap: [String: Color] = [
            "blue": .blue,
            "green": .green,
            "red": .red,
            "purple": .purple,
            "indigo": .indigo,
            "orange": .orange,
            "pink": .pink,
            "yellow": .yellow,
            "teal": .teal,
            "gray": .gray
        ]

        return colorMap[name, default: .blue]
    }
}
