//
//  CloudKitAppDelegate.swift
//  mythings
//
//  ✅ FIX: 處理 CloudKit 遠端推播通知
//  讓其他裝置的變更能即時同步到本機，而不是只靠 App 啟動才觸發
//
//  使用方式：在你的 mythingsApp.swift（或主 App struct）加上：
//
//      @UIApplicationDelegateAdaptor(CloudKitAppDelegate.self) var appDelegate
//
//  同時在 Xcode → Target → Signing & Capabilities 確認已開啟：
//  - iCloud（含 CloudKit）
//  - Background Modes → Remote notifications
//  - Push Notifications
//

import UIKit
import CloudKit
import SwiftUI

final class CloudKitAppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 向 APNs 註冊遠端推播通知
        application.registerForRemoteNotifications()
        return true
    }

    // APNs 註冊成功（token 不需要特別處理，CloudKit 自動管理）
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Successfully registered for remote notifications
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("⚠️ Failed to register for remote notifications: \(error)")
        // 非致命錯誤：模擬器上無法接收推播，但不影響手動同步
    }

    // ✅ 核心：收到 CloudKit 遠端推播時，觸發同步
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // 只處理 CloudKit 的通知
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              notification.notificationID != nil else {
            completionHandler(.noData)
            return
        }

        // 找到 iCloudSyncManager 並觸發同步
        // 透過 NotificationCenter 廣播，避免直接依賴 EnvironmentObject
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .iCloudRemoteNotificationReceived,
                object: nil
            )
        }

        // 給 background fetch 足夠時間完成同步（最長 30 秒）
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            completionHandler(.newData)
        }
    }
}

// MARK: - Notification Names（集中在這裡方便管理）
extension Notification.Name {
    static let iCloudRemoteNotificationReceived = Notification.Name("iCloudRemoteNotificationReceived")
}
