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
        NavigationView {
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
            .navigationTitle("Choose Emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Close") { dismiss() } }
            }
        }
    }
}

private struct ManualEmojiInput: View {
    @Binding var selected: String
    var onDone: () -> Void

    @State private var input: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Or type an emoji")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                TextField("🙂", text: $input)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .onChange(of: input) { oldValue, newValue in
                        // 限制為第一個 character（通常是一個 emoji）
                        if let first = newValue.first {
                            input = String(first)
                        } else {
                            input = ""
                        }
                    }
                    .frame(height: 44)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                    )


                Button("Use") {
                    if let first = input.first {
                        selected = String(first)
                        onDone()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
