//
//  Category.swift
//  mythings
//
//  Created by Designer on 2025/4/29.
//
import Foundation

struct Category: Identifiable, Codable, Hashable, Equatable {
    let id: UUID
    var name: String
    var color: String
    
    init(id: UUID = UUID(), name: String, color: String = "blue") {
        self.id = id
        self.name = name
        self.color = color
    }
}
