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
    let date: Date?
    
    var createdAt: Date      // ✅ 新增：建立時間（排序依據）
    var updatedAt: Date      // 已有：最後編輯時間（增量同步依據）

    init(
        id: UUID = UUID(),
        imageName: String,
        brand: String,
        category: String,
        name: String,
        price: String,
        date: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.imageName = imageName
        self.brand = brand
        self.category = category
        self.name = name
        self.price = price
        self.date = date
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, imageName, brand, category, name, price, date, createdAt, updatedAt
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

        let decodedUpdated = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        updatedAt = decodedUpdated

        // ✅ 舊檔相容：沒 createdAt 時，用 updatedAt（若也沒有就用 date / distantPast）
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
            ?? (decodedUpdated != .distantPast ? decodedUpdated : (date ?? .distantPast))
    }
}
