//
//  CloudKitSyncManager.swift
//  mythings
//
//  Created by Designer on 2025/9/9.
//

import Foundation
import SwiftUI
import Combine
import CloudKit
import UIKit

// MARK: - Sync status
enum iCloudSyncStatus: Equatable {
    case idle
    case syncing
    case success
    case error(String)

    static func == (lhs: iCloudSyncStatus, rhs: iCloudSyncStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.syncing, .syncing), (.success, .success):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Sync Events
enum SyncEvent: Hashable {
    case itemsChanged
    case categoriesChanged
    case deleteItem(UUID)
    case deleteCategory(UUID)
    case full
}

// MARK: - App Error Types
enum SyncError: Error, LocalizedError {
    case iCloudUnavailable
    case networkError(underlying: Error)
    case dataCorrupted(String)
    case quotaExceeded
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud 服務不可用，請檢查設定"
        case .networkError(let error):
            return "網路連接問題：\(error.localizedDescription)"
        case .dataCorrupted(let message):
            return "資料錯誤：\(message)"
        case .quotaExceeded:
            return "iCloud 儲存空間不足"
        case .authenticationFailed:
            return "iCloud 帳號驗證失敗"
        }
    }
}

// MARK: - 單一協調器
actor SyncCoordinator {
    private var isSyncing = false
    private var pending = Set<SyncEvent>()
    private let minInterval: TimeInterval = 0.7
    private var lastRun: Date = .distantPast

    func enqueue(_ event: SyncEvent, runners: Runners) async {
        pending.insert(event)
        await maybeRun(runners: runners)
    }

    private func maybeRun(runners: Runners) async {
        guard !isSyncing else { return }
        let since = Date().timeIntervalSince(lastRun)
        if since < minInterval {
            let ns = UInt64((minInterval - since) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
        }
        guard !isSyncing else { return }
        isSyncing = true
        let batch = pending
        pending.removeAll()
        await runners.setStatus(.syncing)
        do {
            try await run(batch, runners: runners)
            lastRun = Date()
            await runners.setStatus(.success)
        } catch is CancellationError {
            await runners.setStatus(.idle)
        } catch {
            await runners.setStatus(.error("Sync failed: \(error.localizedDescription)"))
        }
        isSyncing = false
        if !pending.isEmpty { await maybeRun(runners: runners) }
    }

    private func run(_ batch: Set<SyncEvent>, runners: Runners) async throws {
        let deleteItemIDs = batch.compactMap { if case let .deleteItem(id) = $0 { return id } else { return nil } }
        for id in deleteItemIDs { try await runners.deleteItem(id) }

        let deleteCategoryIDs = batch.compactMap { if case let .deleteCategory(id) = $0 { return id } else { return nil } }
        for id in deleteCategoryIDs { try await runners.deleteCategory(id) }

        if batch.contains(.full) { try await runners.full(); return }

        if batch.contains(.itemsChanged) {
            try await runners.optimized()
        } else if batch.contains(.categoriesChanged) {
            try await runners.categoriesOnly()
        }
    }

    struct Runners {
        let optimized: () async throws -> Void
        let categoriesOnly: () async throws -> Void
        let full: () async throws -> Void
        let deleteItem: (UUID) async throws -> Void
        let deleteCategory: (UUID) async throws -> Void
        let setStatus: (iCloudSyncStatus) async -> Void
    }
}

// MARK: - ImageStore
struct ImageStore {
    let fm = FileManager.default
    let documentsDir: URL
    let imagesDir: URL

    init() {
        documentsDir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        imagesDir = documentsDir.appendingPathComponent("Images", isDirectory: true)
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
    }

    func sanitizedFileName(_ raw: String) -> String {
        let last = (raw as NSString).lastPathComponent
        if last.isEmpty { return "" }
        if (last as NSString).pathExtension.isEmpty { return last + ".png" }
        return last
    }

    func fileURL(for fileName: String) -> URL {
        imagesDir.appendingPathComponent(sanitizedFileName(fileName), isDirectory: false)
    }

    func ensureDirs() throws {
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: imagesDir.path, isDirectory: &isDir) || !isDir.boolValue {
            try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        }
    }

    func existsFile(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
    }

    func nonEmptyFile(_ url: URL) -> Bool {
        guard existsFile(url),
              let attr = try? fm.attributesOfItem(atPath: url.path),
              let size = attr[.size] as? Int64, size > 0 else { return false }
        return true
    }

    func tempUploadURL(for id: UUID, ext: String) throws -> URL {
        let tmpBase = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("Upload", isDirectory: true)
        try? fm.createDirectory(at: tmpBase, withIntermediateDirectories: true)
        return tmpBase.appendingPathComponent("\(id.uuidString).\(ext)", isDirectory: false)
    }

    func assetForUpload(from source: URL, id: UUID) throws -> CKAsset {
        let ext = (source.path as NSString).pathExtension.isEmpty ? "png" : (source.path as NSString).pathExtension
        let dst = try tempUploadURL(for: id, ext: ext)
        if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
        try fm.copyItem(at: source, to: dst)
        return CKAsset(fileURL: dst)
    }
    
    // MARK: - Cleanup
    
    /// Clean up temporary upload files older than 24 hours
    func cleanupTempUploads() {
        let tmpBase = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("Upload", isDirectory: true)
        guard fm.fileExists(atPath: tmpBase.path) else { return }
        
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60) // 24 hours ago
        guard let files = try? fm.contentsOfDirectory(
            at: tmpBase,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }
        
        for file in files {
            if let attrs = try? fm.attributesOfItem(atPath: file.path),
               let created = attrs[.creationDate] as? Date,
               created < cutoff {
                try? fm.removeItem(at: file)
            }
        }
    }
}

