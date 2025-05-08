//
//  mythingsApp.swift
//  mythings
//
//  Created by Designer on 2025/4/23.
//

import SwiftUI

@main
struct MyThingsApp: App {
    @AppStorage("isDarkMode") private var isDarkMode = false
    @StateObject var categoryStore = CategoryStore()

    var body: some Scene {
        WindowGroup {
            ContentView(categoryStore: categoryStore)
                    .preferredColorScheme(isDarkMode ? .dark : .light)
        }
    }
}

