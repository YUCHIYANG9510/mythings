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

// MARK: - Single-flight gate (防重入)
actor SyncGate {
    private var isRunning = false
    func runOnce(_ op: @escaping () async throws -> Void) async rethrows {
        guard !isRunning else {
            print("⚠️ Sync already in progress, skipping…")
            return
        }
        isRunning = true
        defer { isRunning = false }
        try await op()
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
}

// MARK: - CloudKitSyncManager
@MainActor
final class iCloudSyncManager: ObservableObject {
    // Public state
    @Published var syncStatus: iCloudSyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published private(set) var supportsOrderIndex: Bool = false
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "icloud.sync.enabled")
            if isEnabled { enableCloudSync() } else { disableCloudSync() }
        }
    }

    // Private
    private lazy var container = CKContainer(identifier: "iCloud.com.daisyyang.mythings.v2")
    private lazy var privateDB = container.privateCloudDatabase
    private var cancellables = Set<AnyCancellable>()
    private let fm = FileManager.default
    private let gate = SyncGate()
    private let imageStore = ImageStore()

    private var documentsDir: URL { imageStore.documentsDir }
    private var localItemsURL: URL { documentsDir.appendingPathComponent("items.json") }
    private var localCategoriesURL: URL { documentsDir.appendingPathComponent("categories.json") }
    private var localImagesDir: URL { imageStore.imagesDir }

    private var currentSyncTask: Task<Void, Never>?
    
    // MARK: - 增量同步相關屬性
    private var lastItemSyncDate: Date {
        get { UserDefaults.standard.object(forKey: "icloud.sync.items.lastDate") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "icloud.sync.items.lastDate") }
    }

    private var lastCategorySyncDate: Date {
        get { UserDefaults.standard.object(forKey: "icloud.sync.categories.lastDate") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "icloud.sync.categories.lastDate") }
    }
    
    // 同步策略常數
    private let fullSyncThreshold: TimeInterval = 24 * 60 * 60 // 24小時
    private let maxRetryAttempts: Int = 3
    private let batchSize: Int = 300

    // 正規化分類名稱作為唯一 Key（避免同名多筆）
    private func normalizeCategoryKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // Lifecycle
    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "icloud.sync.enabled")
        self.lastSyncDate = UserDefaults.standard.object(forKey: "icloud.sync.lastDate") as? Date
        self.supportsOrderIndex = UserDefaults.standard.bool(forKey: "icloud.schema.orderIndex")
        if isEnabled { enableCloudSync() }
        // 開 app 後稍等一下再嘗試啟動一次，避免網路/iCloud 尚未就緒
        Task { [weak self] in
                try? await Task.sleep(nanoseconds: 400_000_000)
                await MainActor.run { [weak self] in
                    self?.kickoffIfNeeded()
                }
            }
    }

    // MARK: - Public helpers

    /// 在「啟用」且目前不是同步中時，觸發一次同步。
    func kickoffIfNeeded() {
        guard isEnabled else { return }
        if case .syncing = syncStatus { return }
        manualSync()
    }

    func manualSync() {
        guard isEnabled else { return }
        currentSyncTask?.cancel()

        currentSyncTask = Task { [weak self] in
            guard let self else { return }
            await gate.runOnce { [weak self] in
                guard let self else { return }
                await MainActor.run { self.syncStatus = .syncing }
                do {
                    try await self.runOptimizedSync()
                    await MainActor.run {
                        self.syncStatus = .success
                        self.updateLastSyncDate()
                    }
                    // 讓 UI 有時間看到「成功」，再回 idle（可調整/移除）
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await MainActor.run { self.syncStatus = .idle }
                } catch is CancellationError {
                    await MainActor.run { self.syncStatus = .idle }
                } catch {
                    let friendlyError = mapErrorToFriendlyMessage(error)
                    await MainActor.run { self.syncStatus = .error(friendlyError) }
                }
            }
            if !Task.isCancelled {
                await MainActor.run { [weak self] in self?.currentSyncTask = nil }
            }
        }
    }

    func checkiCloudAvailability() -> Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    // MARK: - 錯誤映射
    private func mapErrorToFriendlyMessage(_ error: Error) -> String {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .notAuthenticated:
                return SyncError.authenticationFailed.localizedDescription
            case .networkUnavailable, .networkFailure:
                return SyncError.networkError(underlying: error).localizedDescription
            case .quotaExceeded:
                return SyncError.quotaExceeded.localizedDescription
            case .serviceUnavailable, .requestRateLimited:
                return "iCloud 服務暫時不可用，請稍後再試"
            default:
                return ckError.localizedDescription
            }
        }
        return error.localizedDescription
    }

    // MARK: - Enable / Disable

    private func enableCloudSync() {
        print("=== CloudKit Debug Info ===")
        print("Container ID: \(container.containerIdentifier ?? "nil")")
        print("App Bundle ID: \(Bundle.main.bundleIdentifier ?? "nil")")

        // 查詢帳號狀態後，若可用就立即啟動同步
        container.accountStatus { [weak self] status, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    let mappedError = self.mapErrorToFriendlyMessage(error)
                    self.syncStatus = .error(mappedError)
                    return
                }
                print("Account status: \(status.rawValue)")
                if status == .available {
                    // 等 300ms 讓 iCloud/網路就緒，再觸發
                    Task { [weak self] in
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            await self?.detectOrderIndexSupport()
                            await MainActor.run { [weak self] in
                                self?.kickoffIfNeeded()
                            }
                        }
                }
            }
        }
    }

    // 嘗試偵測 CloudKit 是否已建立 orderIndex 欄位（Item/Category 皆需要）。
    private func detectOrderIndexSupport() async {
        do {
            let q = CKQuery(recordType: "Category", predicate: NSPredicate(value: true))
            q.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true)]
            _ = try await performQuery(query: q, cursor: nil)
            await MainActor.run {
                self.supportsOrderIndex = true
                UserDefaults.standard.set(true, forKey: "icloud.schema.orderIndex")
            }
        } catch {
            await MainActor.run {
                self.supportsOrderIndex = false
                UserDefaults.standard.set(false, forKey: "icloud.schema.orderIndex")
            }
        }
    }

    private func disableCloudSync() {
        currentSyncTask?.cancel()
        currentSyncTask = nil
        cancellables.removeAll()
        syncStatus = .idle
    }

    // MARK: - Local IO

    private func loadLocalItems() -> [Item] {
        guard fm.fileExists(atPath: localItemsURL.path),
              let data = try? Data(contentsOf: localItemsURL),
              let items = try? JSONDecoder().decode([Item].self, from: data) else {
            return []
        }
        return items
    }

    private func saveLocalItems(_ items: [Item]) {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: localItemsURL, options: .atomic)
        } catch {
            print("Save items.json failed: \(error)")
        }
    }

    private func loadLocalCategories() -> [Category] {
        guard fm.fileExists(atPath: localCategoriesURL.path),
              let data = try? Data(contentsOf: localCategoriesURL),
              let cats = try? JSONDecoder().decode([Category].self, from: data) else {
            return []
        }
        return cats
    }

    private func saveLocalCategories(_ cats: [Category]) {
        do {
            let data = try JSONEncoder().encode(cats)
            try data.write(to: localCategoriesURL, options: .atomic)
        } catch {
            print("Save categories.json failed: \(error)")
        }
    }

    // MARK: - 混合同步策略
    private func runOptimizedSync() async throws {
        let timeSinceLastSync = Date().timeIntervalSince(lastSyncDate ?? .distantPast)
        let shouldDoFullSync = timeSinceLastSync > fullSyncThreshold || lastSyncDate == nil
        
        if shouldDoFullSync {
            print("=== Running Full Sync (first time or >24h) ===")
            try await runFullSync()
        } else {
            do {
                print("=== Running Incremental Sync ===")
                try await runIncrementalSync()
            } catch {
                print("Incremental sync failed, falling back to full sync: \(error)")
                try await runFullSync()
            }
        }
    }

    // MARK: - 增量同步
    private func runIncrementalSync() async throws {
        print("=== Starting Incremental Sync ===")
        try Task.checkCancellation()
        
        try ensureLocalFolders()
        
        // 增量推送本地變更
        try await pushLocalChanges()
        
        // 增量拉取雲端變更
        try await pullRemoteChanges()
        
        print("✓ Incremental sync completed")
    }

    private func pushLocalChanges() async throws {
        let items = loadLocalItems()
        let categories = loadLocalCategories()
        
        // 對於 items，我們假設最近的項目可能有變更（可以根據實際需求調整）
        // 這裡簡化為推送最近 7 天創建的項目
        let recentThreshold = Date().addingTimeInterval(-7 * 24 * 60 * 60) // 7天前
        let recentItems = items.filter { item in
            (item.date ?? .distantPast) > max(recentThreshold, lastItemSyncDate)
        }
        
        if !recentItems.isEmpty {
            print("Pushing \(recentItems.count) recent/changed items")
            try await pushItemsWithRetry(recentItems)
        }
        
        // 分類變更檢測：推送所有分類（通常數量不多）
        if !categories.isEmpty {
            try await pushCategoriesWithRetry(categories)
        }
    }

    private func pullRemoteChanges() async throws {
        // 只拉取自上次同步後的變更
        try await pullItemsSince(lastItemSyncDate)
        try await pullCategoriesSince(lastCategorySyncDate)
        
        // 更新同步時間戳
        let now = Date()
        lastItemSyncDate = now
        lastCategorySyncDate = now
    }

    private func pullItemsSince(_ since: Date) async throws {
        let predicate = NSPredicate(format: "updatedAt > %@", since as CVarArg)
        let query = CKQuery(recordType: "Item", predicate: predicate)
        
        if supportsOrderIndex {
            query.sortDescriptors = [
                NSSortDescriptor(key: "orderIndex", ascending: true),
                NSSortDescriptor(key: "updatedAt", ascending: false)
            ]
        } else {
            query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        }
        
        var allChanges: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        
        repeat {
            let page = try await performQuery(query: query, cursor: cursor)
            allChanges.append(contentsOf: page.records)
            cursor = page.cursor
        } while cursor != nil
        
        guard !allChanges.isEmpty else {
            print("No item changes since last sync")
            return
        }
        
        print("Found \(allChanges.count) changed items")
        try await mergeItemChanges(allChanges)
    }

    private func pullCategoriesSince(_ since: Date) async throws {
        let predicate = NSPredicate(format: "updatedAt > %@", since as CVarArg)
        let query = CKQuery(recordType: "Category", predicate: predicate)
        
        if supportsOrderIndex {
            query.sortDescriptors = [
                NSSortDescriptor(key: "orderIndex", ascending: true),
                NSSortDescriptor(key: "updatedAt", ascending: false)
            ]
        } else {
            query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        }
        
        var allChanges: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        
        repeat {
            let page = try await performQuery(query: query, cursor: cursor)
            allChanges.append(contentsOf: page.records)
            cursor = page.cursor
        } while cursor != nil
        
        guard !allChanges.isEmpty else {
            print("No category changes since last sync")
            return
        }
        
        print("Found \(allChanges.count) changed categories")
        try await mergeCategoryChanges(allChanges)
    }

    private func mergeItemChanges(_ changes: [CKRecord]) async throws {
        var local = loadLocalItems()
        
        for record in changes {
            guard
                let idStr = record["id"] as? String,
                let uuid = UUID(uuidString: idStr),
                let brand = record["brand"] as? String,
                let category = record["category"] as? String,
                let name = record["name"] as? String,
                let price = record["price"] as? String
            else { continue }
            
            let date = record["date"] as? Date
            var finalImageName = ""
            
            // 處理圖片下載
            if let asset = record["image"] as? CKAsset, let cloudURL = asset.fileURL {
                finalImageName = "\(uuid.uuidString).png"
                let target = imageStore.fileURL(for: finalImageName)

                do {
                    try imageStore.ensureDirs()
                    if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }
                    try fm.copyItem(at: cloudURL, to: target)
                    print("✅ Downloaded image: \(finalImageName)")
                    ImageMemoryCache.shared.remove(finalImageName)
                } catch {
                    print("❌ Copy image failed: \(error)")
                    finalImageName = ""
                }
            }
            
            let updatedItem = Item(
                id: uuid,
                imageName: finalImageName,
                brand: brand,
                category: category,
                name: name,
                price: price,
                date: date
            )
            
            // 更新或新增項目
            if let index = local.firstIndex(where: { $0.id == uuid }) {
                local[index] = updatedItem
            } else {
                local.append(updatedItem)
            }
        }
        
        saveLocalItems(local)
        print("✅ Merged \(changes.count) item changes")
    }

    private func mergeCategoryChanges(_ changes: [CKRecord]) async throws {
        var local = loadLocalCategories()
        
        for record in changes {
            guard
                let idStr = record["id"] as? String,
                let uuid = UUID(uuidString: idStr),
                let name = record["name"] as? String
            else { continue }
            
            let emoji = (record["emoji"] as? String) ?? ""
            let updatedCategory = Category(id: uuid, name: name, emoji: emoji)
            
            // 更新或新增分類
            if let index = local.firstIndex(where: { $0.id == uuid }) {
                local[index] = updatedCategory
            } else if !local.contains(where: { normalizeCategoryKey($0.name) == normalizeCategoryKey(name) }) {
                // 如果沒有同名的分類才新增
                local.append(updatedCategory)
            }
        }
        
        saveLocalCategories(local)
        print("✅ Merged \(changes.count) category changes")
    }

    // MARK: - 完整同步（保留原邏輯作為備選）
    private func runFullSync() async throws {
        print("=== Starting Full Sync ===")
        try Task.checkCancellation()

        try ensureLocalFolders()
        print("✓ Local folders ensured")

        // Push-first → Pull（避免本機更動被雲端覆寫）
        let items = loadLocalItems()
        let cats = loadLocalCategories()

        if !items.isEmpty {
            try Task.checkCancellation()
            try await pushItemsWithRetry(items)
            print("✓ Items pushed")
        }
        if !cats.isEmpty {
            try Task.checkCancellation()
            try await pushCategoriesWithRetry(cats)
            print("✓ Categories pushed")
        }

        try Task.checkCancellation()
        try await pullItems()
        try Task.checkCancellation()
        try await pullCategories()
        print("✓ Full sync completed")
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
                } catch let e as CKError where e.code == .serverRecordChanged && attempts < maxRetryAttempts - 1 {
                    attempts += 1
                    let delay = min(400_000_000 * UInt64(attempts), 2_000_000_000) // 最多等2秒
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    throw error
                }
            }
        }
    }

    private func pushCategoriesWithRetry(_ categories: [Category]) async throws {
        // 在推送前先做一次雲端清理：把不在本機名單內的同名分類刪除，多餘重複也清掉
        try await cleanupAndDeleteRemoteCategories(notInLocal: Set(categories.map { normalizeCategoryKey($0.name) }))

        for (index, cat) in categories.enumerated() {
            try Task.checkCancellation()
            var attempts = 0
            while attempts < maxRetryAttempts {
                do {
                    let ord = supportsOrderIndex ? index : 0
                    try await pushSingleCategory(cat, orderIndex: ord)
                    break
                } catch let e as CKError where e.code == .serverRecordChanged && attempts < maxRetryAttempts - 1 {
                    attempts += 1
                    print("⚠️ serverRecordChanged, retry \(attempts) for category \(cat.name)")
                    let delay = min(400_000_000 * UInt64(attempts), 2_000_000_000)
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    throw error
                }
            }
        }
    }

    // MARK: - Push one item

    private func pushSingleItem(_ item: Item, orderIndex: Int) async throws {
        let rid = CKRecord.ID(recordName: "item-\(item.id.uuidString)")
        let rec = try await fetchOrCreate(recordType: "Item", id: rid)

        rec["id"] = item.id.uuidString as CKRecordValue
        rec["brand"] = item.brand as CKRecordValue
        rec["category"] = item.category as CKRecordValue
        rec["name"] = item.name as CKRecordValue
        rec["price"] = item.price as CKRecordValue
        if let d = item.date { rec["date"] = d as CKRecordValue }
        rec["updatedAt"] = Date() as CKRecordValue
        rec["orderIndex"] = NSNumber(value: orderIndex)

        if !item.imageName.isEmpty {
            let fileName = imageStore.sanitizedFileName(item.imageName)
            let imgURL = imageStore.fileURL(for: fileName)

            if imageStore.nonEmptyFile(imgURL) {
                let asset = try imageStore.assetForUpload(from: imgURL, id: item.id)
                rec["image"] = asset
                print("✅ Upload image \(fileName)")
            } else {
                print("⚠️ Missing or empty image file: \(imgURL.path)")
                rec["image"] = nil
            }
        } else {
            rec["image"] = nil
        }

        _ = try await dbSave(rec)
    }

    private func pushSingleCategory(_ category: Category, orderIndex: Int) async throws {
        // 以名稱作為唯一鍵，避免兩裝置產生不同 UUID 而重複
        let key = normalizeCategoryKey(category.name)
        let rid = CKRecord.ID(recordName: "category-name-\(key)")
        let rec = try await fetchOrCreate(recordType: "Category", id: rid)
        rec["id"] = category.id.uuidString as CKRecordValue
        rec["name"] = category.name as CKRecordValue
        if !category.emoji.isEmpty { rec["emoji"] = category.emoji as CKRecordValue } else { rec["emoji"] = nil }
        rec["updatedAt"] = Date() as CKRecordValue
        rec["orderIndex"] = NSNumber(value: orderIndex)
        _ = try await dbSave(rec)
    }

    // MARK: - Pull

    private func pullItems() async throws {
        let query = CKQuery(recordType: "Item", predicate: NSPredicate(value: true))
        if supportsOrderIndex {
            query.sortDescriptors = [
                NSSortDescriptor(key: "orderIndex", ascending: true),
                NSSortDescriptor(key: "updatedAt", ascending: false)
            ]
        } else {
            query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        }

        var all: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let page = try await performQuery(query: query, cursor: cursor)
            all.append(contentsOf: page.records)
            cursor = page.cursor
        } while cursor != nil

        var local = loadLocalItems()
        var cloudOrder: [(UUID, Int)] = []
        var fallbackOrderIndexByUUID: [UUID: Int] = [:]

        for (idx, r) in all.enumerated() {
            guard
                let idStr = r["id"] as? String,
                let uuid = UUID(uuidString: idStr),
                let brand = r["brand"] as? String,
                let category = r["category"] as? String,
                let name = r["name"] as? String,
                let price = r["price"] as? String
            else { continue }

            let date = r["date"] as? Date
            let orderIdx = supportsOrderIndex ? (r["orderIndex"] as? NSNumber)?.intValue : nil
            var finalImageName = ""

            if let asset = r["image"] as? CKAsset, let cloudURL = asset.fileURL {
                finalImageName = "\(uuid.uuidString).png"
                let target = imageStore.fileURL(for: finalImageName)

                do {
                    try imageStore.ensureDirs()
                    if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }
                    try fm.copyItem(at: cloudURL, to: target)
                    print("✅ Downloaded image: \(finalImageName)")
                    ImageMemoryCache.shared.remove(finalImageName) // 你專案中的快取管理
                } catch {
                    print("❌ Copy image failed: \(error)")
                    finalImageName = ""
                }
            }

            if let idx = local.firstIndex(where: { $0.id == uuid }) {
                local[idx] = Item(
                    id: uuid,
                    imageName: finalImageName.isEmpty ? local[idx].imageName : finalImageName,
                    brand: brand,
                    category: category,
                    name: name,
                    price: price,
                    date: date
                )
            } else {
                local.append(Item(
                    id: uuid,
                    imageName: finalImageName,
                    brand: brand,
                    category: category,
                    name: name,
                    price: price,
                    date: date
                ))
            }

            if let orderIdx { cloudOrder.append((uuid, orderIdx)) }
            fallbackOrderIndexByUUID[uuid] = idx
        }

        // 以雲端順序重排：支援 orderIndex 則用之，否則用查詢返回順序（最新在前）
        let orderMap: [UUID: Int] = (supportsOrderIndex && !cloudOrder.isEmpty)
            ? Dictionary(uniqueKeysWithValues: cloudOrder)
            : fallbackOrderIndexByUUID
        local.sort { (a, b) -> Bool in
            let ia = orderMap[a.id] ?? Int.max
            let ib = orderMap[b.id] ?? Int.max
            if ia != ib { return ia < ib }
            return (a.date ?? .distantPast) > (b.date ?? .distantPast)
        }

        saveLocalItems(local)
        print("✅ Items pulled and saved: \(local.count)")
    }

    private func pullCategories() async throws {
        let query = CKQuery(recordType: "Category", predicate: NSPredicate(value: true))
        if supportsOrderIndex {
            query.sortDescriptors = [
                NSSortDescriptor(key: "orderIndex", ascending: true),
                NSSortDescriptor(key: "updatedAt", ascending: false)
            ]
        } else {
            query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        }

        var all: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let page = try await performQuery(query: query, cursor: cursor)
            all.append(contentsOf: page.records)
            cursor = page.cursor
        } while cursor != nil

        let local = loadLocalCategories()

        // 暫存依名稱去重：保留最新 updatedAt 的一筆
        var nameToBest: [String: (Category, Date?, CKRecord.ID, Int?)] = [:]
        for r in all {
            guard
                let idStr = r["id"] as? String,
                let uuid = UUID(uuidString: idStr),
                let name = r["name"] as? String
            else { continue }

            let emoji = (r["emoji"] as? String) ?? ""
            let updatedAt = r["updatedAt"] as? Date
            let ord = supportsOrderIndex ? (r["orderIndex"] as? NSNumber)?.intValue : nil
            let key = normalizeCategoryKey(name)

            let candidate = Category(id: uuid, name: name, emoji: emoji)
            if let exist = nameToBest[key] {
                let existingDate = exist.1 ?? .distantPast
                let newDate = updatedAt ?? .distantPast
                if newDate >= existingDate {
                    nameToBest[key] = (candidate, updatedAt, r.recordID, ord)
                }
            } else {
                nameToBest[key] = (candidate, updatedAt, r.recordID, ord)
            }
        }

        // 雲端清理：刪除同名的舊紀錄（保留最新），並刪除非標準鍵（舊 UUID 型）重複
        try await cleanupDuplicateCategoryRecords(allRecords: all, keepKeys: Set(nameToBest.values.map { $0.2 }))

        // 將雲端（去重後）合併進本地：同名以雲端為準；不同名保留本地
        var merged: [Category] = []
        var usedIds = Set<UUID>()

        // 先放入雲端的唯一集合
        // 依 orderIndex 與 updatedAt 決定順序
        let ordered = nameToBest.values.sorted { a, b in
            let ia = a.3 ?? Int.max
            let ib = b.3 ?? Int.max
            if ia != ib { return ia < ib }
            let da = a.1 ?? .distantPast
            let db = b.1 ?? .distantPast
            if da != db { return da > db }
            return a.0.name.lowercased() < b.0.name.lowercased()
        }
        for value in ordered {
            merged.append(value.0)
            usedIds.insert(value.0.id)
        }

        // 加入本地那些雲端沒有同名的一筆
        let cloudNameSet = Set(nameToBest.keys)
        for lc in local {
            let key = lc.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !cloudNameSet.contains(key) && !usedIds.contains(lc.id) {
                merged.append(lc)
            }
        }

        // 已依 orderIndex 合併排序，無需額外排序

        saveLocalCategories(merged)
        print("✅ Categories pulled and saved: \(merged.count)")
    }

    // 刪除同名重複與舊格式鍵的分類紀錄，只保留一筆最新的（傳入要保留的 RecordID 集合）
    private func cleanupDuplicateCategoryRecords(allRecords: [CKRecord], keepKeys: Set<CKRecord.ID>) async throws {
        var toDelete: [CKRecord.ID] = []
        for r in allRecords {
            let id = r.recordID
            if !keepKeys.contains(id) {
                // 若不是被選中的最新一筆，刪掉；另外，舊的 UUID 型 recordName 也刪
                if id.recordName.hasPrefix("category-") && !id.recordName.hasPrefix("category-name-") {
                    toDelete.append(id)
                } else if !keepKeys.contains(id) {
                    toDelete.append(id)
                }
            }
        }
        if !toDelete.isEmpty {
            try await deleteRecordsInBatches(ids: Array(Set(toDelete)))
        }
    }

    // 刪除雲端中「不在本機名稱集合內」的分類，並去除同名重複
    private func cleanupAndDeleteRemoteCategories(notInLocal localNameKeys: Set<String>) async throws {
        let query = CKQuery(recordType: "Category", predicate: NSPredicate(value: true))
        var all: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let page = try await performQuery(query: query, cursor: cursor)
            all.append(contentsOf: page.records)
            cursor = page.cursor
        } while cursor != nil

        // 分組 by key，保留最新
        var grouped: [String: [(CKRecord, Date?)]] = [:]
        for r in all {
            guard let name = r["name"] as? String else { continue }
            let key = normalizeCategoryKey(name)
            let updatedAt = r["updatedAt"] as? Date
            grouped[key, default: []].append((r, updatedAt))
        }

        var toDelete: [CKRecord.ID] = []
        for (key, list) in grouped {
            // 不在本機名稱集合 → 全刪
            if !localNameKeys.contains(key) {
                toDelete.append(contentsOf: list.map { $0.0.recordID })
                continue
            }

            // 在本機集合 → 保留最新一筆，其餘刪除
            let sorted = list.sorted { ($0.1 ?? .distantPast) > ($1.1 ?? .distantPast) }
            let keep = sorted.first?.0.recordID
            for (rec, _) in sorted.dropFirst() {
                toDelete.append(rec.recordID)
            }

            // 舊 UUID 型 recordName 一率刪，只保留名稱鍵型
            for (rec, _) in list {
                let rn = rec.recordID.recordName
                if rn.hasPrefix("category-") && !rn.hasPrefix("category-name-") {
                    if rec.recordID != keep { toDelete.append(rec.recordID) }
                }
            }
        }

        if !toDelete.isEmpty {
            try await deleteRecordsInBatches(ids: Array(Set(toDelete)))
        }
    }

    private func deleteRecordsInBatches(ids: [CKRecord.ID], batchSize: Int = 300) async throws {
        guard !ids.isEmpty else { return }
        let unique = Array(Set(ids))
        let total = unique.count
        var index = 0
        while index < total {
            let end = min(index + batchSize, total)
            let slice = Array(unique[index..<end])
            try await withCheckedThrowingContinuation { cont in
                let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: slice)
                op.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        cont.resume()
                    case .failure(let error):
                        cont.resume(throwing: error)
                    }
                }
                self.privateDB.add(op)
            }
            index = end
        }
    }

    // MARK: - Public: Purge Categories (Cloud)
    /// 清空 CloudKit 上所有 Category 紀錄（不影響 Items）。
    func purgeAllCategoriesCloud() async {
        do {
            let query = CKQuery(recordType: "Category", predicate: NSPredicate(value: true))
            var all: [CKRecord] = []
            var cursor: CKQueryOperation.Cursor?
            repeat {
                let page = try await performQuery(query: query, cursor: cursor)
                all.append(contentsOf: page.records)
                cursor = page.cursor
            } while cursor != nil

            let ids = all.map { $0.recordID }
            try await deleteRecordsInBatches(ids: ids)
            print("✅ Purged all Category records from iCloud: \(ids.count)")
        } catch {
            print("❌ Purge categories from iCloud failed: \(error)")
        }
    }

    // MARK: - CK helpers

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
        catch let ck as CKError where ck.code == .unknownItem {
            return CKRecord(recordType: recordType, recordID: id)
        }
    }

    private func performQuery(query: CKQuery, cursor: CKQueryOperation.Cursor?) async throws -> (records: [CKRecord], cursor: CKQueryOperation.Cursor?) {
        try await withCheckedThrowingContinuation { cont in
            let op: CKQueryOperation = (cursor != nil) ? CKQueryOperation(cursor: cursor!) : CKQueryOperation(query: query)

            var fetched: [CKRecord] = []

            op.recordMatchedBlock = { _, result in
                if case .success(let record) = result { fetched.append(record) }
            }

            op.queryResultBlock = { result in
                switch result {
                case .success(let next):
                    cont.resume(returning: (fetched, next))
                case .failure(let err):
                    cont.resume(throwing: err)
                }
            }

            self.privateDB.add(op)
        }
    }

    private func updateLastSyncDate() {
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: "icloud.sync.lastDate")
    }

    // MARK: - Folders / Debug

    private func ensureLocalFolders() throws {
        try imageStore.ensureDirs()
        _ = localImagesDir // 只是確保路徑建立
    }

    private func debugFileSystem() {
        print("=== File System Debug ===")
        print("Documents: \(documentsDir.path)")
        print("Images: \(localImagesDir.path)")
        var isDir: ObjCBool = false
        print("Images exists: \(fm.fileExists(atPath: localImagesDir.path, isDirectory: &isDir)) isDir=\(isDir.boolValue)")
        if let files = try? fm.contentsOfDirectory(atPath: localImagesDir.path) {
            print("Images count: \(files.count)")
            for f in files {
                let p = localImagesDir.appendingPathComponent(f).path
                let size = (try? fm.attributesOfItem(atPath: p)[.size] as? Int64) ?? 0
                print(" - \(f) \(size) bytes")
            }
        }
        print("items.json exists: \(fm.fileExists(atPath: localItemsURL.path))")
        print("categories.json exists: \(fm.fileExists(atPath: localCategoriesURL.path))")
        print("=== End Debug ===")
    }

    // MARK: - Delete Sync
    func syncDeletion(for itemId: UUID) async {
        guard isEnabled else { return }
        do {
            let rid = CKRecord.ID(recordName: "item-\(itemId.uuidString)")
            try await privateDB.deleteRecord(withID: rid)
            print("✅ Deleted item from iCloud: \(itemId)")
        } catch {
            print("❌ Failed to delete item from iCloud: \(error)")
        }
    }
}
