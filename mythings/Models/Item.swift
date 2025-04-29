//
//  Item.swift
//  mythings
//
//  Created by Designer on 2025/4/29.
//

import Foundation

struct Item: Identifiable, Codable {
    let id: UUID
    let imageName: String
    let brand: String
    let category: String
    let name: String
    let price: String

    init(id: UUID = UUID(), imageName: String, brand: String, category: String, name: String, price: String) {
        self.id = id
        self.imageName = imageName
        self.brand = brand
        self.category = category
        self.name = name
        self.price = price
    }
}
