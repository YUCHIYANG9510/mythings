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
    var body: some View {
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
                }
            }
            .padding(.horizontal)
        }
    }
}
