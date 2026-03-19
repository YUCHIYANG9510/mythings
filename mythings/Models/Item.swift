//
//  Item.swift
//  mythings
//

import Foundation

struct Item: Identifiable, Codable {
    let id: UUID
    let imageName: String
    let brand: String

    // ✅ 根本解法：儲存 Category 的 UUID，改名後自動對應
    var categoryID: UUID

    let name: String
    let price: String
    let date: Date?

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        imageName: String,
        brand: String,
        categoryID: UUID,
        name: String,
        price: String,
        date: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.imageName = imageName
        self.brand = brand
        self.categoryID = categoryID
        self.name = name
        self.price = price
        self.date = date
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, imageName, brand, categoryID, name, price, date, createdAt, updatedAt
        case legacyCategoryName = "category"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,         forKey: .id)
        try c.encode(imageName,  forKey: .imageName)
        try c.encode(brand,      forKey: .brand)
        try c.encode(categoryID, forKey: .categoryID)
        try c.encode(name,       forKey: .name)
        try c.encode(price,      forKey: .price)
        try c.encodeIfPresent(date, forKey: .date)
        try c.encode(createdAt,  forKey: .createdAt)
        try c.encode(updatedAt,  forKey: .updatedAt)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id        = try c.decode(UUID.self,   forKey: .id)
        imageName = try c.decode(String.self, forKey: .imageName)
        brand     = try c.decode(String.self, forKey: .brand)
        name      = try c.decode(String.self, forKey: .name)
        price     = try c.decode(String.self, forKey: .price)
        date      = try c.decodeIfPresent(Date.self, forKey: .date)

        let decodedUpdated = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        updatedAt = decodedUpdated
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
            ?? (decodedUpdated != .distantPast ? decodedUpdated : (date ?? .distantPast))

        if let cid = try c.decodeIfPresent(UUID.self, forKey: .categoryID) {
            // 新格式：直接讀 UUID
            categoryID = cid
        } else {
            // 舊格式遷移：暫用 nilUUID 佔位，migration 時會覆寫
            categoryID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

            // ✅ 用 NameMapRef（純 Swift class）取代 NSMutableDictionary，避免 Sendable 警告
            if let ref = decoder.userInfo[ItemMigrationKey.categoryNameKey] as? NameMapRef {
                let oldName = try c.decodeIfPresent(String.self, forKey: .legacyCategoryName) ?? ""
                ref.storage[id.uuidString] = oldName
            }
        }
    }
}

// MARK: - Migration Helper

enum ItemMigrationKey {
    static let categoryNameKey = CodingUserInfoKey(rawValue: "pendingCategoryNames")!
}
