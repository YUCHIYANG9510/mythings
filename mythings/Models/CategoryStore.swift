//
//  CategoryStore.swift
//  mythings
//
//  Created by Designer on 2025/4/29.
//

import Foundation
import SwiftUI

class CategoryStore: ObservableObject {
    @Published var categories: [Category] = []
    
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
        saveCategories()
    }
    
    func deleteCategory(at indexSet: IndexSet) {
        categories.remove(atOffsets: indexSet)
        saveCategories()
    }
    
    func updateCategory(category: Category) {
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
            saveCategories()
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
    
    func colorForName(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "green": return .green
        case "red": return .red
        case "purple": return .purple
        case "indigo": return .indigo
        case "orange": return .orange
        case "pink": return .pink
        case "yellow": return .yellow
        case "teal": return .teal
        default: return .blue
        }
    }
}
