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

    @StateObject private var iCloudSync = iCloudSyncManager()
    @StateObject private var categoryStore: CategoryStore

    init() {
        let sync = iCloudSyncManager()
        _iCloudSync = StateObject(wrappedValue: sync)
        _categoryStore = StateObject(wrappedValue: CategoryStore(iCloudSync: sync))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(categoryStore: categoryStore)
                .environmentObject(iCloudSync)         // ⬅️ 關鍵
                .preferredColorScheme(isDarkMode ? .dark : .light)
        }
    }
}
