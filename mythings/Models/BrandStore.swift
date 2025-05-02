//
//  BrandStore.swift
//  mythings
//
//  Created by Designer on 2025/5/2.
//

import Foundation
import SwiftUI

class BrandStore: ObservableObject {
    @Published var brands: [String] {
        didSet {
            saveBrands()
        }
    }

    private let saveKey = "SavedBrands"

    init() {
        if let saved = UserDefaults.standard.stringArray(forKey: saveKey) {
            brands = saved
        } else {
            brands = []
        }
    }

    private func saveBrands() {
        UserDefaults.standard.set(brands, forKey: saveKey)
    }
}
