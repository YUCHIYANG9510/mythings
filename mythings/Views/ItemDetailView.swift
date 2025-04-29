//
//  ItemDetailView.swift
//  mythings
//
//  Created by Designer on 2025/4/29.
//

import SwiftUI

struct ItemDetailView: View {
    let item: Item
    @Environment(\.dismiss) var dismiss
    @State private var image: UIImage?
    
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
            Text("$\(item.price)")
                .font(.headline)
        }
        .padding()
        .onTapGesture {
            dismiss()
        }
        .onAppear {
            let imagePath = FileManager.documentsDirectory.appendingPathComponent(item.imageName).path
            if let uiImage = UIImage(contentsOfFile: imagePath) {
                self.image = uiImage
            }
        }
    }
}
