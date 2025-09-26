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
    let date: Date?          // 可選日期（相容舊資料）
    var updatedAt: Date      // ⭐ 新增：本機最後編輯時間（用於增量同步判斷）

    init(
        id: UUID = UUID(),
        imageName: String,
        brand: String,
        category: String,
        name: String,
        price: String,
        date: Date? = nil,
        updatedAt: Date = Date()   // ⭐ 預設為現在，新增或編輯時會刷新
    ) {
        self.id = id
        self.imageName = imageName
        self.brand = brand
        self.category = category
        self.name = name
        self.price = price
        self.date = date
        self.updatedAt = updatedAt
    }

    // 舊檔相容：舊 JSON 沒有 updatedAt 時給 .distantPast
    enum CodingKeys: String, CodingKey {
        case id, imageName, brand, category, name, price, date, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self, forKey: .id)
        imageName = try c.decode(String.self, forKey: .imageName)
        brand     = try c.decode(String.self, forKey: .brand)
        category  = try c.decode(String.self, forKey: .category)
        name      = try c.decode(String.self, forKey: .name)
        price     = try c.decode(String.self, forKey: .price)
        date      = try c.decodeIfPresent(Date.self, forKey: .date)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}
