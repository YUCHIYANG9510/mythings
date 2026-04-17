//
//  AddCategoryView.swift
//  mythings
//
//  Created by Designer on 2025/4/29.
//

import SwiftUI

struct AddCategoryView: View {
    @ObservedObject var categoryStore: CategoryStore
    @Environment(\.dismiss) var dismiss
    
    // 🌐 監聽語言變更
    @ObservedObject private var localizationManager = LocalizationManager.shared

    @State private var categoryName = ""
    @State private var emoji = "🎧"                 // ⭐️ 預設 emoji
    @State private var showEmojiPicker = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        VStack(spacing: 24) {

            // Header
            HStack {
                Button(L("close")) { dismiss() }
                Spacer()
                Text(L("add_category_title"))
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
                } else if categoryStore.isDuplicateName(trimmed) {
                    alertMessage = L("category_already_exists")
                    showAlert = true
                } else {
                    categoryStore.addCategory(name: trimmed, emoji: emoji)
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
            .padding(.bottom, 8)

            // 依照你的附圖保留 Delete 位置（此畫面新增時通常不需要顯示）
            // Text("Delete").foregroundColor(.secondary)

        }
        .onAppear {
            // 設定預設名稱
            if categoryName.isEmpty {
                categoryName = L("new_category_default")
            }
        }
        .presentationDragIndicator(.hidden)
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
    }
}



