//
//  ManageCategoriesView.swift
//  mythings
//
//  Created by Designer on 2025/4/29.
//

import SwiftUI

struct ManageCategoriesView: View {
    @ObservedObject var categoryStore: CategoryStore
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var iCloudSync: iCloudSyncManager

    // 🔑 RevenueCat：用於分類數量 gating（免費上限 6）
    @EnvironmentObject private var pm: PurchasesManager
    @State private var showPaywall = false

    @Environment(\.editMode) private var editMode
    @State private var showAddCategoryView = false
    @State private var editingCategory: Category? = nil

    // 單筆刪除
    @State private var pendingDelete: IndexSet? = nil
    @State private var showDeleteAlert = false

    // 全刪
    @State private var showResetAllAlert = false

    // MARK: - Derived States（降低型別推斷負擔）
    private var isEditing: Bool { (editMode?.wrappedValue.isEditing ?? false) }
    private var canAddCategory: Bool { pm.canAddCategory(currentCount: categoryStore.categories.count) }
    private var showProBadgeOnNew: Bool { !pm.isPro && categoryStore.categories.count >= 6 }
    private var resetAlertMessage: String {
        iCloudSync.isEnabled
        ? "Clear all categories locally. Also clears iCloud and resyncs."
        : "Clear all categories locally."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // 列表
            List {
                Section {
                    ForEach(categoryStore.categories) { category in
                        CategoryRow(category: category)
                            .contentShape(Rectangle())
                            .onTapGesture { editingCategory = category }
                    }
                    .onDelete { indexSet in
                        pendingDelete = indexSet
                        showDeleteAlert = true
                    }
                    .onMove(perform: moveCategories)
                }
            }
            .listStyle(.insetGrouped)

            // 編輯模式才顯示全刪
            if isEditing {
                DeleteAllCategoriesButton {
                    showResetAllAlert = true
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }

            // 新增分類（含 Pro 限制徽章）
            NewCategoryButton(
                showProBadge: showProBadgeOnNew,
                onTap: handleTapNewCategory
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            Spacer(minLength: 0)
        }
        .navigationTitle("Manage Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { EditButton() }
        }

        // Add / Edit
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

        // 付費牆
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(pm)
        }

        // 單筆刪除確認
        .alert("Delete Category?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) { confirmDeleteSelected() }
        } message: {
            Text("This action cannot be undone.")
        }

        // 全刪確認
        .alert("Reset Categories?", isPresented: $showResetAllAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) { resetAllCategories() }
        } message: {
            Text(resetAlertMessage)
        }
    }

    // MARK: - Actions

    private func handleTapNewCategory() {
        if canAddCategory {
            showAddCategoryView = true
        } else {
            showPaywall = true
        }
    }

    private func confirmDeleteSelected() {
        if let idx = pendingDelete {
            categoryStore.deleteCategory(at: idx)
        }
        pendingDelete = nil
    }

    @MainActor
    private func resetAllCategories() {
        // 1) 清本機
        categoryStore.categories.removeAll()

        // 2) 選擇性清雲端 + 排程一次完整同步（協調器會序列化與合併事件）
        if iCloudSync.isEnabled {
            Task {
                await iCloudSync.purgeAllCategoriesCloud()   // 需要在 iCloudSyncManager 補上公開方法
                iCloudSync.schedule(.full)
            }
        }
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        categoryStore.moveCategory(from: source, to: destination)
    }
}

// MARK: - Subviews

private struct CategoryRow: View {
    let category: Category
    var body: some View {
        HStack(spacing: 16) {
            Text(category.emoji)
                .font(.system(size: 28))
                .frame(width: 32, height: 32)
            Text(category.name)
                .font(.body)
            Spacer()
        }
        .padding(.vertical, 2.5)
    }
}

private struct NewCategoryButton: View {
    let showProBadge: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .imageScale(.large)
                Text("New Category")
                    .font(.title3.weight(.semibold))

                if showProBadge {
                    Spacer()
                    Text("Pro")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                } else {
                    Spacer()
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct DeleteAllCategoriesButton: View {
    let onTap: () -> Void
    var body: some View {
        Button(role: .destructive, action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "trash.fill")
                    .imageScale(.large)
                Text("Delete All Categories")
                    .font(.title3.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
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
    .environmentObject(iCloudSyncManager())
    .environmentObject(PurchasesManager())
}
