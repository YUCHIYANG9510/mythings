//
//  EmojiPickerView.swift
//  mythings
//
//  Created by Designer on 2025/8/20.
//

import SwiftUI

struct EmojiPickerView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selected: String

    // 常用集，之後你可換成更大的表或從遠端載入
    private let emojis: [String] = [
        "👕","👖","👗","🧥","🧢","🎒","👟","👠","🧦","🧤",
        "🎮","🧸","📱","💻","🎧","⌚️","📷","💡","🪑","🛋️",
        "🍎","🍔","🍰","☕️","🧴","🧼","🪥","🧽","🧻","🧺"
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    var body: some View {
           VStack(spacing: 24) {
               // Header
               HStack {
                   Button("Close") { dismiss() }
                   Spacer()
                   Text("Choose Emoji")
                       .font(.title2.weight(.bold))
                   Spacer()
                   // 右側保留空間對齊
                   Color.clear.frame(width: 48, height: 1)
               }
               .padding(.horizontal, 20)
               .padding(.top, 32)
               
               ScrollView {
                   LazyVGrid(columns: columns, spacing: 12) {
                       ForEach(emojis, id: \.self) { e in
                           Button {
                               selected = e
                               dismiss()
                           } label: {
                               Text(e)
                                   .font(.system(size: 28))
                                   .frame(width: 44, height: 44)
                                   .background(
                                       RoundedRectangle(cornerRadius: 12, style: .continuous)
                                           .fill(Color(.secondarySystemBackground))
                                   )
                           }
                           .buttonStyle(.plain)
                       }
                   }
                   .padding(16)

                   // 想手動輸入任意 emoji（例如從鍵盤挑）
                   ManualEmojiInput(selected: $selected) {
                       dismiss()
                   }
                   .padding(.horizontal, 16)
                   .padding(.bottom, 20)
               }
           }
           .presentationDragIndicator(.hidden)
       }
   }

   struct ManualEmojiInput: View {
       @Binding var selected: String
       @State private var inputEmoji = ""
       let onComplete: () -> Void
       
       var body: some View {
           VStack(alignment: .leading, spacing: 12) {
               Text("Or enter any emoji")
                   .font(.subheadline)
                   .foregroundStyle(.secondary)
               
               HStack {
                   TextField("Type emoji here", text: $inputEmoji)
                       .font(.system(size: 16))
                       .padding(16)
                       .background(
                           RoundedRectangle(cornerRadius: 8, style: .continuous)
                               .fill(Color(.systemGray6))  // 淺灰底色
                       )
                   
                   Button("Use") {
                       if !inputEmoji.isEmpty {
                           selected = inputEmoji
                           onComplete()
                       }
                   }
                   .buttonStyle(.borderedProminent)
                   .disabled(inputEmoji.isEmpty)
                   .padding(12)
            }
           }
           .padding(.vertical, 12)
           .padding(.horizontal, 16)
           .background(
               RoundedRectangle(cornerRadius: 16, style: .continuous)
                   .fill(Color(.tertiarySystemBackground))
           )
       }
   }


#Preview {
    EmojiPickerView(selected: .constant("🎮"))
}
