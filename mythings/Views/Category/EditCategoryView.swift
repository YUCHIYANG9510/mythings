//
//  EditCategoryView.swift
//  mythings
//
//  Created by Designer on 2025/8/20.
//


import SwiftUI

struct EditCategoryView: View {
    @ObservedObject var categoryStore: CategoryStore
    @Environment(\.dismiss) var dismiss
    
    let category: Category
    
    // 🌐 監聽語言變更
    @ObservedObject private var localizationManager = LocalizationManager.shared
    
    @State private var categoryName = ""
    @State private var emoji = ""
    @State private var showEmojiPicker = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showDeleteAlert = false

    var body: some View {
        VStack(spacing: 24) {

            // Header
            HStack {
                Button(L("close")) { dismiss() }
                Spacer()
                Text(L("edit_category_title"))
                    .font(.title2.weight(.bold))
                Spacer()
                // 右側保留空間對齊
                Color.clear.frame(width: 48, height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 32)

            // Emoji 選擇區
            Button {
                showEmojiPicker.toggle()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.black.opacity(0.06), radius: 12, y: 4)
                        .frame(width: 160, height: 160)

                    Text(emoji).font(.system(size: 64))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            // 名稱輸入
            VStack(alignment: .leading, spacing: 8) {
                Text(L("category_name_label"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField(L("category_name_field"), text: $categoryName)
                    .textInputAutocapitalization(.words)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)

            // Save 按鈕（黑底）
            Button {
                let trimmed = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if trimmed.isEmpty {
                    alertMessage = L("please_enter_category_name")
                    showAlert = true
                } else if categoryStore.isDuplicateName(trimmed, excludingID: category.id) {
                    alertMessage = L("category_already_exists")
                    showAlert = true
                } else {
                    let updatedCategory = Category(
                        id: category.id,
                        name: trimmed,
                        emoji: emoji
                    )
                    categoryStore.updateCategory(category: updatedCategory)
                    dismiss()
                }
            } label: {
                Text(L("save"))
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color.black))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)

            // Delete 按鈕
            Button {
                showDeleteAlert = true
            } label: {
                Text(L("delete"))
                    .foregroundColor(.red)
            }
            .padding(.bottom, 8)

        }
        .presentationDragIndicator(.hidden)
        .onAppear {
            // 初始化編輯的值
            categoryName = category.name
            emoji = category.emoji
        }
        .sheet(isPresented: $showEmojiPicker) {
            EmojiPickerView(selected: $emoji)
                .presentationDetents([.fraction(0.7)])
                .presentationCornerRadius(40)

        }
        .alert(L("error"), isPresented: $showAlert) {
            Button(L("ok"), role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .alert(L("delete_category_title"), isPresented: $showDeleteAlert) {
            Button(L("cancel"), role: .cancel) { }
            
            Button(L("delete"), role: .destructive) {
                if let index = categoryStore.categories.firstIndex(where: { $0.id == category.id }) {
                    categoryStore.deleteCategory(at: IndexSet(integer: index))
                }
                dismiss()
            }
        } message: {
            Text(L("delete_category_message"))
        }
    }
}

#Preview {
    let previewStore = CategoryStore()
    let sampleCategory = Category(name: "3C Device", emoji: "🎧")
    
    return EditCategoryView(categoryStore: previewStore, category: sampleCategory)
}
