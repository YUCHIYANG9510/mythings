//
//  mythingsApp.swift
//  mythings
//
//  Created by Designer on 2025/4/23.
//

import SwiftUI
import RevenueCat

@main
struct MyThingsApp: App {
    @AppStorage("isDarkMode") private var isDarkMode = false

    @StateObject private var iCloudSync: iCloudSyncManager
    @StateObject private var categoryStore: CategoryStore
    @StateObject private var purchasesManager: PurchasesManager

    init() {
        // ① RevenueCat 初始化（只呼叫一次）
        Purchases.logLevel = .debug                 // 上架前可改成 .warn
        Purchases.configure(withAPIKey: "appl_cifqZHzabysVBxNHvgqyqFrrruT") // ← 換成你的 RC Public SDK Key

        // ② 你的既有同步與資料層初始化
        let sync = iCloudSyncManager()
        _iCloudSync = StateObject(wrappedValue: sync)
        _categoryStore = StateObject(wrappedValue: CategoryStore(iCloudSync: sync))

        // ③ 購買管理（讀 entitlement、提供價格、購買/還原）
        _purchasesManager = StateObject(wrappedValue: PurchasesManager())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(categoryStore: categoryStore)
                .environmentObject(iCloudSync)         // ⬅️ iCloud Sync Manager
                .environmentObject(purchasesManager)   // ⬅️ RevenueCat Purchases Manager
                .preferredColorScheme(isDarkMode ? .dark : .light)
                .task {
                    // 首次進入時，依目前權益設定 iCloud
                    iCloudSync.isEnabled = purchasesManager.isPro
                }
                // iOS 17 的兩參數 onChange
                .onChange(of: purchasesManager.isPro) { _, newValue in
                    iCloudSync.isEnabled = newValue
                }
        }
    }

}

