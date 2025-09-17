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

// 不再使用簡化的 SimpleCategory；改用專案內的 Category（含 emoji）

// MARK: - CloudKitSyncManager
@MainActor
final class iCloudSyncManager: ObservableObject {
    // Public state
    @Published var syncStatus: iCloudSyncStatus = .idle
    @Published var lastSyncDate: Date?
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

    // 正規化分類名稱作為唯一 Key（避免同名多筆）
    private func normalizeCategoryKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // Lifecycle
    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "icloud.sync.enabled")
        self.lastSyncDate = UserDefaults.standard.object(forKey: "icloud.sync.lastDate") as? Date
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
                    try await self.runFullSync()
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
                    await MainActor.run { self.syncStatus = .error(error.localizedDescription) }
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
                    let ns = error as NSError
                    print("AccountStatus error: \(ns.domain) \(ns.code) \(ns.localizedDescription)")
                    self.syncStatus = .error("\(ns.domain) - \(ns.code)")
                    return
                }
                print("Account status: \(status.rawValue)")
                if status == .available {
                    // 等 300ms 讓 iCloud/網路就緒，再觸發
                    Task { [weak self] in
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            await MainActor.run { [weak self] in
                                self?.kickoffIfNeeded()
                            }
                        }
                }
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

    // MARK: - Core Sync

    private func runFullSync() async throws {
        print("=== Starting Full Sync ===")
        try Task.checkCancellation()

        try ensureLocalFolders()
        print("✓ Local folders ensured")

        // Pull → Push → Pull
        print("📥 Pulling from cloud first…")
        try Task.checkCancellation()
        try await pullItems()
        try Task.checkCancellation()
        try await pullCategories()
        print("✓ Cloud data pulled")

        try Task.checkCancellation()
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
        print("✓ Final sync completed")
    }

    // MARK: - Push with retry

    private func pushItemsWithRetry(_ items: [Item]) async throws {
        for item in items {
            try Task.checkCancellation()
            var attempts = 0
            while true {
                do {
                    try await pushSingleItem(item)
                    break
                } catch let e as CKError where e.code == .serverRecordChanged && attempts < 2 {
                    attempts += 1
                    try await Task.sleep(nanoseconds: UInt64(400_000_000 * attempts))
                } catch {
                    throw error
                }
            }
        }
    }

    private func pushCategoriesWithRetry(_ categories: [Category]) async throws {
        // 在推送前先做一次雲端清理：把不在本機名單內的同名分類刪除，多餘重複也清掉
        try await cleanupAndDeleteRemoteCategories(notInLocal: Set(categories.map { normalizeCategoryKey($0.name) }))

        for cat in categories {
            try Task.checkCancellation()
            var attempts = 0
            while true {
                do {
                    try await pushSingleCategory(cat)
                    break
                } catch let e as CKError where e.code == .serverRecordChanged && attempts < 2 {
                    attempts += 1
                    print("⚠️ serverRecordChanged, retry \(attempts) for category \(cat.name)")
                    try await Task.sleep(nanoseconds: UInt64(400_000_000 * attempts))
                } catch {
                    throw error
                }
            }
        }
    }

    // MARK: - Push one item

    private func pushSingleItem(_ item: Item) async throws {
        let rid = CKRecord.ID(recordName: "item-\(item.id.uuidString)")
        let rec = try await fetchOrCreate(recordType: "Item", id: rid)

        rec["id"] = item.id.uuidString as CKRecordValue
        rec["brand"] = item.brand as CKRecordValue
        rec["category"] = item.category as CKRecordValue
        rec["name"] = item.name as CKRecordValue
        rec["price"] = item.price as CKRecordValue
        if let d = item.date { rec["date"] = d as CKRecordValue }
        rec["updatedAt"] = Date() as CKRecordValue

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

    private func pushSingleCategory(_ category: Category) async throws {
        // 以名稱作為唯一鍵，避免兩裝置產生不同 UUID 而重複
        let key = normalizeCategoryKey(category.name)
        let rid = CKRecord.ID(recordName: "category-name-\(key)")
        let rec = try await fetchOrCreate(recordType: "Category", id: rid)
        rec["id"] = category.id.uuidString as CKRecordValue
        rec["name"] = category.name as CKRecordValue
        if !category.emoji.isEmpty { rec["emoji"] = category.emoji as CKRecordValue } else { rec["emoji"] = nil }
        rec["updatedAt"] = Date() as CKRecordValue
        _ = try await dbSave(rec)
    }

    // MARK: - Pull

    private func pullItems() async throws {
        let query = CKQuery(recordType: "Item", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: true)]

        var all: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let page = try await performQuery(query: query, cursor: cursor)
            all.append(contentsOf: page.records)
            cursor = page.cursor
        } while cursor != nil

        var local = loadLocalItems()

        for r in all {
            guard
                let idStr = r["id"] as? String,
                let uuid = UUID(uuidString: idStr),
                let brand = r["brand"] as? String,
                let category = r["category"] as? String,
                let name = r["name"] as? String,
                let price = r["price"] as? String
            else { continue }

            let date = r["date"] as? Date
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
        }

        saveLocalItems(local)
        print("✅ Items pulled and saved: \(local.count)")
    }

    private func pullCategories() async throws {
        let query = CKQuery(recordType: "Category", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: true)]

        var all: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let page = try await performQuery(query: query, cursor: cursor)
            all.append(contentsOf: page.records)
            cursor = page.cursor
        } while cursor != nil

        var local = loadLocalCategories()

        // 暫存依名稱去重：保留最新 updatedAt 的一筆
        var nameToBest: [String: (Category, Date?, CKRecord.ID)] = [:]
        for r in all {
            guard
                let idStr = r["id"] as? String,
                let uuid = UUID(uuidString: idStr),
                let name = r["name"] as? String
            else { continue }

            let emoji = (r["emoji"] as? String) ?? ""
            let updatedAt = r["updatedAt"] as? Date
            let key = normalizeCategoryKey(name)

            let candidate = Category(id: uuid, name: name, emoji: emoji)
            if let exist = nameToBest[key] {
                let existingDate = exist.1 ?? .distantPast
                let newDate = updatedAt ?? .distantPast
                if newDate >= existingDate {
                    nameToBest[key] = (candidate, updatedAt, r.recordID)
                }
            } else {
                nameToBest[key] = (candidate, updatedAt, r.recordID)
            }
        }

        // 雲端清理：刪除同名的舊紀錄（保留最新），並刪除非標準鍵（舊 UUID 型）重複
        try await cleanupDuplicateCategoryRecords(allRecords: all, keepKeys: Set(nameToBest.values.map { $0.2 }))

        // 將雲端（去重後）合併進本地：同名以雲端為準；不同名保留本地
        var merged: [Category] = []
        var usedIds = Set<UUID>()

        // 先放入雲端的唯一集合
        for (_, value) in nameToBest {
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

        // 排序：名字排序，穩定輸出
        merged.sort { $0.name.lowercased() < $1.name.lowercased() }

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
