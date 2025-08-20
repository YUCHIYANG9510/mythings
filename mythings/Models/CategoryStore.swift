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
        didSet { saveCategories() }
    }

    private var savePath: URL {
        FileManager.documentsDirectory.appendingPathComponent("categories.json")
    }

    init() {
        loadCategories()

        // 預設分類（僅在無資料時）
        if categories.isEmpty {
            categories = [
                Category(name: "3C Device", emoji: "🎧"),
                Category(name: "Furniture",  emoji: "🪑"),
                Category(name: "Kitchen",    emoji: "🍳"),
                Category(name: "Clothes",    emoji: "👕"),
                Category(name: "Shoes",      emoji: "👟"),
                Category(name: "Bags",       emoji: "🎒")
            ]
            saveCategories()
        }
    }

    // ✅ 新介面：直接用 emoji
    func addCategory(name: String, emoji: String) {
        let newCategory = Category(name: name, emoji: emoji)
        categories.append(newCategory)
    }

    func deleteCategory(at indexSet: IndexSet) {
        categories.remove(atOffsets: indexSet)
    }

    func moveCategory(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
    }
    
    func updateCategory(category: Category) {
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
        }
    }

    private func saveCategories() {
        do {
            let data = try JSONEncoder().encode(categories)
            try data.write(to: savePath, options: [.atomic])
        } catch {
            print("Failed to save categories: \(error)")
        }
    }

    private func loadCategories() {
        guard FileManager.default.fileExists(atPath: savePath.path) else { return }
        do {
            let data = try Data(contentsOf: savePath)

            // 先嘗試新格式（含 emoji）
            if let decoded = try? JSONDecoder().decode([Category].self, from: data) {
                self.categories = decoded
                return
            }

            // 向下相容：舊格式（含 color）
            struct LegacyCategory: Identifiable, Codable {
                var id = UUID()
                var name: String
                var color: String
            }

            if let legacy = try? JSONDecoder().decode([LegacyCategory].self, from: data) {
                // 轉成新格式；沒有 emoji 的舊資料給一個合理預設
                self.categories = legacy.map { old in
                    Category(name: old.name, emoji: defaultEmoji(for: old.name, legacyColor: old.color))
                }
                return
            }

            // 若兩者皆失敗，保持空陣列
            self.categories = []
        } catch {
            print("Failed to load categories or no data yet: \(error)")
        }
    }
}

// MARK: - Helpers

/// 依舊資料名稱/顏色給一個合適的預設 emoji（僅用於舊資料轉換）
private func defaultEmoji(for name: String, legacyColor: String) -> String {
    let lower = name.lowercased()
    if lower.contains("3c") || lower.contains("device") || lower.contains("gadget") { return "🎧" }
    if lower.contains("furniture") { return "🪑" }
    if lower.contains("kitchen") { return "🍳" }
    if lower.contains("clothes") || lower.contains("cloth") || lower.contains("apparel") { return "👕" }
    if lower.contains("shoe") { return "👟" }
    if lower.contains("bag") { return "🎒" }

    // fallback：用顏色大致對應幾個常見類型，或給通用標誌
    switch legacyColor.lowercased() {
    case "blue":   return "📘"
    case "green":  return "🟢"
    case "orange": return "🟠"
    case "purple": return "🟣"
    case "red":    return "🔴"
    case "indigo": return "🔷"
    default:       return "📦"
    }
}
