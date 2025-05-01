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
           /* Text("\(item.brand) · \(item.category)")
                .foregroundColor(.gray)
                .padding(.bottom, 4) */
            HStack{
                Text("\(item.brand) ·")
                Text("\(item.category)")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .font(.caption)
                    .background(Color(UIColor.systemGray5))
                    .foregroundColor(Color.black)
                    .clipShape(Capsule())
            }
            .padding(.bottom, 4)
            if let price = Double(item.price) {
                Text("$\(formattedPrice(price))")
                    .font(.callout)
                    .foregroundColor(.black)
            } else {
                Text("$\(item.price)")
                    .font(.callout)
                    .foregroundColor(.black)
            }
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
    
    private func formattedPrice(_ price: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: price)) ?? "\(price)"
    }
}
