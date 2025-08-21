//
//  CategoryScrollView.swift
//  mythings
//
//  Created by Designer on 2025/8/15.
//

import SwiftUI

struct CategoryScrollView: View {
    let categoryNames: [String]
    @Binding var selectedCategory: String
    @State private var scrollID: String? // iOS 17+

    var body: some View {
        if #available(iOS 17.0, *) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categoryNames, id: \.self) { category in
                        Button(action: { selectedCategory = category }) {
                            Text(category)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .font(.caption)
                                .background(selectedCategory == category ? Color.primary : Color.gray.opacity(0.2))
                                .foregroundColor(selectedCategory == category ? Color.textcolor : Color.primary)
                                .clipShape(Capsule())
                        }
                        .id(category) // 讓 scroll 定位用
                    }
                }
                .padding(.horizontal)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrollID)
            .onAppear {
                // 首次進入時讓選中項目可見（置中對齊）
                scrollID = selectedCategory
            }
            .onChange(of: selectedCategory) { _, new in
                withAnimation(.smooth(duration: 0.25)) {
                    scrollID = new
                }
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categoryNames, id: \.self) { category in
                            Button(action: { selectedCategory = category }) {
                                Text(category)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .font(.caption)
                                    .background(selectedCategory == category ? Color.primary : Color.gray.opacity(0.2))
                                    .foregroundColor(selectedCategory == category ? Color.textcolor : Color.primary)
                                    .clipShape(Capsule())
                            }
                            .id(category)
                        }
                    }
                    .padding(.horizontal)
                }
                .onAppear {
                    proxy.scrollTo(selectedCategory, anchor: .center)
                }
                .onChange(of: selectedCategory) { _, new in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(new, anchor: .center)
                    }
                }
            }
        }
    }
}

