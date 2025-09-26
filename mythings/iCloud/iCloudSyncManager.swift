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

// MARK: - Sync Events（統一入口）
enum SyncEvent: Hashable {
    case itemsChanged
    case categoriesChanged
    case deleteItem(UUID)
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

// MARK: - 單一協調器（序列化 + 去重 + 節流）
actor SyncCoordinator {
    private var isSyncing = false
    private var pending = Set<SyncEvent>()
    private let minInterval: TimeInterval = 0.7
    private var lastRun: Date = .distantPast

    func enqueue(_ event: SyncEvent,
                 runners: Runners) async {
        pending.insert(event)
        await maybeRun(runners: runners)
    }

    private func maybeRun(runners: Runners) async {
        guard !isSyncing else { return }

        // 節流：短時間多事件 → 合併
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

        if !pending.isEmpty {
            await maybeRun(runners: runners)
        }
    }

    private func run(_ batch: Set<SyncEvent>, runners: Runners) async throws {
        // 先刪除、再推/拉、最後 full
        let deleteIDs = batch.compactMap { if case let .deleteItem(id) = $0 { return id } else { return nil } }
        for id in deleteIDs {
            try await runners.deleteItem(id)
        }

        if batch.contains(.full) {
            try await runners.full()
            return
        }

        if batch.contains(.itemsChanged) || batch.contains(.categoriesChanged) {
            try await runners.optimized() // 內部已處理 push/pull（增量→fallback full）
        }
    }

    struct Runners {
        let optimized: () async throws -> Void
        let full: () async throws -> Void
        let deleteItem: (UUID) async throws -> Void
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
    private let imageStore = ImageStore()

    private var documentsDir: URL { imageStore.documentsDir }
    private var localItemsURL: URL { documentsDir.appendingPathComponent("items.json") }
    private var localCategoriesURL: URL { documentsDir.appendingPathComponent("categories.json") }
    private var localImagesDir: URL { imageStore.imagesDir }

    // 🔑 單一協調器
    private let coordinator = SyncCoordinator()

    // MARK: - 增量同步相關屬性
    private var lastItemSyncDate: Date {
        get { UserDefaults.standard.object(forKey: "icloud.sync.items.lastDate") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "icloud.sync.items.lastDate") }
    }

    private var lastCategorySyncDate: Date {
        get { UserDefaults.standard.object(forKey: "icloud.sync.categories.lastDate") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "icloud.sync.categories.lastDate") }
    }

