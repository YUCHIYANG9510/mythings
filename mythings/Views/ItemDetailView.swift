//
//  ItemDetailView.swift
//  mythings
//
//  Created by Designer on 2025/4/29.
//

import SwiftUI
import UIKit

struct ItemDetailView: View {
    let item: Item
    @Environment(\.dismiss) var dismiss
    @State private var image: UIImage?
    @StateObject private var cacheManager = ImageCacheManager.shared
    
    var body: some View {
        VStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 300)
                    .padding()
            }
            Text(item.name)
                .font(.title2)
                .padding(.vertical)
            Text("\(item.brand) · \(item.category)")
                .foregroundColor(.gray)
                .padding(.bottom, 4)
            // ✅ 統一顯示價錢
            Text(item.displayPrice)
                .font(.callout)
        }
        .padding()
        .onTapGesture { dismiss() }
        .onAppear(perform: loadImage)
        .onChangeCompat(of: cacheManager.cacheInvalidationTrigger) { loadImage() }
    }
    
    private func loadImage() {
        let imagePath = FileManager.documentsDirectory.appendingPathComponent(item.imageName).path
        image = UIImage(contentsOfFile: imagePath)
    }
}
