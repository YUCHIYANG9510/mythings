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
    let date: Date?     // ✅ 新增：可選日期（相容舊資料）

    init(
        id: UUID = UUID(),
        imageName: String,
        brand: String,
        category: String,
        name: String,
        price: String,
        date: Date? = nil // ✅ 新增：預設 nil，不影響既有呼叫
    ) {
        self.id = id
        self.imageName = imageName
        self.brand = brand
        self.category = category
        self.name = name
        self.price = price
        self.date = date
    }
}

