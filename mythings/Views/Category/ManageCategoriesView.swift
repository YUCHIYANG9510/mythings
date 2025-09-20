//  ManageCategoriesView.swift
//  mythings
//
//  Created by Designer on 2025/4/29.
//

import SwiftUI

struct ManageCategoriesView: View {
    @ObservedObject var categoryStore: CategoryStore
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var iCloudSync: iCloudSyncManager

    // 🔑 RevenueCat：用於分類數量 gating（免費上限 6）
    @EnvironmentObject private var pm: PurchasesManager
    @State private var showPaywall = false

    @Environment(\.editMode) private var editMode
    @State private var showAddCategoryView = false
    @State private var editingCategory: Category? = nil

    // 確認刪除所需狀態
    @State private var pendingDelete: IndexSet? = nil
    @State private var showDeleteAlert = false
    @State private var showResetAllAlert = false

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

            // 僅在編輯模式顯示 Reset，放在 New Category 之上
            if editMode?.wrappedValue.isEditing == true {
                Button(role: .destructive) {
                    showResetAllAlert = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trash.fill")
                            .imageScale(.large)
                        Text("Delete All Categories")
                            .font(.title3.weight(.semibold))
                        Spacer()
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }

            Button {
                // ✅ 限制：免費用戶最多 6 個分類；超過則彈付費牆
                if pm.canAddCategory(currentCount: categoryStore.categories.count) {
                    showAddCategoryView = true
                } else {
                    showPaywall = true
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.large)
                    Text("New Category")
                        .font(.title3.weight(.semibold))

                    // 小提示：非 Pro 且已達上限時顯示 Pro badge
                    if !pm.isPro && categoryStore.categories.count >= 6 {
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
                // （可選）若擔心其它入口能新增分類，可在 AddCategoryView 的保存動作再檢一次 pm.canAddCategory
        }
        .sheet(item: $editingCategory) { category in
            EditCategoryView(categoryStore: categoryStore, category: category)
                .presentationDetents([.fraction(0.7)])
                .presentationCornerRadius(40)
        }

        // 付費牆（當達到上限時彈出）
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(pm)
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

        // Reset（本機 + iCloud）確認對話框
        .alert("Reset Categories?", isPresented: $showResetAllAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task { @MainActor in
                    // 1) 清本機
                    categoryStore.categories.removeAll()

                    // 2) 僅在啟用 iCloud（= Pro）時清雲端，避免免費用戶觸發雲端操作
                    if iCloudSync.isEnabled {
                        await iCloudSync.purgeAllCategoriesCloud()
                        iCloudSync.manualSync()
                    }
                }
            }
        } message: {
            Text("Clear all categories locally.\(iCloudSync.isEnabled ? " Also clears iCloud and resyncs." : "")")
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

    // ✅ 預覽注入必要的 EnvironmentObject，避免崩潰
    return NavigationStack {
        ManageCategoriesView(categoryStore: previewStore)
    }
    .environmentObject(iCloudSyncManager())
    .environmentObject(PurchasesManager())
}
