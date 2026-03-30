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
                Button("Close") { dismiss() }
                Spacer()
                Text("Edit Category")
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
                Text("Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Name", text: $categoryName)
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
                    alertMessage = "Please enter a category name"
                    showAlert = true
                } else if categoryStore.isDuplicateName(trimmed, excludingID: category.id) {
                    alertMessage = "A category with this name already exists"
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
                Text("Save")
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
                Text("Delete")
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
        .alert("Error", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .alert("Delete Category?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            
            Button("Delete", role: .destructive) {
                if let index = categoryStore.categories.firstIndex(where: { $0.id == category.id }) {
                    categoryStore.deleteCategory(at: IndexSet(integer: index))
                }
                dismiss()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }
}

#Preview {
    let previewStore = CategoryStore()
    let sampleCategory = Category(name: "3C Device", emoji: "🎧")
    
    return EditCategoryView(categoryStore: previewStore, category: sampleCategory)
}