// MARK: - CloudKitSyncManager
@MainActor
final class iCloudSyncManager: ObservableObject {
    @Published var syncStatus: iCloudSyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published private(set) var supportsOrderIndex: Bool = false
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "icloud.sync.enabled")
            if isEnabled { enableCloudSync() } else { disableCloudSync() }
        }
    }

    private lazy var container = CKContainer(identifier: "iCloud.com.daisyyang.mythings.v2")
    private lazy var privateDB = container.privateCloudDatabase
    private var cancellables = Set<AnyCancellable>()
    private let fm = FileManager.default
    private let imageStore = ImageStore()
    
    // Notification observers for cleanup
    private var notificationObservers: [NSObjectProtocol] = []

    private var documentsDir: URL { imageStore.documentsDir }
    private var localItemsURL: URL { documentsDir.appendingPathComponent("items.json") }
    private var localCategoriesURL: URL { documentsDir.appendingPathComponent("categories.json") }
    private var localImagesDir: URL { imageStore.imagesDir }

    private let coordinator = SyncCoordinator()

    private var lastItemSyncDate: Date {
        get { UserDefaults.standard.object(forKey: "icloud.sync.items.lastDate") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "icloud.sync.items.lastDate") }
    }
    private var lastCategorySyncDate: Date {
        get { UserDefaults.standard.object(forKey: "icloud.sync.categories.lastDate") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "icloud.sync.categories.lastDate") }
    }
    private var lastDeletedSyncDate: Date {
        get { UserDefaults.standard.object(forKey: "icloud.sync.deleted.lastDate") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "icloud.sync.deleted.lastDate") }
    }
    private var lastDeletedCategorySyncDate: Date {
        get { UserDefaults.standard.object(forKey: "icloud.sync.deletedCategory.lastDate") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "icloud.sync.deletedCategory.lastDate") }
    }

    private let fullSyncThreshold: TimeInterval = 24 * 60 * 60
    private let maxRetryAttempts: Int = 3
    private let batchSize: Int = 300

    private func normalizeCategoryKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private let clockSkewLeeway: TimeInterval = 5 * 60

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "icloud.sync.enabled")
        self.lastSyncDate = UserDefaults.standard.object(forKey: "icloud.sync.lastDate") as? Date
        self.supportsOrderIndex = UserDefaults.standard.bool(forKey: "icloud.schema.orderIndex")
        if isEnabled { enableCloudSync() }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            await MainActor.run { [weak self] in self?.kickoffIfNeeded() }
        }
        
        // Store observers for cleanup
        let foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled else { return }
                self.kickoffIfNeeded()
            }
        }
        notificationObservers.append(foregroundObserver)
        
        let accountObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.CKAccountChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled else { return }
                self.kickoffIfNeeded()
            }
        }
        notificationObservers.append(accountObserver)
        
        let remoteObserver = NotificationCenter.default.addObserver(
            forName: .iCloudRemoteNotificationReceived, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled else { return }
                print("📲 iCloudSyncManager received remote notification, starting sync")
                self.schedule(.full)
            }
        }
        notificationObservers.append(remoteObserver)
        
        // Clean up old temp files on init
        imageStore.cleanupTempUploads()
    }
    
    deinit {
        // Clean up notification observers
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }

    func schedule(_ event: SyncEvent) {
        guard isEnabled else { return }
        Task { await coordinator.enqueue(event, runners: makeRunners()) }
    }

    func manualSync() { schedule(.full) }

    func kickoffIfNeeded() {
        guard isEnabled else { return }
        if case .syncing = syncStatus { return }
        manualSync()
    }
    
    /// ✅ 批量刪除 items（等待完成）
    /// 用於「刪除所有東西」功能，確保所有刪除都同步到 iCloud 後才返回
    func deleteAllItemsSync(_ itemIDs: [UUID]) async throws {
        guard isEnabled else { return }
        guard !itemIDs.isEmpty else { return }
        
        print("🗑️ Batch deleting \(itemIDs.count) items to iCloud...")
        
        // 使用 TaskGroup 並行處理刪除，但等待全部完成
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in itemIDs {
                group.addTask {
                    try await self.deleteItemOnCloud(id)
                }
            }
            
            // 等待所有刪除完成
            try await group.waitForAll()
        }
        
        print("✅ Batch deletion completed: \(itemIDs.count) items")
    }

    func checkiCloudAvailability() -> Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private func makeRunners() -> SyncCoordinator.Runners {
        .init(
            optimized: { [weak self] in guard let self else { return }; try await self.runOptimizedSync() },
            categoriesOnly: { [weak self] in
                guard let self else { return }
                let timeSinceLastSync = Date().timeIntervalSince(self.lastSyncDate ?? .distantPast)
                if timeSinceLastSync > self.fullSyncThreshold || self.lastSyncDate == nil {
                    try await self.runFullSync()
                } else {
                    try await self.runCategoriesOnlySync()
                }
            },
            full: { [weak self] in guard let self else { return }; try await self.runFullSync() },
            deleteItem: { [weak self] id in guard let self else { return }; try await self.deleteItemOnCloud(id) },
            deleteCategory: { [weak self] id in guard let self else { return }; try await self.deleteCategoryOnCloud(id) },
            setStatus: { [weak self] status in
                await MainActor.run { self?.syncStatus = status }
                if case .success = status { await MainActor.run { self?.updateLastSyncDate() } }
            }
        )
    }

    private func mapErrorToFriendlyMessage(_ error: Error) -> String {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .notAuthenticated: return SyncError.authenticationFailed.localizedDescription
            case .networkUnavailable, .networkFailure: return SyncError.networkError(underlying: error).localizedDescription
            case .quotaExceeded: return SyncError.quotaExceeded.localizedDescription
            case .serviceUnavailable, .requestRateLimited: return "iCloud 服務暫時不可用，請稍後再試"
            default: return ckError.localizedDescription
            }
        }
        return error.localizedDescription
    }

    // MARK: - Enable / Disable
    private func enableCloudSync() {
        container.accountStatus { [weak self] status, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error = error { self.syncStatus = .error(self.mapErrorToFriendlyMessage(error)); return }
                if status == .available {
                    Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        await self?.detectOrderIndexSupport()
                        await self?.ensureCloudKitSubscriptions()
                        await MainActor.run { [weak self] in self?.kickoffIfNeeded() }
                    }
                }
            }
        }
    }

    private func ensureCloudKitSubscriptions() async {
        let subscriptionIDs = ["item-changes-sub", "category-changes-sub"]
        do {
            let existingIDs = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[String], Error>) in
                let op = CKFetchSubscriptionsOperation(subscriptionIDs: subscriptionIDs)
                op.qualityOfService = .utility
                var found: [String] = []
                op.perSubscriptionResultBlock = { subID, result in if case .success = result { found.append(subID) } }
                op.fetchSubscriptionsResultBlock = { _ in cont.resume(returning: found) }
                privateDB.add(op)
            }
            if !existingIDs.contains("item-changes-sub") {
                let sub = CKQuerySubscription(recordType: "Item", predicate: NSPredicate(value: true), subscriptionID: "item-changes-sub", options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion])
                let note = CKSubscription.NotificationInfo(); note.shouldSendContentAvailable = true; sub.notificationInfo = note
                _ = try await dbSave(sub); print("✅ Created Item CloudKit subscription")
            }
            if !existingIDs.contains("category-changes-sub") {
                let sub = CKQuerySubscription(recordType: "Category", predicate: NSPredicate(value: true), subscriptionID: "category-changes-sub", options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion])
                let note = CKSubscription.NotificationInfo(); note.shouldSendContentAvailable = true; sub.notificationInfo = note
                _ = try await dbSave(sub); print("✅ Created Category CloudKit subscription")
            }
        } catch { print("⚠️ CloudKit subscription setup failed (non-fatal): \(error)") }
    }

    private func dbSave(_ subscription: CKSubscription) async throws -> CKSubscription {
        try await withCheckedThrowingContinuation { cont in
            privateDB.save(subscription) { saved, error in
                if let error { cont.resume(throwing: error) }
                else if let saved { cont.resume(returning: saved) }
                else { cont.resume(throwing: CKError(.internalError)) }
            }
        }
    }

    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        guard notification?.notificationID != nil else { return }
        kickoffIfNeeded()
    }

    private func detectOrderIndexSupport() async {
        do {
            let q = CKQuery(recordType: "Category", predicate: NSPredicate(value: true))
            q.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true)]
            _ = try await performQuery(query: q, cursor: nil)
            await MainActor.run { self.supportsOrderIndex = true; UserDefaults.standard.set(true, forKey: "icloud.schema.orderIndex") }
        } catch {
            await MainActor.run { self.supportsOrderIndex = false; UserDefaults.standard.set(false, forKey: "icloud.schema.orderIndex") }
        }
    }

    private func disableCloudSync() { 
        cancellables.removeAll()
        
        // Clean up notification observers
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
        
        syncStatus = .idle
    }

    // MARK: - Local IO
    private func loadLocalItems() -> [Item] {
        guard fm.fileExists(atPath: localItemsURL.path),
              let data = try? Data(contentsOf: localItemsURL),
              let items = try? JSONDecoder().decode([Item].self, from: data) else { return [] }
        return items
    }

    private func saveLocalItems(_ items: [Item]) {
        do {
            try saveAtomically(items, to: localItemsURL)
        } catch {
            print("❌ Save items.json failed: \(error)")
        }
    }

    private func loadLocalCategories() -> [Category] {
        guard fm.fileExists(atPath: localCategoriesURL.path),
              let data = try? Data(contentsOf: localCategoriesURL),
              let cats = try? JSONDecoder().decode([Category].self, from: data) else { return [] }
        return cats
    }

    private func saveLocalCategories(_ cats: [Category]) {
        do {
            try saveAtomically(cats, to: localCategoriesURL)
        } catch {
            print("❌ Save categories.json failed: \(error)")
        }
    }
    
    // MARK: - Atomic File Operations
    
    /// Atomically save data with backup, preventing data loss if write fails
    private func saveAtomically<T: Encodable>(_ value: T, to url: URL) throws {
        let tempURL = url.appendingPathExtension("tmp")
        let backupURL = url.appendingPathExtension("bak")
        
        // Encode and write to temp file
        let data = try JSONEncoder().encode(value)
        try data.write(to: tempURL, options: .atomic)
        
        // If original exists, move it to backup
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: backupURL)
            try? fm.moveItem(at: url, to: backupURL)
        }
        
        // Move temp to final location
        try fm.moveItem(at: tempURL, to: url)
        
        // Clean up backup on success
        try? fm.removeItem(at: backupURL)
    }

    // MARK: - Category 名稱 ↔ UUID 對照
    // CloudKit 雲端 CKRecord 存 category 名稱字串（雲端格式不變）
    // 本機 Item 存 categoryID（UUID）
    // 這兩個 helper 從本機 categories.json 建立對照表，不依賴 @MainActor 的 CategoryStore

    private func categoryNameToIDMap() -> [String: UUID] {
        var map: [String: UUID] = [:]
        let categories = loadLocalCategories()
        
        for cat in categories {
            let key = normalizeCategoryKey(cat.name)
            if let existingID = map[key] {
                print("⚠️ Duplicate category name detected: '\(cat.name)' (normalized: '\(key)')")
                print("   Existing ID: \(existingID), New ID: \(cat.id)")
                // Keep the first one found, but log the conflict
            } else {
                map[key] = cat.id
            }
        }
        
        if !map.isEmpty {
            print("📂 Category name→ID map built with \(map.count) categories:")
            for (name, id) in map.sorted(by: { $0.key < $1.key }) {
                print("   '\(name)' → \(id)")
            }
        } else {
            print("⚠️ Category name→ID map is EMPTY! Items will get nil UUID.")
        }
        
        return map
    }

    private func categoryIDToNameMap() -> [UUID: String] {
        var map: [UUID: String] = [:]
        for cat in loadLocalCategories() { map[cat.id] = cat.name }
        return map
    }

    /// categoryID → 名稱字串（push 到 CloudKit 時用）
    private func categoryName(for id: UUID) -> String {
        categoryIDToNameMap()[id] ?? ""
    }

    /// 名稱字串 → categoryID（從 CloudKit pull 回來時用）
    /// 若找不到對應，用 nilUUID 佔位，App 啟動時的 migration 會補上
    private func categoryID(for name: String) -> UUID {
        let key = normalizeCategoryKey(name)
        return categoryNameToIDMap()[key] ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    }

    // MARK: - 混合同步策略
    private func runOptimizedSync() async throws {
        let timeSinceLastSync = Date().timeIntervalSince(lastSyncDate ?? .distantPast)
        if timeSinceLastSync > fullSyncThreshold || lastSyncDate == nil {
            try await runFullSync()
        } else {
            do { try await runIncrementalSync() }
            catch { print("Incremental sync failed, falling back to full sync: \(error)"); try await runFullSync() }
        }
    }

    private func runIncrementalSync() async throws {
        try Task.checkCancellation()
        try ensureLocalFolders()
        try await pullDeletedItemsSince(lastDeletedSyncDate)
        try await pullDeletedCategoriesSince(lastDeletedCategorySyncDate)
        try await pushLocalChanges()
        try await pullRemoteChanges()
    }

    private func runCategoriesOnlySync() async throws {
        try Task.checkCancellation()
        try ensureLocalFolders()
        try await pushCategoriesOnly()
        try await pullCategoriesSince(lastCategorySyncDate)
    }

    private func pushLocalChanges() async throws {
        let items = loadLocalItems()
        let categories = loadLocalCategories()
        
        // ✅ Push categories first to ensure they exist before items reference them
        let timeSinceCatSync = Date().timeIntervalSince(lastCategorySyncDate)
        let catWatermark = lastCategorySyncDate.addingTimeInterval(-clockSkewLeeway)
        if timeSinceCatSync > clockSkewLeeway || catWatermark == .distantPast.addingTimeInterval(-clockSkewLeeway) {
            if !categories.isEmpty { try await pushCategoriesWithRetry(categories) }
        }
        
        // Then push items
        let watermark = lastItemSyncDate.addingTimeInterval(-clockSkewLeeway)
        let recentItems = items.filter { $0.updatedAt > watermark }
        if !recentItems.isEmpty { try await pushItemsWithRetry(recentItems) }
    }

    private func pushCategoriesOnly() async throws {
        let categories = loadLocalCategories()
        guard !categories.isEmpty else { return }
        try await pushCategoriesWithRetry(categories)
    }

    private func pullRemoteChanges() async throws {
        // ✅ CRITICAL FIX: Pull categories BEFORE items
        // This ensures categoryNameToIDMap() has all categories when processing items
        try await pullCategoriesSince(lastCategorySyncDate)
        try await pullItemsSince(lastItemSyncDate)
    }

    private func pullItemsSince(_ since: Date) async throws {
        let sinceWithLeeway = since.addingTimeInterval(-clockSkewLeeway)
        let predicate = NSPredicate(format: "updatedAt > %@", sinceWithLeeway as CVarArg)
        let query = CKQuery(recordType: "Item", predicate: predicate)
        if supportsOrderIndex {
            query.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true), NSSortDescriptor(key: "updatedAt", ascending: false)]
        } else {
            query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        }
        var allChanges: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        repeat { let page = try await performQuery(query: query, cursor: cursor); allChanges.append(contentsOf: page.records); cursor = page.cursor } while cursor != nil
        guard !allChanges.isEmpty else { return }
        try await mergeItemChanges(allChanges)
    }

    private func pullCategoriesSince(_ since: Date) async throws {
        let sinceWithLeeway = since.addingTimeInterval(-clockSkewLeeway)
        let predicate = NSPredicate(format: "updatedAt > %@", sinceWithLeeway as CVarArg)
        let query = CKQuery(recordType: "Category", predicate: predicate)
        if supportsOrderIndex {
            query.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true), NSSortDescriptor(key: "updatedAt", ascending: false)]
        } else {
            query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        }
        var allChanges: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        repeat { let page = try await performQuery(query: query, cursor: cursor); allChanges.append(contentsOf: page.records); cursor = page.cursor } while cursor != nil
        guard !allChanges.isEmpty else { return }
        try await mergeCategoryChanges(allChanges)
    }

    private func mergeItemChanges(_ changes: [CKRecord]) async throws {
        var local = loadLocalItems()
        var maxCloudUpdatedAt: Date = lastItemSyncDate
        // ✅ 建立一次 name→UUID 對照表，避免每筆重複 IO
        let nameToID = categoryNameToIDMap()

        for record in changes {
            guard
                let idStr = record["id"] as? String,
                let uuid = UUID(uuidString: idStr),
                let brand = record["brand"] as? String,
                let categoryName = record["category"] as? String,
                let name = record["name"] as? String,
                let price = record["price"] as? String
            else { continue }

            let date = record["date"] as? Date
            let cloudUpdatedAt = record["updatedAt"] as? Date ?? .distantPast
            let cloudCreatedAt = record["createdAt"] as? Date
            if cloudUpdatedAt > maxCloudUpdatedAt { maxCloudUpdatedAt = cloudUpdatedAt }

            // ✅ 名稱 → UUID（使用 normalized key）
            let normalizedKey = normalizeCategoryKey(categoryName)
            let resolvedCategoryID = nameToID[normalizedKey] ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            
            // ✅ Log when category is not found during incremental sync
            if resolvedCategoryID == UUID(uuidString: "00000000-0000-0000-0000-000000000000")! {
                print("⚠️ [Incremental Sync] Category '\(categoryName)' (normalized: '\(normalizedKey)') not found in local categories for item '\(name)'")
                print("   Item will show as 'Unknown' until categories are synced")
            }

            var finalImageName = ""
            if let asset = record["image"] as? CKAsset, let cloudURL = asset.fileURL {
                finalImageName = "\(uuid.uuidString).png"
                let target = imageStore.fileURL(for: finalImageName)
                do {
                    try imageStore.ensureDirs()
                    if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }
                    try fm.copyItem(at: cloudURL, to: target)
                    ImageMemoryCache.shared.remove(finalImageName)
                } catch { print("❌ Copy image failed: \(error)"); finalImageName = "" }
            }

            if let index = local.firstIndex(where: { $0.id == uuid }) {
                let localItem = local[index]
                let localUpdatedAt = localItem.updatedAt
                
                // ✅ CRITICAL FIX: Only merge if cloud version is newer or equal
                // This prevents iCloud from overwriting recent local edits
                if cloudUpdatedAt >= localUpdatedAt {
                    let chosenImageName = finalImageName.isEmpty ? local[index].imageName : finalImageName
                    let localCreated = local[index].createdAt
                    let finalCreated = cloudCreatedAt ?? localCreated
                    // ✅ 使用 categoryID: UUID 取代 category: String
                    let merged = Item(
                        id: uuid,
                        imageName: chosenImageName,
                        brand: brand,
                        categoryID: resolvedCategoryID,
                        name: name,
                        price: price,
                        date: date,
                        createdAt: finalCreated,
                        updatedAt: cloudUpdatedAt
                    )
                    local[index] = merged
                    print("✅ [Merge] Updated item '\(name)' from cloud (cloud: \(cloudUpdatedAt), local: \(localUpdatedAt))")
                } else {
                    // Local version is newer, keep it and log
                    print("⏭️ [Merge] Skipped item '\(name)' - local version is newer (cloud: \(cloudUpdatedAt), local: \(localUpdatedAt))")
                    print("   Local category: \(localItem.categoryID), Cloud category: \(resolvedCategoryID)")
                }
            } else {
                let fallbackCreated: Date = {
                    if let c = cloudCreatedAt { return c }
                    if cloudUpdatedAt != .distantPast { return cloudUpdatedAt }
                    return date ?? .distantPast
                }()
                // ✅ 使用 categoryID: UUID 取代 category: String
                let newItem = Item(
                    id: uuid,
                    imageName: finalImageName,
                    brand: brand,
                    categoryID: resolvedCategoryID,
                    name: name,
                    price: price,
                    date: date,
                    createdAt: fallbackCreated,
                    updatedAt: cloudUpdatedAt
                )
                local.append(newItem)
            }
        }

        local.sort { $0.createdAt > $1.createdAt }
        saveLocalItems(local)
        if maxCloudUpdatedAt > lastItemSyncDate { lastItemSyncDate = maxCloudUpdatedAt }
    }

    private func mergeCategoryChanges(_ changes: [CKRecord]) async throws {
        var local = loadLocalCategories()
        var maxCloudUpdatedAt: Date = lastCategorySyncDate
        var idToOrderIndex: [UUID: Int] = [:]

        for record in changes {
            guard let idStr = record["id"] as? String, let uuid = UUID(uuidString: idStr), let name = record["name"] as? String else { continue }
            let emoji = (record["emoji"] as? String) ?? ""
            let cloudUpdatedAt = record["updatedAt"] as? Date ?? .distantPast
            if cloudUpdatedAt > maxCloudUpdatedAt { maxCloudUpdatedAt = cloudUpdatedAt }
            if let ord = (record["orderIndex"] as? NSNumber)?.intValue { idToOrderIndex[uuid] = ord }
            let updatedCategory = Category(id: uuid, name: name, emoji: emoji)
            if let index = local.firstIndex(where: { $0.id == uuid }) {
                local[index] = updatedCategory
            } else if !local.contains(where: { normalizeCategoryKey($0.name) == normalizeCategoryKey(name) }) {
                local.append(updatedCategory)
            }
        }

        // ✅ IMPROVED: Always sort if we have ANY orderIndex data
        // This ensures consistent ordering across devices
        if !idToOrderIndex.isEmpty {
            local.sort { a, b in
                let ia = idToOrderIndex[a.id] ?? Int.max
                let ib = idToOrderIndex[b.id] ?? Int.max
                if ia != ib { return ia < ib }
                // If both don't have orderIndex, preserve relative order
                // by comparing names for consistency
                if ia == Int.max && ib == Int.max {
                    return a.name.lowercased() < b.name.lowercased()
                }
                return ia < ib
            }
        }

        saveLocalCategories(local)
        if maxCloudUpdatedAt > lastCategorySyncDate { lastCategorySyncDate = maxCloudUpdatedAt }
    }

    // MARK: - 完整同步
    private func runFullSync() async throws {
        try Task.checkCancellation()
        try ensureLocalFolders()
        try await pullAllDeletedItems()
        try await pullAllDeletedCategories()
        
        // ✅ NEW: Clean up old name-based category records during full sync
        // This is a one-time migration that will gradually clean up old records
        await cleanupOldNameBasedCategoryRecords()
        
        let items = loadLocalItems()
        let cats = loadLocalCategories()
        // ✅ Push categories before items (order doesn't matter as much for push)
        if !cats.isEmpty { try Task.checkCancellation(); try await pushCategoriesWithRetry(cats) }
        if !items.isEmpty { try Task.checkCancellation(); try await pushItemsWithRetry(items) }
        // ✅ CRITICAL FIX: Pull categories BEFORE items
        // This ensures categoryNameToIDMap() has all categories when processing items
        try Task.checkCancellation(); try await pullCategories()
        try Task.checkCancellation(); try await pullItems()
    }

    // MARK: - Push with retry
    private func pushItemsWithRetry(_ items: [Item]) async throws {
        for (index, item) in items.enumerated() {
            try Task.checkCancellation()
            var attempts = 0
            while attempts < maxRetryAttempts {
                do {
                    let ord = supportsOrderIndex ? index : 0
                    try await pushSingleItem(item, orderIndex: ord)
                    break
                } catch let e as CKError where isRetryableError(e) && attempts < maxRetryAttempts - 1 {
                    attempts += 1
                    let delay = calculateBackoffDelay(attempt: attempts)
                    print("⚠️ Retrying push item (attempt \(attempts)/\(maxRetryAttempts)): \(e.localizedDescription)")
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    throw error
                }
            }
        }
        
        // Clean up temp files after batch upload
        imageStore.cleanupTempUploads()
    }

    private func pushCategoriesWithRetry(_ categories: [Category]) async throws {
        for (index, cat) in categories.enumerated() {
            try Task.checkCancellation()
            var attempts = 0
            while attempts < maxRetryAttempts {
                do {
                    let ord = supportsOrderIndex ? index : 0
                    try await pushSingleCategory(cat, orderIndex: ord)
                    break
                } catch let e as CKError where isRetryableError(e) && attempts < maxRetryAttempts - 1 {
                    attempts += 1
                    let delay = calculateBackoffDelay(attempt: attempts)
                    print("⚠️ Retrying push category (attempt \(attempts)/\(maxRetryAttempts)): \(e.localizedDescription)")
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    throw error
                }
            }
        }
    }
    
    // MARK: - Error Handling Helpers
    
    /// Check if a CloudKit error is retryable
    private func isRetryableError(_ error: CKError) -> Bool {
        switch error.code {
        case .serverRecordChanged,
             .serviceUnavailable,
             .requestRateLimited,
             .zoneBusy,
             .networkFailure,
             .networkUnavailable:
            return true
        default:
            return false
        }
    }
    
    /// Calculate exponential backoff delay with jitter
    private func calculateBackoffDelay(attempt: Int) -> UInt64 {
        let baseDelay: UInt64 = 400_000_000 // 0.4 seconds
        let exponentialDelay = baseDelay * UInt64(1 << attempt)
        let maxDelay: UInt64 = 8_000_000_000 // 8 seconds
        let cappedDelay = min(exponentialDelay, maxDelay)
        
        // Add jitter (±20%)
        let jitterRange = Double(cappedDelay) * 0.2
        let jitter = Double.random(in: -jitterRange...jitterRange)
        return UInt64(max(0, Double(cappedDelay) + jitter))
    }

    // MARK: - Push one item
    private func pushSingleItem(_ item: Item, orderIndex: Int) async throws {
        let rid = CKRecord.ID(recordName: "item-\(item.id.uuidString)")
        let rec = try await fetchOrCreate(recordType: "Item", id: rid)
        rec["id"] = item.id.uuidString as CKRecordValue
        rec["brand"] = item.brand as CKRecordValue
        // ✅ 核心改動：categoryID → 名稱字串再存入 CKRecord（雲端格式不變）
        rec["category"] = categoryName(for: item.categoryID) as CKRecordValue
        rec["name"] = item.name as CKRecordValue
        rec["price"] = item.price as CKRecordValue
        if let d = item.date { rec["date"] = d as CKRecordValue }
        rec["updatedAt"] = item.updatedAt as CKRecordValue
        if rec["createdAt"] == nil { rec["createdAt"] = item.createdAt as CKRecordValue }
        rec["orderIndex"] = NSNumber(value: orderIndex)

        if !item.imageName.isEmpty {
            let fileName = imageStore.sanitizedFileName(item.imageName)
            let imgURL = imageStore.fileURL(for: fileName)
            if imageStore.nonEmptyFile(imgURL) {
                let asset = try imageStore.assetForUpload(from: imgURL, id: item.id)
                rec["image"] = asset
            } else { rec["image"] = nil }
        } else { rec["image"] = nil }

        _ = try await dbSave(rec)
    }

    private func pushSingleCategory(_ category: Category, orderIndex: Int) async throws {
        // ✅ CRITICAL FIX: Use UUID as recordName instead of category name
        // This prevents duplicate categories when renaming (e.g., "Pikmin" → "Coffee")
        // Old behavior: recordName = "category-name-pikmin" → rename → creates "category-name-coffee"
        // New behavior: recordName = "category-uuid-xxx" → rename → updates same record
        let rid = CKRecord.ID(recordName: "category-uuid-\(category.id.uuidString)")
        let rec = try await fetchOrCreate(recordType: "Category", id: rid)
        rec["id"] = category.id.uuidString as CKRecordValue
        rec["name"] = category.name as CKRecordValue
        if !category.emoji.isEmpty { rec["emoji"] = category.emoji as CKRecordValue } else { rec["emoji"] = nil }
        rec["updatedAt"] = Date() as CKRecordValue
        rec["orderIndex"] = NSNumber(value: orderIndex)
        _ = try await dbSave(rec)
        
        // ✅ After successfully saving with UUID-based recordName, clean up old name-based records
        // This ensures old "category-name-xxx" records are removed from CloudKit
        let normalizedKey = normalizeCategoryKey(category.name)
        let oldNameBasedRecordID = CKRecord.ID(recordName: "category-name-\(normalizedKey)")
        
        // Check if old record exists and delete it
        do {
            let oldRecord = try await dbFetch(recordID: oldNameBasedRecordID)
            // Only delete if it has the same category ID (to avoid deleting unrelated records)
            if let oldRecordID = oldRecord["id"] as? String, oldRecordID == category.id.uuidString {
                try await privateDB.deleteRecord(withID: oldNameBasedRecordID)
                print("🧹 Cleaned up old name-based category record: \(oldNameBasedRecordID.recordName)")
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Old record doesn't exist, which is fine
            print("✅ No old name-based record to clean up for category: \(category.name)")
        } catch {
            // Other errors during cleanup should not fail the whole sync
            print("⚠️ Failed to clean up old category record: \(error.localizedDescription)")
        }
    }

    // MARK: - Pull 全量
    private func pullItems() async throws {
        let query = CKQuery(recordType: "Item", predicate: NSPredicate(value: true))
        if supportsOrderIndex {
            query.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true), NSSortDescriptor(key: "updatedAt", ascending: false)]
        } else {
            query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        }
        var all: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        repeat { let page = try await performQuery(query: query, cursor: cursor); all.append(contentsOf: page.records); cursor = page.cursor } while cursor != nil

        var local = loadLocalItems()
        var maxCloudUpdatedAt: Date = lastItemSyncDate
        // ✅ 建立一次 name→UUID 對照表
        let nameToID = categoryNameToIDMap()

        for r in all {
            guard
                let idStr = r["id"] as? String, let uuid = UUID(uuidString: idStr),
                let brand = r["brand"] as? String,
                let categoryName = r["category"] as? String,
                let name = r["name"] as? String,
                let price = r["price"] as? String
            else { continue }

            let date = r["date"] as? Date
            let cloudUpdatedAt = r["updatedAt"] as? Date ?? .distantPast
            let cloudCreatedAt = r["createdAt"] as? Date
            if cloudUpdatedAt > maxCloudUpdatedAt { maxCloudUpdatedAt = cloudUpdatedAt }

            // ✅ 名稱 → UUID（使用 normalized key）
            let normalizedKey = normalizeCategoryKey(categoryName)
            let resolvedCategoryID = nameToID[normalizedKey] ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            
            // ✅ Log when category is not found during full sync
            if resolvedCategoryID == UUID(uuidString: "00000000-0000-0000-0000-000000000000")! {
                print("⚠️ [Full Sync] Category '\(categoryName)' (normalized: '\(normalizedKey)') not found in local categories for item '\(name)'")
                print("   Item will show as 'Unknown' until categories are synced")
            }

            var finalImageName = ""
            if let asset = r["image"] as? CKAsset, let cloudURL = asset.fileURL {
                finalImageName = "\(uuid.uuidString).png"
                let target = imageStore.fileURL(for: finalImageName)
                do {
                    try imageStore.ensureDirs()
                    if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }
                    try fm.copyItem(at: cloudURL, to: target)
                    ImageMemoryCache.shared.remove(finalImageName)
                } catch { print("❌ Copy image failed: \(error)"); finalImageName = "" }
            }

            if let idxLocal = local.firstIndex(where: { $0.id == uuid }) {
                let chosenImageName = finalImageName.isEmpty ? local[idxLocal].imageName : finalImageName
                let localCreated = local[idxLocal].createdAt
                let finalCreated = cloudCreatedAt ?? localCreated
                // ✅ 使用 categoryID: UUID
                let merged = Item(
                    id: uuid, imageName: chosenImageName, brand: brand,
                    categoryID: resolvedCategoryID,
                    name: name, price: price, date: date,
                    createdAt: finalCreated, updatedAt: cloudUpdatedAt
                )
                local[idxLocal] = merged
            } else {
                let fallbackCreated: Date = {
                    if let c = cloudCreatedAt { return c }
                    if cloudUpdatedAt != .distantPast { return cloudUpdatedAt }
                    return date ?? .distantPast
                }()
                // ✅ 使用 categoryID: UUID
                let newItem = Item(
                    id: uuid, imageName: finalImageName, brand: brand,
                    categoryID: resolvedCategoryID,
                    name: name, price: price, date: date,
                    createdAt: fallbackCreated, updatedAt: cloudUpdatedAt
                )
                local.append(newItem)
            }
        }

        local.sort { $0.createdAt > $1.createdAt }
        saveLocalItems(local)
        if maxCloudUpdatedAt > lastItemSyncDate { lastItemSyncDate = maxCloudUpdatedAt }
    }

    private func pullCategories() async throws {
        // ✅ First, check for deleted categories and remove them from local
        try await pullAllDeletedCategories()
        
        let query = CKQuery(recordType: "Category", predicate: NSPredicate(value: true))
        if supportsOrderIndex {
            query.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true), NSSortDescriptor(key: "updatedAt", ascending: false)]
        } else {
            query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        }
        var all: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        repeat { let page = try await performQuery(query: query, cursor: cursor); all.append(contentsOf: page.records); cursor = page.cursor } while cursor != nil

        let local = loadLocalCategories()
        var maxCloudUpdatedAt: Date = lastCategorySyncDate
        
        // ✅ CRITICAL FIX: Deduplicate by UUID instead of name to handle renames correctly
        // When a category is renamed (e.g., "Pikmin" → "Coffee"), both old and new records
        // may exist in CloudKit temporarily. We need to keep only the latest version by UUID.
        // Store: (Category, updatedAt, recordID, orderIndex, originalIndex)
        var cloudCategories: [(Category, Date?, CKRecord.ID, Int?, Int)] = []
        var seenUUIDs = Set<UUID>()

        for (index, r) in all.enumerated() {
            guard let idStr = r["id"] as? String, let uuid = UUID(uuidString: idStr), let name = r["name"] as? String else { continue }
            let emoji = (r["emoji"] as? String) ?? ""
            let updatedAt = r["updatedAt"] as? Date
            if let upd = updatedAt, upd > maxCloudUpdatedAt { maxCloudUpdatedAt = upd }
            let ord = supportsOrderIndex ? (r["orderIndex"] as? NSNumber)?.intValue : nil
            let candidate = Category(id: uuid, name: name, emoji: emoji)
            
            // ✅ CRITICAL FIX: Deduplicate by UUID instead of name
            // This ensures that when a category is renamed, we keep the latest version
            // Old logic: Deduplicated by name → "Pikmin" and "Coffee" treated as different
            // New logic: Deduplicate by UUID → Same category, keep latest updatedAt
            if let existingIndex = cloudCategories.firstIndex(where: { $0.0.id == uuid }) {
                let existingDate = cloudCategories[existingIndex].1 ?? .distantPast
                let newDate = updatedAt ?? .distantPast
                if newDate >= existingDate {
                    print("🔄 [Category Dedup] Updating category '\(name)' (UUID: \(uuid)) - newer version found (old: \(existingDate), new: \(newDate))")
                    cloudCategories[existingIndex] = (candidate, updatedAt, r.recordID, ord, index)
                } else {
                    print("⏭️ [Category Dedup] Skipping older version of category '\(name)' (UUID: \(uuid))")
                }
            } else {
                cloudCategories.append((candidate, updatedAt, r.recordID, ord, index))
                seenUUIDs.insert(uuid)
            }
        }

        try await cleanupDuplicateCategoryRecords(allRecords: all, keepKeys: Set(cloudCategories.map { $0.2 }))

        // ✅ Sort by orderIndex (if available), then by original CloudKit order
        cloudCategories.sort { a, b in
            // If both have orderIndex, use it
            if let ia = a.3, let ib = b.3 {
                return ia < ib
            }
            // If only one has orderIndex, it goes first
            if a.3 != nil { return true }
            if b.3 != nil { return false }
            // Otherwise preserve CloudKit query order (which respects sortDescriptors)
            return a.4 < b.4
        }
        
        var merged: [Category] = []
        var usedIds = Set<UUID>()
        for value in cloudCategories {
            merged.append(value.0)
            usedIds.insert(value.0.id)
        }
        
        // ✅ FIX: On first sync (fresh device), REPLACE local categories with cloud categories
        // Only keep local categories if this is an established device with its own categories
        let isFirstSync = lastCategorySyncDate == .distantPast
        
        if !isFirstSync {
            // Normal operation: Keep local categories that don't exist in cloud (by UUID)
            for lc in local {
                // ✅ Check by UUID instead of name to handle renames correctly
                if !usedIds.contains(lc.id) {
                    merged.append(lc)
                    usedIds.insert(lc.id)
                }
            }
        } else {
            // First sync: Only use cloud categories, ignore default local categories
            // This prevents duplicate categories when syncing to a new device
            print("🔄 First category sync: Using cloud categories only (\(merged.count) categories)")
        }
        
        saveLocalCategories(merged)
        if maxCloudUpdatedAt > lastCategorySyncDate { lastCategorySyncDate = maxCloudUpdatedAt }
        
        // ✅ Notify CategoryStore to reload
        await MainActor.run {
            NotificationCenter.default.post(name: Notification.Name.iCloudCategoriesSynced, object: nil)
        }
    }

    private func cleanupDuplicateCategoryRecords(allRecords: [CKRecord], keepKeys: Set<CKRecord.ID>) async throws {
        var toDelete: [CKRecord.ID] = []
        for r in allRecords {
            let id = r.recordID
            if !keepKeys.contains(id) && id.recordName.hasPrefix("category-") && !id.recordName.hasPrefix("category-name-") {
                toDelete.append(id)
            }
        }
        if !toDelete.isEmpty { try await deleteRecordsInBatches(ids: Array(Set(toDelete))) }
    }

    private func cleanupAndDeleteRemoteCategories(notInLocal localNameKeys: Set<String>) async throws {
        let query = CKQuery(recordType: "Category", predicate: NSPredicate(value: true))
        var all: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        repeat { let page = try await performQuery(query: query, cursor: cursor); all.append(contentsOf: page.records); cursor = page.cursor } while cursor != nil

        var grouped: [String: [(CKRecord, Date?)]] = [:]
        for r in all {
            guard let name = r["name"] as? String else { continue }
            grouped[normalizeCategoryKey(name), default: []].append((r, r["updatedAt"] as? Date))
        }

        var toDelete: [CKRecord.ID] = []
        for (key, list) in grouped {
            if !localNameKeys.contains(key) { toDelete.append(contentsOf: list.map { $0.0.recordID }); continue }
            let sorted = list.sorted { ($0.1 ?? .distantPast) > ($1.1 ?? .distantPast) }
            let keep = sorted.first?.0.recordID
            for (rec, _) in sorted.dropFirst() { toDelete.append(rec.recordID) }
            for (rec, _) in list {
                let rn = rec.recordID.recordName
                if rn.hasPrefix("category-") && !rn.hasPrefix("category-name-") && rec.recordID != keep { toDelete.append(rec.recordID) }
            }
        }
        if !toDelete.isEmpty { try await deleteRecordsInBatches(ids: Array(Set(toDelete))) }
    }

    // MARK: - Public maintenance
    func countAllRecords() async -> (items: Int, categories: Int) { (await countItemRecords(), await countCategoryRecords()) }
    func countItemRecords() async -> Int { await countRecords(of: "Item") }
    func countCategoryRecords() async -> Int { await countRecords(of: "Category") }

    func purgeAllItemsCloud() async {
        do {
            let ids = try await fetchAllRecordIDs(of: "Item")
            guard !ids.isEmpty else { print("ℹ️ No Item records to purge."); return }
            try await deleteRecordsInBatches(ids: ids)
            print("✅ Purged all Item records from iCloud: \(ids.count)")
        } catch { print("❌ Purge items from iCloud failed: \(error)") }
    }

    func purgeAllCloud() async { await purgeAllItemsCloud(); await purgeAllCategoriesCloud() }

    func wipeLocalStore() {
        try? fm.removeItem(at: localItemsURL)
        try? fm.removeItem(at: localCategoriesURL)
        if let files = try? fm.contentsOfDirectory(at: localImagesDir, includingPropertiesForKeys: nil) {
            for url in files { try? fm.removeItem(at: url) }
        }
        lastSyncDate = nil
        UserDefaults.standard.removeObject(forKey: "icloud.sync.lastDate")
        lastItemSyncDate = .distantPast
        lastCategorySyncDate = .distantPast
        lastDeletedSyncDate = .distantPast
        lastDeletedCategorySyncDate = .distantPast
        NotificationCenter.default.post(name: .iCloudLocalStoreWiped, object: nil)
        print("🧹 Wiped local store and reset sync timestamps.")
    }

    private func countRecords(of recordType: String) async -> Int {
        do {
            var total = 0
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            var cursor: CKQueryOperation.Cursor?
            repeat { let page = try await performQuery(query: query, cursor: cursor); total += page.records.count; cursor = page.cursor } while cursor != nil
            return total
        } catch { print("❌ countRecords(\(recordType)) failed: \(error)"); return 0 }
    }

    private func fetchAllRecordIDs(of recordType: String) async throws -> [CKRecord.ID] {
        var ids: [CKRecord.ID] = []
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        var cursor: CKQueryOperation.Cursor?
        repeat { let page = try await performQuery(query: query, cursor: cursor); ids.append(contentsOf: page.records.map { $0.recordID }); cursor = page.cursor } while cursor != nil
        return Array(Set(ids))
    }

    func purgeAllCategoriesCloud() async {
        do {
            let query = CKQuery(recordType: "Category", predicate: NSPredicate(value: true))
            var all: [CKRecord] = []
            var cursor: CKQueryOperation.Cursor?
            repeat { let page = try await performQuery(query: query, cursor: cursor); all.append(contentsOf: page.records); cursor = page.cursor } while cursor != nil
            let ids = all.map { $0.recordID }
            try await deleteRecordsInBatches(ids: ids)
            print("✅ Purged all Category records from iCloud: \(ids.count)")
        } catch { print("❌ Purge categories from iCloud failed: \(error)") }
    }
    
    /// ✅ NEW: Clean up old name-based category records after migration to UUID-based records
    /// This function finds all old "category-name-xxx" records and deletes them if a corresponding
    /// "category-uuid-xxx" record exists for the same category ID.
    /// Call this during initial sync or as a maintenance operation.
    func cleanupOldNameBasedCategoryRecords() async {
        do {
            print("🧹 Starting cleanup of old name-based category records...")
            
            let query = CKQuery(recordType: "Category", predicate: NSPredicate(value: true))
            var all: [CKRecord] = []
            var cursor: CKQueryOperation.Cursor?
            repeat { 
                let page = try await performQuery(query: query, cursor: cursor)
                all.append(contentsOf: page.records)
                cursor = page.cursor
            } while cursor != nil
            
            // Separate records into UUID-based and name-based
            var uuidBasedRecords: [String: CKRecord] = [:] // categoryID -> record
            var nameBasedRecords: [CKRecord] = []
            
            for record in all {
                let recordName = record.recordID.recordName
                if recordName.hasPrefix("category-uuid-") {
                    // UUID-based record (new format)
                    if let categoryID = record["id"] as? String {
                        uuidBasedRecords[categoryID] = record
                    }
                } else if recordName.hasPrefix("category-name-") {
                    // Name-based record (old format)
                    nameBasedRecords.append(record)
                }
            }
            
            // Find name-based records that have corresponding UUID-based records
            var recordsToDelete: [CKRecord.ID] = []
            for oldRecord in nameBasedRecords {
                if let categoryID = oldRecord["id"] as? String {
                    // Check if UUID-based record exists for this category
                    if uuidBasedRecords[categoryID] != nil {
                        recordsToDelete.append(oldRecord.recordID)
                        let name = (oldRecord["name"] as? String) ?? "unknown"
                        print("   📍 Found old record to delete: \(oldRecord.recordID.recordName) (category: \(name), ID: \(categoryID))")
                    }
                }
            }
            
            // Delete old records in batches
            if !recordsToDelete.isEmpty {
                try await deleteRecordsInBatches(ids: recordsToDelete)
                print("✅ Cleaned up \(recordsToDelete.count) old name-based category records")
            } else {
                print("✅ No old name-based category records to clean up")
            }
        } catch {
            print("❌ Failed to clean up old category records: \(error)")
        }
    }

    // MARK: - Delete（協調器呼叫）
    private func deleteItemOnCloud(_ itemId: UUID) async throws {
        do {
            let did = CKRecord.ID(recordName: "deleted-\(itemId.uuidString)")
            let tomb = try await fetchOrCreate(recordType: "DeletedItem", id: did)
            tomb["id"] = itemId.uuidString as CKRecordValue
            tomb["updatedAt"] = Date() as CKRecordValue
            _ = try await dbSave(tomb)
            print("🪦 Upserted DeletedItem tombstone for id=\(itemId)")
        } catch { print("❗️Failed to upsert DeletedItem tombstone: \(error)") }

        let rid = CKRecord.ID(recordName: "item-\(itemId.uuidString)")
        do {
            try await privateDB.deleteRecord(withID: rid)
            print("✅ Deleted item from iCloud by recordID: \(itemId)")
        } catch let ck as CKError { if ck.code != .unknownItem { throw ck } } catch { throw error }

        let predicate = NSPredicate(format: "id == %@", itemId.uuidString)
        let query = CKQuery(recordType: "Item", predicate: predicate)
        var idsToDelete: [CKRecord.ID] = []
        var cursor: CKQueryOperation.Cursor?
        repeat { let page = try await performQuery(query: query, cursor: cursor); idsToDelete.append(contentsOf: page.records.map { $0.recordID }); cursor = page.cursor } while cursor != nil
        if !idsToDelete.isEmpty { try await deleteRecordsInBatches(ids: Array(Set(idsToDelete))); print("✅ Deleted \(idsToDelete.count) legacy Item record(s) for id=\(itemId)") }
    }

    private func deleteCategoryOnCloud(_ categoryId: UUID) async throws {
        do {
            let did = CKRecord.ID(recordName: "deleted-category-\(categoryId.uuidString)")
            let tomb = try await fetchOrCreate(recordType: "DeletedCategory", id: did)
            tomb["id"] = categoryId.uuidString as CKRecordValue
            tomb["updatedAt"] = Date() as CKRecordValue
            _ = try await dbSave(tomb)
            print("🪦 Upserted DeletedCategory tombstone for id=\(categoryId)")
        } catch { print("❗️Failed to upsert DeletedCategory tombstone: \(error)") }

        let predicate = NSPredicate(format: "id == %@", categoryId.uuidString)
        let query = CKQuery(recordType: "Category", predicate: predicate)
        var idsToDelete: [CKRecord.ID] = []
        var cursor: CKQueryOperation.Cursor?
        repeat { let page = try await performQuery(query: query, cursor: cursor); idsToDelete.append(contentsOf: page.records.map { $0.recordID }); cursor = page.cursor } while cursor != nil
        if !idsToDelete.isEmpty { try await deleteRecordsInBatches(ids: Array(Set(idsToDelete))); print("✅ Deleted \(idsToDelete.count) Category record(s) for id=\(categoryId)") }
    }

    // MARK: - DeletedItem tombstone
    private func pullDeletedItemsSince(_ since: Date) async throws {
        let predicate = NSPredicate(format: "updatedAt > %@", since as CVarArg)
        let query = CKQuery(recordType: "DeletedItem", predicate: predicate)
        var deletedIDs: [UUID] = []
        var cursor: CKQueryOperation.Cursor?
        repeat { let page = try await performQuery(query: query, cursor: cursor); for rec in page.records { if let idStr = rec["id"] as? String, let uuid = UUID(uuidString: idStr) { deletedIDs.append(uuid) } }; cursor = page.cursor } while cursor != nil
        guard !deletedIDs.isEmpty else { return }
        try await removeLocalItems(withIDs: Set(deletedIDs))
        lastDeletedSyncDate = Date()
    }

    private func removeLocalItems(withIDs ids: Set<UUID>) async throws {
        var local = loadLocalItems()
        let before = local.count
        local.removeAll { ids.contains($0.id) }
        if local.count != before {
            saveLocalItems(local)
            print("🧹 Removed \(before - local.count) local item(s) by DeletedItem tombstones.")
            
            // ✅ Notify to refresh UI if needed
            await MainActor.run {
                NotificationCenter.default.post(name: .iCloudLocalStoreWiped, object: nil)
            }
        }
    }

    private func pullAllDeletedItems() async throws {
        let query = CKQuery(recordType: "DeletedItem", predicate: NSPredicate(value: true))
        var deletedIDs: [UUID] = []
        var cursor: CKQueryOperation.Cursor?
        repeat { let page = try await performQuery(query: query, cursor: cursor); for rec in page.records { if let idStr = rec["id"] as? String, let uuid = UUID(uuidString: idStr) { deletedIDs.append(uuid) } }; cursor = page.cursor } while cursor != nil
        guard !deletedIDs.isEmpty else { return }
        try await removeLocalItems(withIDs: Set(deletedIDs))
        lastDeletedSyncDate = Date()
    }

    // MARK: - DeletedCategory tombstone
    private func pullDeletedCategoriesSince(_ since: Date) async throws {
        let predicate = NSPredicate(format: "updatedAt > %@", since as CVarArg)
        let query = CKQuery(recordType: "DeletedCategory", predicate: predicate)
        var deletedIDs: [UUID] = []
        var cursor: CKQueryOperation.Cursor?
        repeat { let page = try await performQuery(query: query, cursor: cursor); for rec in page.records { if let idStr = rec["id"] as? String, let uuid = UUID(uuidString: idStr) { deletedIDs.append(uuid) } }; cursor = page.cursor } while cursor != nil
        guard !deletedIDs.isEmpty else { return }
        try await removeLocalCategories(withIDs: Set(deletedIDs))
        lastDeletedCategorySyncDate = Date()
    }

    private func pullAllDeletedCategories() async throws {
        let query = CKQuery(recordType: "DeletedCategory", predicate: NSPredicate(value: true))
        var deletedIDs: [UUID] = []
        var cursor: CKQueryOperation.Cursor?
        repeat { let page = try await performQuery(query: query, cursor: cursor); for rec in page.records { if let idStr = rec["id"] as? String, let uuid = UUID(uuidString: idStr) { deletedIDs.append(uuid) } }; cursor = page.cursor } while cursor != nil
        guard !deletedIDs.isEmpty else { return }
        try await removeLocalCategories(withIDs: Set(deletedIDs))
        lastDeletedCategorySyncDate = Date()
    }

    private func removeLocalCategories(withIDs ids: Set<UUID>) async throws {
        var local = loadLocalCategories()
        let before = local.count
        local.removeAll { ids.contains($0.id) }
        if local.count != before {
            saveLocalCategories(local)
            print("🧹 Removed \(before - local.count) local category(ies) by DeletedCategory tombstones.")
            
            // ✅ CRITICAL FIX: Notify CategoryStore to reload after removing categories
            // Without this, CategoryStore's in-memory copy is stale and may overwrite the deletion
            await MainActor.run {
                NotificationCenter.default.post(name: .iCloudCategoriesSynced, object: nil)
            }
        }
    }

    // MARK: - CK helpers
    private func deleteRecordsInBatches(ids: [CKRecord.ID], batchSize: Int = 300) async throws {
        guard !ids.isEmpty else { return }
        let unique = Array(Set(ids))
        var index = 0
        while index < unique.count {
            let end = min(index + batchSize, unique.count)
            let slice = Array(unique[index..<end])
            try await withCheckedThrowingContinuation { cont in
                let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: slice)
                op.isAtomic = false; op.qualityOfService = .utility
                op.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success: cont.resume()
                    case .failure(let error): cont.resume(throwing: error)
                    }
                }
                self.privateDB.add(op)
            }
            index = end
        }
    }

    private func dbSave(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { cont in
            privateDB.save(record) { saved, error in
                if let error { cont.resume(throwing: error) }
                else if let saved { cont.resume(returning: saved) }
                else { cont.resume(throwing: CKError(.internalError)) }
            }
        }
    }

    private func dbFetch(recordID: CKRecord.ID) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { cont in
            privateDB.fetch(withRecordID: recordID) { rec, error in
                if let error { cont.resume(throwing: error) }
                else if let rec { cont.resume(returning: rec) }
                else { cont.resume(throwing: CKError(.unknownItem)) }
            }
        }
    }

    private func fetchOrCreate(recordType: String, id: CKRecord.ID) async throws -> CKRecord {
        do { return try await dbFetch(recordID: id) }
        catch let ck as CKError where ck.code == .unknownItem { return CKRecord(recordType: recordType, recordID: id) }
    }

    private func performQuery(query: CKQuery, cursor: CKQueryOperation.Cursor?) async throws -> (records: [CKRecord], cursor: CKQueryOperation.Cursor?) {
        try await withCheckedThrowingContinuation { cont in
            let op: CKQueryOperation = (cursor != nil) ? CKQueryOperation(cursor: cursor!) : CKQueryOperation(query: query)
            var fetched: [CKRecord] = []
            op.recordMatchedBlock = { _, result in if case .success(let record) = result { fetched.append(record) } }
            op.queryResultBlock = { result in
                switch result {
                case .success(let next): cont.resume(returning: (fetched, next))
                case .failure(let err): cont.resume(throwing: err)
                }
            }
            self.privateDB.add(op)
        }
    }

    private func updateLastSyncDate() {
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: "icloud.sync.lastDate")
    }

    private func ensureLocalFolders() throws { try imageStore.ensureDirs(); _ = localImagesDir }
}

// MARK: - Notification Names
extension Notification.Name {
    static let iCloudLocalStoreWiped = Notification.Name("com.daisyyang.mythings.iCloudLocalStoreWiped")
    static let iCloudCategoriesSynced = Notification.Name("com.daisyyang.mythings.iCloudCategoriesSynced")
    // Note: .iCloudRemoteNotificationReceived is declared in CloudKitAppDelegate.swift
}
