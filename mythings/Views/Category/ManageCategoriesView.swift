//  ManageCategoriesView.swift
//  mythings
//
//  Created by Designer on 2025/4/29.
//

import SwiftUI

struct ManageCategoriesView: View {
    @ObservedObject var categoryStore: CategoryStore
    @Environment(\.dismiss) var dismiss
    @State private var showAddCategoryView = false
    @State private var editingCategory: Category? = nil

    // 確認刪除所需狀態
    @State private var pendingDelete: IndexSet? = nil
    @State private var showDeleteAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            List {
                Section {
                    ForEach(categoryStore.categories) { category in
                        HStack(spacing: 16) {
                            Text(category.emoji)
                                .font(.system(size: 28))
                                .frame(width: 32, height: 32)

                            Text(category.name)
                                .font(.body)

                            Spacer()
                        }
                        .padding(.vertical, 2.5)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingCategory = category
                        }
                    }
                    .onDelete { indexSet in
                        // 先暫存，等使用者確認
                        pendingDelete = indexSet
                        showDeleteAlert = true
                    }
                    .onMove(perform: moveCategories)
                }
            }
            .listStyle(.insetGrouped)

            Button {
                showAddCategoryView = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.large)
                    Text("New Category")
                        .font(.title3.weight(.semibold))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .navigationTitle("Manage Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
        .sheet(isPresented: $showAddCategoryView) {
            AddCategoryView(categoryStore: categoryStore)
                .presentationDetents([.fraction(0.7)])
                .presentationCornerRadius(40)
        }
        .sheet(item: $editingCategory) { category in
            EditCategoryView(categoryStore: categoryStore, category: category)
                .presentationDetents([.fraction(0.7)])
                .presentationCornerRadius(40)
        }
        // 刪除確認對話框
        .alert("Delete Category?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
            
            Button("Delete", role: .destructive) {
                if let idx = pendingDelete {
                    categoryStore.deleteCategory(at: idx)
                }
                pendingDelete = nil
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }
    
    private func moveCategories(from source: IndexSet, to destination: Int) {
        categoryStore.moveCategory(from: source, to: destination)
    }
}

#Preview {
    let previewStore = CategoryStore()
    previewStore.categories = [
        Category(name: "3C Device", emoji: "🎧"),
        Category(name: "Furniture", emoji: "🪑"),
        Category(name: "Kitchen", emoji: "🍳"),
        Category(name: "Clothes", emoji: "👕"),
        Category(name: "Shoes", emoji: "👟"),
        Category(name: "Bags", emoji: "🎒")
    ]
    return NavigationStack {
        ManageCategoriesView(categoryStore: previewStore)
    }
}
