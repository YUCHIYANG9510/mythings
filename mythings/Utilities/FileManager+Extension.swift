//
//  FileManager+Extension.swift
//  mythings
//
//  Created by Designer on 2025/4/29.
//

import Foundation

extension FileManager {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
