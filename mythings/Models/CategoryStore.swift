//
//  CategoryStore.swift
//  mythings
//
//  Created by Designer on 2025/4/29.
//



import Foundation
import SwiftUI

@MainActor
class CategoryStore: ObservableObject {
    @Published var categories: [Category] = [] {
        didSet { saveCategories() }
    }

    private var savePath: URL {
        FileManager.documentsDirectory.appendingPathComponent("categories.json")
    }

    private let iCloudSync: iCloudSyncManager

    init(iCloudSync: iCloudSyncManager) {
        self.iCloudSync = iCloudSync
        loadCategories()

        // ✅ No default categories - users start with an empty category list
        // They can add their own categories as needed
        
        // ✅ Listen for successful sync and reload categories
        // This ensures we pick up synced categories from other devices
        NotificationCenter.default.addObserver(
            forName: .iCloudCategoriesSynced,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadCategories()
            print("📂 CategoryStore: Reloaded categories after iCloud sync")
        }
    }

    convenience init() {
        self.init(iCloudSync: iCloudSyncManager())
    }

    // MARK: - Lookup Helpers

    /// UUID → Category name（用於顯示）
    func name(for id: UUID) -> String {
        categories.first(where: { $0.id == id })?.name ?? "Unknown"
    }

    /// Category name → UUID（用於建立新 Item 時）
    func id(for name: String) -> UUID? {
        categories.first(where: { $0.name == name })?.id
    }

    /// UUID → Category（完整物件）
    func category(for id: UUID) -> Category? {
        categories.first(where: { $0.id == id })
    }

    // MARK: - CRUD

    func addCategory(name: String, emoji: String) {
        let newCategory = Category(name: name, emoji: emoji)
        categories.append(newCategory)
    }

    func deleteCategory(at indexSet: IndexSet) {
        let idsToDelete = indexSet.map { categories[$0].id }
        categories.remove(atOffsets: indexSet)

        if iCloudSync.isEnabled {
            for id in idsToDelete {
                iCloudSync.schedule(.deleteCategory(id))
            }
        }
    }

    func moveCategory(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
    }

    func updateCategory(category: Category) {
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            // ✅ 只更新 Category 本身即可
            // Item 存的是 categoryID（UUID），不受 name 變動影響
            categories[index] = category
        }
    }

    // MARK: - Persistence

    func saveCategories() {
        do {
            let data = try JSONEncoder().encode(categories)
            try data.write(to: savePath)
            if iCloudSync.isEnabled {
                iCloudSync.schedule(.categoriesChanged)
            }
        } catch {
            print("儲存分類失敗：\(error)")
        }
    }

    private func loadCategories() {
        guard FileManager.default.fileExists(atPath: savePath.path) else { return }
        do {
            let data = try Data(contentsOf: savePath)

            if let decoded = try? JSONDecoder().decode([Category].self, from: data) {
                self.categories = decoded
                return
            }

            struct SimpleCategoryCompat: Identifiable, Codable {
                var id: UUID
                var name: String
            }
            if let simple = try? JSONDecoder().decode([SimpleCategoryCompat].self, from: data) {
                self.categories = simple.map { sc in
                    let emoji = defaultEmoji(for: sc.name, legacyColor: "")
                    return Category(id: sc.id, name: sc.name, emoji: emoji)
                }
                return
            }

            struct LegacyCategory: Identifiable, Codable {
                var id = UUID()
                var name: String
                var color: String
            }
            if let legacy = try? JSONDecoder().decode([LegacyCategory].self, from: data) {
                self.categories = legacy.map { old in
                    Category(name: old.name, emoji: defaultEmoji(for: old.name, legacyColor: old.color))
                }
                return
            }

            self.categories = []
        } catch {
            print("Failed to load categories or no data yet: \(error)")
        }
    }
}

// MARK: - Helpers

private func defaultEmoji(for name: String, legacyColor: String) -> String {
    let lower = name.lowercased()
    if lower.contains("3c") || lower.contains("device") || lower.contains("gadget") { return "🎧" }
    if lower.contains("furniture") { return "🪑" }
    if lower.contains("kitchen") { return "🍳" }
    if lower.contains("clothes") || lower.contains("cloth") || lower.contains("apparel") { return "👕" }
    if lower.contains("shoe") { return "👟" }
    if lower.contains("bag") { return "🎒" }

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