    // ⭐️ 新增：追蹤 DeletedItem（墓碑）最後同步時間
    private var lastDeletedSyncDate: Date {
        get { UserDefaults.standard.object(forKey: "icloud.sync.deleted.lastDate") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "icloud.sync.deleted.lastDate") }
    }

    // 同步策略常數
    private let fullSyncThreshold: TimeInterval = 24 * 60 * 60 // 24 小時
    private let maxRetryAttempts: Int = 3
    private let batchSize: Int = 300

    // 正規化分類名稱作為唯一 Key（避免同名多筆）
    private func normalizeCategoryKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // ⭐ 時鐘/網路誤差的保險重疊
    private let clockSkewLeeway: TimeInterval = 5 * 60  // 5 分鐘

    
    // Lifecycle
    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "icloud.sync.enabled")
        self.lastSyncDate = UserDefaults.standard.object(forKey: "icloud.sync.lastDate") as? Date
        self.supportsOrderIndex = UserDefaults.standard.bool(forKey: "icloud.schema.orderIndex")
        if isEnabled { enableCloudSync() }
        // 開 app 後稍等一下再嘗試啟動一次
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            await MainActor.run { [weak self] in
                self?.kickoffIfNeeded()
            }
        }
    }

    // MARK: - Public：統一入口（排程事件）
    func schedule(_ event: SyncEvent) {
        guard isEnabled else { return }
        Task {
            await coordinator.enqueue(event, runners: makeRunners())
        }
    }

    func manualSync() {
        schedule(.full)
    }

    /// App 啟動或使用者開啟 iCloud 時，若非同步中則排一次
    func kickoffIfNeeded() {
        guard isEnabled else { return }
        if case .syncing = syncStatus { return }
        manualSync()
    }

    func checkiCloudAvailability() -> Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    // MARK: - Runners（協調器使用的動作實作）
    private func makeRunners() -> SyncCoordinator.Runners {
        .init(
            optimized: { [weak self] in
                guard let self else { return }
                try await self.runOptimizedSync()
            },
            full: { [weak self] in
                guard let self else { return }
                try await self.runFullSync()
            },
            deleteItem: { [weak self] id in
                guard let self else { return }
                try await self.deleteItemOnCloud(id)
            },
            setStatus: { [weak self] status in
                await MainActor.run { self?.syncStatus = status }
                if case .success = status {
                    await MainActor.run { self?.updateLastSyncDate() }
                }
            }
        )
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
            try await runFullSync()
        } else {
            do {
                try await runIncrementalSync()
            } catch {
                print("Incremental sync failed, falling back to full sync: \(error)")
                try await runFullSync()
            }
        }
    }

    // MARK: - 增量同步（已加入墓碑處理）
    private func runIncrementalSync() async throws {
        try Task.checkCancellation()
        try ensureLocalFolders()

        // ⭐️ 先套用墓碑，避免把已刪的東西從本機推回雲端
        try await pullDeletedItemsSince(lastDeletedSyncDate)

        try await pushLocalChanges()
        try await pullRemoteChanges()
    }

    private func pushLocalChanges() async throws {
        let items = loadLocalItems()
        let categories = loadLocalCategories()

        // ⭐ 用 updatedAt 判斷本機最近有變更的項目（含重疊）
        let watermark = lastItemSyncDate.addingTimeInterval(-clockSkewLeeway)
        let recentItems = items.filter { $0.updatedAt > watermark }

        if !recentItems.isEmpty {
            try await pushItemsWithRetry(recentItems)
        }

        if !categories.isEmpty {
            try await pushCategoriesWithRetry(categories)
        }
    }


    private func pullRemoteChanges() async throws {
        try await pullItemsSince(lastItemSyncDate)
        try await pullCategoriesSince(lastCategorySyncDate)
       
    }
    private func pullItemsSince(_ since: Date) async throws {
        // ⭐ 將 since 往回推一段重疊，避免漏抓
        let sinceWithLeeway = since.addingTimeInterval(-clockSkewLeeway)
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

        guard !allChanges.isEmpty else { return }
        try await mergeItemChanges(allChanges)
    }

    private func pullCategoriesSince(_ since: Date) async throws {
        let sinceWithLeeway = since.addingTimeInterval(-clockSkewLeeway)          // ⭐ 重疊
        let predicate = NSPredicate(format: "updatedAt > %@", sinceWithLeeway as CVarArg)
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

        guard !allChanges.isEmpty else { return }
        try await mergeCategoryChanges(allChanges)   // ⭐ 水位在 merge 裡更新
    }

    private func mergeItemChanges(_ changes: [CKRecord]) async throws {
        var local = loadLocalItems()
        var maxCloudUpdatedAt: Date = lastItemSyncDate   // ⭐ 追蹤雲端最大時間

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
            let cloudUpdatedAt = record["updatedAt"] as? Date ?? .distantPast
            if cloudUpdatedAt > maxCloudUpdatedAt { maxCloudUpdatedAt = cloudUpdatedAt }   // ⭐

            var finalImageName = ""
            if let asset = record["image"] as? CKAsset, let cloudURL = asset.fileURL {
                finalImageName = "\(uuid.uuidString).png"
                let target = imageStore.fileURL(for: finalImageName)
                do {
                    try imageStore.ensureDirs()
                    if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }
                    try fm.copyItem(at: cloudURL, to: target)
                    ImageMemoryCache.shared.remove(finalImageName)
                } catch {
                    print("❌ Copy image failed: \(error)")
                    finalImageName = ""
                }
            }

            if let index = local.firstIndex(where: { $0.id == uuid }) {
                let chosenImageName = finalImageName.isEmpty ? local[index].imageName : finalImageName
                let merged = Item(
                    id: uuid,
                    imageName: chosenImageName,
                    brand: brand,
                    category: category,
                    name: name,
                    price: price,
                    date: date,
                    updatedAt: cloudUpdatedAt
                )
                local[index] = merged
            } else {
                let newItem = Item(
                    id: uuid,
                    imageName: finalImageName,
                    brand: brand,
                    category: category,
                    name: name,
                    price: price,
                    date: date,
                    updatedAt: cloudUpdatedAt
                )
                local.append(newItem)
            }
        }

        saveLocalItems(local)

        // ⭐ 將水位設為「目前水位」與「雲端最大 updatedAt」的較大者
        //    （不要直接用 Date()，避免把水位設得過新而漏抓）
        if maxCloudUpdatedAt > lastItemSyncDate {
            lastItemSyncDate = maxCloudUpdatedAt
        }
    }

    private func mergeCategoryChanges(_ changes: [CKRecord]) async throws {
        var local = loadLocalCategories()
        var maxCloudUpdatedAt: Date = lastCategorySyncDate                         // ⭐ 追蹤最大時間

        for record in changes {
            guard
                let idStr = record["id"] as? String,
                let uuid = UUID(uuidString: idStr),
                let name = record["name"] as? String
            else { continue }

            let emoji = (record["emoji"] as? String) ?? ""
            let cloudUpdatedAt = record["updatedAt"] as? Date ?? .distantPast
            if cloudUpdatedAt > maxCloudUpdatedAt { maxCloudUpdatedAt = cloudUpdatedAt }   // ⭐

            let updatedCategory = Category(id: uuid, name: name, emoji: emoji)

            if let index = local.firstIndex(where: { $0.id == uuid }) {
                local[index] = updatedCategory
            } else if !local.contains(where: { normalizeCategoryKey($0.name) == normalizeCategoryKey(name) }) {
                local.append(updatedCategory)
            }
        }

        saveLocalCategories(local)

        // ⭐ 用雲端最大 updatedAt 更新水位（不要用 Date()）
        if maxCloudUpdatedAt > lastCategorySyncDate {
            lastCategorySyncDate = maxCloudUpdatedAt
        }
    }

    // MARK: - 完整同步（已加入墓碑處理）
    private func runFullSync() async throws {
        try Task.checkCancellation()
        try ensureLocalFolders()

        // ⭐️ 先套用墓碑，防止舊裝置把東西又推回來
        try await pullAllDeletedItems()

        let items = loadLocalItems()
        let cats = loadLocalCategories()

        if !items.isEmpty {
            try Task.checkCancellation()
            try await pushItemsWithRetry(items)
        }
        if !cats.isEmpty {
            try Task.checkCancellation()
            try await pushCategoriesWithRetry(cats)
        }

        try Task.checkCancellation()
        try await pullItems()
        try Task.checkCancellation()
        try await pullCategories()
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
                    let delay = min(400_000_000 * UInt64(attempts), 2_000_000_000)
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    throw error
                }
            }
        }
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
                } catch let e as CKError where e.code == .serverRecordChanged && attempts < maxRetryAttempts - 1 {
                    attempts += 1
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
        rec["updatedAt"] = item.updatedAt as CKRecordValue   // ⭐ 用本機記錄的 updatedAt
        rec["orderIndex"] = NSNumber(value: orderIndex)

        if !item.imageName.isEmpty {
            let fileName = imageStore.sanitizedFileName(item.imageName)
            let imgURL = imageStore.fileURL(for: fileName)

            if imageStore.nonEmptyFile(imgURL) {
                let asset = try imageStore.assetForUpload(from: imgURL, id: item.id)
                rec["image"] = asset
            } else {
                rec["image"] = nil
            }
        } else {
            rec["image"] = nil
        }

        _ = try await dbSave(rec)
    }

    private func pushSingleCategory(_ category: Category, orderIndex: Int) async throws {
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

    // MARK: - Pull 全量（作為 Full 的一環）

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
        var maxCloudUpdatedAt: Date = lastItemSyncDate   // ⭐ 追蹤雲端最大 updatedAt

        for (idx, r) in all.enumerated() {
            guard
                let idStr = r["id"] as? String,
                let uuid = UUID(uuidString: idStr),
                let brand = r["brand"] as? String,
                let category = r["category"] as? String,
                let name = r["name"] as? String,
                let price = r["price"] as? String
            else { continue }

            let date           = r["date"] as? Date
            let cloudUpdatedAt = r["updatedAt"] as? Date ?? .distantPast   // ⭐ 雲端時間
            if cloudUpdatedAt > maxCloudUpdatedAt { maxCloudUpdatedAt = cloudUpdatedAt } // ⭐ 累計最大值

            let orderIdx = supportsOrderIndex ? (r["orderIndex"] as? NSNumber)?.intValue : nil

            var finalImageName = ""
            if let asset = r["image"] as? CKAsset, let cloudURL = asset.fileURL {
                finalImageName = "\(uuid.uuidString).png"
                let target = imageStore.fileURL(for: finalImageName)
                do {
                    try imageStore.ensureDirs()
                    if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }
                    try fm.copyItem(at: cloudURL, to: target)
                    ImageMemoryCache.shared.remove(finalImageName)
                } catch {
                    print("❌ Copy image failed: \(error)")
                    finalImageName = ""
                }
            }

            if let idxLocal = local.firstIndex(where: { $0.id == uuid }) {
                let merged = Item(
                    id: uuid,
                    imageName: finalImageName.isEmpty ? local[idxLocal].imageName : finalImageName, // ⭐ 雲端沒圖→保留本機圖
                    brand: brand,
                    category: category,
                    name: name,
                    price: price,
                    date: date,
                    updatedAt: cloudUpdatedAt                                                     // ⭐ 寫回雲端時間
                )
                local[idxLocal] = merged
            } else {
                let newItem = Item(
                    id: uuid,
                    imageName: finalImageName,
                    brand: brand,
                    category: category,
                    name: name,
                    price: price,
                    date: date,
                    updatedAt: cloudUpdatedAt                                                     // ⭐
                )
                local.append(newItem)
            }

            if let orderIdx { cloudOrder.append((uuid, orderIdx)) }
            fallbackOrderIndexByUUID[uuid] = idx
        }

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

        // ⭐ 用雲端最大 updatedAt 更新本機水位（避免設成現在時間造成之後漏抓）
        if maxCloudUpdatedAt > lastItemSyncDate {
            lastItemSyncDate = maxCloudUpdatedAt
        }
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
        var maxCloudUpdatedAt: Date = lastCategorySyncDate   // ⭐ 追蹤雲端最大時間

        // 依「規一化名稱」挑最新一筆，並保留排序資訊
        var nameToBest: [String: (Category, Date?, CKRecord.ID, Int?)] = [:]
        for r in all {
            guard
                let idStr = r["id"] as? String,
                let uuid  = UUID(uuidString: idStr),
                let name  = r["name"] as? String
            else { continue }

            let emoji = (r["emoji"] as? String) ?? ""
            let updatedAt = r["updatedAt"] as? Date
            if let upd = updatedAt, upd > maxCloudUpdatedAt { maxCloudUpdatedAt = upd }   // ⭐ 累計最大值
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

        // 清除重複舊鍵（僅保留我們挑的那幾筆）
        try await cleanupDuplicateCategoryRecords(
            allRecords: all,
            keepKeys: Set(nameToBest.values.map { $0.2 })
        )

        // 產出排序後的最終清單
        var merged: [Category] = []
        var usedIds = Set<UUID>()

        let ordered = nameToBest.values.sorted { a, b in
            let ia = a.3 ?? Int.max
            let ib = b.3 ?? Int.max
            if ia != ib { return ia < ib }                      // 先看 orderIndex（小在前）
            let da = a.1 ?? .distantPast
            let db = b.1 ?? .distantPast
            if da != db { return da > db }                      // 再看 updatedAt（新在前）
            return a.0.name.lowercased() < b.0.name.lowercased()// 最後按名稱
        }
        for value in ordered {
            merged.append(value.0)
            usedIds.insert(value.0.id)
        }

        // 雲端沒有但本機有的，保留在尾端（避免資料突然消失）
        let cloudNameSet = Set(nameToBest.keys)
        for lc in local {
            let key = normalizeCategoryKey(lc.name)
            if !cloudNameSet.contains(key) && !usedIds.contains(lc.id) {
                merged.append(lc)
            }
        }

        saveLocalCategories(merged)

        // ⭐ 用雲端最大 updatedAt 回寫水位（不要用 Date()）
        if maxCloudUpdatedAt > lastCategorySyncDate {
            lastCategorySyncDate = maxCloudUpdatedAt
        }
    }

    // 刪除同名重複與舊格式鍵的分類紀錄，只保留一筆最新的（傳入要保留的 RecordID 集合）
    private func cleanupDuplicateCategoryRecords(allRecords: [CKRecord], keepKeys: Set<CKRecord.ID>) async throws {
        var toDelete: [CKRecord.ID] = []
        for r in allRecords {
            let id = r.recordID
            if !keepKeys.contains(id) {
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

    // NOTE: 僅供「Reset / 清庫」情境使用（一般同步不要呼叫）
    private func cleanupAndDeleteRemoteCategories(notInLocal localNameKeys: Set<String>) async throws {
        let query = CKQuery(recordType: "Category", predicate: NSPredicate(value: true))
        var all: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let page = try await performQuery(query: query, cursor: cursor)
            all.append(contentsOf: page.records)
            cursor = page.cursor
        } while cursor != nil

        var grouped: [String: [(CKRecord, Date?)]] = [:]
        for r in all {
            guard let name = r["name"] as? String else { continue }
            let key = normalizeCategoryKey(name)
            let updatedAt = r["updatedAt"] as? Date
            grouped[key, default: []].append((r, updatedAt))
        }

        var toDelete: [CKRecord.ID] = []
        for (key, list) in grouped {
            if !localNameKeys.contains(key) {
                toDelete.append(contentsOf: list.map { $0.0.recordID })
                continue
            }

            let sorted = list.sorted { ($0.1 ?? .distantPast) > ($1.1 ?? .distantPast) }
            let keep = sorted.first?.0.recordID
            for (rec, _) in sorted.dropFirst() {
                toDelete.append(rec.recordID)
            }

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

    // MARK: - Public maintenance / inspection

    /// 回傳 iCloud（CloudKit Private DB）目前的 Item/Category 總數
    func countAllRecords() async -> (items: Int, categories: Int) {
        let items = await countItemRecords()
        let categories = await countCategoryRecords()
        return (items, categories)
    }

    func countItemRecords() async -> Int { await countRecords(of: "Item") }
    func countCategoryRecords() async -> Int { await countRecords(of: "Category") }

    func purgeAllItemsCloud() async {
        do {
            let ids = try await fetchAllRecordIDs(of: "Item")
            guard !ids.isEmpty else {
                print("ℹ️ No Item records to purge.")
                return
            }
            try await deleteRecordsInBatches(ids: ids)
            print("✅ Purged all Item records from iCloud: \(ids.count)")
        } catch {
            print("❌ Purge items from iCloud failed: \(error)")
        }
    }

    func purgeAllCloud() async {
        await purgeAllItemsCloud()
        await purgeAllCategoriesCloud()
    }

    func wipeLocalStore() {
        // 刪 JSON
        try? fm.removeItem(at: localItemsURL)
        try? fm.removeItem(at: localCategoriesURL)

        // 刪圖片（僅刪檔案，不刪資料夾）
        if let files = try? fm.contentsOfDirectory(at: localImagesDir, includingPropertiesForKeys: nil) {
            for url in files { try? fm.removeItem(at: url) }
        }

        // 重置同步狀態（下次觸發會走 full）
        lastSyncDate = nil
        UserDefaults.standard.removeObject(forKey: "icloud.sync.lastDate")
        lastItemSyncDate = .distantPast
        lastCategorySyncDate = .distantPast
        lastDeletedSyncDate = .distantPast

        print("🧹 Wiped local store (items.json, categories.json, images/*) and reset sync timestamps.")
    }

    // MARK: - Private helpers for counts

    private func countRecords(of recordType: String) async -> Int {
        do {
            var total = 0
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            var cursor: CKQueryOperation.Cursor?
            repeat {
                let page = try await performQuery(query: query, cursor: cursor)
                total += page.records.count
                cursor = page.cursor
            } while cursor != nil
            return total
        } catch {
            print("❌ countRecords(\(recordType)) failed: \(error)")
            return 0
        }
    }

    private func fetchAllRecordIDs(of recordType: String) async throws -> [CKRecord.ID] {
        var ids: [CKRecord.ID] = []
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let page = try await performQuery(query: query, cursor: cursor)
            ids.append(contentsOf: page.records.map { $0.recordID })
            cursor = page.cursor
        } while cursor != nil
        return Array(Set(ids))
    }

    /// 刪除 iCloud 上所有 Category 記錄（不影響 Items）
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

    // MARK: - Delete（協調器呼叫）— 已加入墓碑 + 全面清除
    private func deleteItemOnCloud(_ itemId: UUID) async throws {
        // 0) 先寫入「墓碑」DeletedItem：deleted-<uuid>
        do {
            let did = CKRecord.ID(recordName: "deleted-\(itemId.uuidString)")
            let tomb = try await fetchOrCreate(recordType: "DeletedItem", id: did)
            tomb["id"] = itemId.uuidString as CKRecordValue
            tomb["updatedAt"] = Date() as CKRecordValue
            _ = try await dbSave(tomb)
            print("🪦 Upserted DeletedItem tombstone for id=\(itemId)")
        } catch {
            print("❗️Failed to upsert DeletedItem tombstone: \(error)")
            // 不阻斷：即使墓碑寫失敗，仍嘗試刪 iCloud Item
        }

        // 1) 嘗試刪除新命名規則的 recordName（"item-<uuid>"）
        let rid = CKRecord.ID(recordName: "item-\(itemId.uuidString)")
        do {
            try await privateDB.deleteRecord(withID: rid)
            print("✅ Deleted item from iCloud by recordID: \(itemId)")
        } catch let ck as CKError {
            if ck.code != .unknownItem { throw ck } // 其他錯誤直接拋出
            // unknownItem → 可能是舊命名，進入後備方案
        } catch {
            throw error
        }

        // 2) 後備：用欄位查詢把 legacy/重複的 Item 一次清乾淨
        let predicate = NSPredicate(format: "id == %@", itemId.uuidString)
        let query = CKQuery(recordType: "Item", predicate: predicate)

        var idsToDelete: [CKRecord.ID] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let page = try await performQuery(query: query, cursor: cursor)
            idsToDelete.append(contentsOf: page.records.map { $0.recordID })
            cursor = page.cursor
        } while cursor != nil

        if !idsToDelete.isEmpty {
            try await deleteRecordsInBatches(ids: Array(Set(idsToDelete)))
            print("✅ Deleted \(idsToDelete.count) legacy Item record(s) for id=\(itemId)")
        } else {
            print("ℹ️ No extra Item records found for id=\(itemId)")
        }
    }

    // MARK: - DeletedItem（墓碑）支援

    // 讀取 DeletedItem（墓碑）後，把本機相同 id 的 Item 移除
    private func pullDeletedItemsSince(_ since: Date) async throws {
        let predicate = NSPredicate(format: "updatedAt > %@", since as CVarArg)
        let query = CKQuery(recordType: "DeletedItem", predicate: predicate)
        var deletedIDs: [UUID] = []

        var cursor: CKQueryOperation.Cursor?
        repeat {
            let page = try await performQuery(query: query, cursor: cursor)
            for rec in page.records {
                if let idStr = rec["id"] as? String, let uuid = UUID(uuidString: idStr) {
                    deletedIDs.append(uuid)
                }
            }
            cursor = page.cursor
        } while cursor != nil

        guard !deletedIDs.isEmpty else { return }
        try await removeLocalItems(withIDs: Set(deletedIDs))
        lastDeletedSyncDate = Date()
    }

    // 從本機 items.json 移除指定 IDs 並落盤
    private func removeLocalItems(withIDs ids: Set<UUID>) async throws {
        var local = loadLocalItems()
        let before = local.count
        local.removeAll { ids.contains($0.id) }
        if local.count != before {
            saveLocalItems(local)
            print("🧹 Removed \(before - local.count) local item(s) by DeletedItem tombstones.")
        }
    }

    // 全量抓取 DeletedItem（給 full sync 用）
    private func pullAllDeletedItems() async throws {
        let query = CKQuery(recordType: "DeletedItem", predicate: NSPredicate(value: true))
        var deletedIDs: [UUID] = []
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let page = try await performQuery(query: query, cursor: cursor)
            for rec in page.records {
                if let idStr = rec["id"] as? String, let uuid = UUID(uuidString: idStr) {
                    deletedIDs.append(uuid)
                }
            }
            cursor = page.cursor
        } while cursor != nil
        guard !deletedIDs.isEmpty else { return }
        try await removeLocalItems(withIDs: Set(deletedIDs))
        lastDeletedSyncDate = Date()
    }

    // MARK: - CK helpers

    // 一次刪多筆紀錄，避免單筆呼叫過多導致 rate limit
    private func deleteRecordsInBatches(ids: [CKRecord.ID], batchSize: Int = 300) async throws {
        guard !ids.isEmpty else { return }
        let unique = Array(Set(ids))
        var index = 0
        while index < unique.count {
            let end = min(index + batchSize, unique.count)
            let slice = Array(unique[index..<end])

            try await withCheckedThrowingContinuation { cont in
                let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: slice)
                // 盡量溫和些
                op.isAtomic = false
                op.qualityOfService = .utility

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
        _ = localImagesDir
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
}
