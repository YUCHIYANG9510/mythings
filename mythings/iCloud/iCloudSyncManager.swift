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
        case (.idle, .idle),
             (.syncing, .syncing),
             (.success, .success):
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
            print("⚠️ Sync already in progress, skipping...")
            return
        }
        isRunning = true
        defer { isRunning = false }
        try await op()
    }
}

// MARK: - ImageStore：集中管理圖片路徑/存取（避免把資料夾當檔案）

struct ImageStore {
    let fm = FileManager.default
    let documentsDir: URL
    let imagesDir: URL

    init() {
        documentsDir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        imagesDir = documentsDir.appendingPathComponent("Images", isDirectory: true)
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
    }

    /// 僅保留檔名，避免把整條路徑（甚至是 "Documents"）存進資料。
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

    /// 為 CKAsset 準備臨時檔案（上傳期間檔案需存在）
    func tempUploadURL(for id: UUID, ext: String) throws -> URL {
        let tmpBase = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("Upload", isDirectory: true)
        try? fm.createDirectory(at: tmpBase, withIntermediateDirectories: true)
        return tmpBase.appendingPathComponent("\(id.uuidString).\(ext)", isDirectory: false)
    }

    /// 將來源檔複製到臨時位置，回傳 CKAsset
    func assetForUpload(from source: URL, id: UUID) throws -> CKAsset {
        let ext = (source.path as NSString).pathExtension.isEmpty ? "png" : (source.path as NSString).pathExtension
        let dst = try tempUploadURL(for: id, ext: ext)
        if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
        try fm.copyItem(at: source, to: dst)
        return CKAsset(fileURL: dst)
    }
}

// MARK: - Categories mirror

private struct SimpleCategory: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
}

// MARK: - CloudKitSyncManager
// ▶︎ A 版：整個類別掛主執行緒
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

    // Local files
    private var documentsDir: URL { imageStore.documentsDir }
    private var localItemsURL: URL { documentsDir.appendingPathComponent("items.json") }
    private var localCategoriesURL: URL { documentsDir.appendingPathComponent("categories.json") }
    private var localImagesDir: URL { imageStore.imagesDir }

    // 追蹤目前同步任務（可取消）
    private var currentSyncTask: Task<Void, Never>?

    // Lifecycle
    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "icloud.sync.enabled")
        self.lastSyncDate = UserDefaults.standard.object(forKey: "icloud.sync.lastDate") as? Date
        if isEnabled { enableCloudSync() }
    }

    // MARK: - Public API

    func manualSync() {
        guard isEnabled else { return }

        // 若先前有任務在跑，先取消（交由 gate 防止重入）
        currentSyncTask?.cancel()

        currentSyncTask = Task { [weak self] in
            guard let self else { return }
            await gate.runOnce {
                // 這裡的 Published 變更需要在主執行緒
                await MainActor.run { self.syncStatus = .syncing }
                do {
                    try await self.runFullSync()
                    await MainActor.run {
                        self.syncStatus = .success
                        self.updateLastSyncDate()
                    }
                    // 回到 idle（可選）
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    await MainActor.run { self.syncStatus = .idle }
                } catch is CancellationError {
                    await MainActor.run { self.syncStatus = .idle }
                } catch {
                    await MainActor.run { self.syncStatus = .error(error.localizedDescription) }
                }
            }

            // 任務結束後清空引用
            if !Task.isCancelled {
                await MainActor.run { [weak self] in self?.currentSyncTask = nil }
            }
        }
    }

    func checkiCloudAvailability() -> Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    // MARK: - Enable/Disable

    private func enableCloudSync() {
        let container = self.container
        print("=== CloudKit Debug Info ===")
        print("Container ID: \(container.containerIdentifier ?? "nil")")
        print("App Bundle ID: \(Bundle.main.bundleIdentifier ?? "nil")")

        container.accountStatus { [weak self] status, error in
            guard let self = self else { return }   // 👈 在 closure 一開始就解開
            DispatchQueue.main.async {
                print("Account status: \(status)")
                if let error = error {
                    let nsError = error as NSError
                    print("Error domain: \(nsError.domain)")
                    print("Error code: \(nsError.code)")
                    print("Error description: \(error.localizedDescription)")
                    self.syncStatus = .error("\(nsError.domain) - \(nsError.code)")
                } else {
                    print("Account status OK: \(status)")
                }
            }
        }
    }


    private func disableCloudSync() {
        // 取消目前同步任務（如果有）
        currentSyncTask?.cancel()
        currentSyncTask = nil

        // 若你有任何訂閱/通知，這裡也一起解除
        cancellables.removeAll()

        // 將狀態歸零，避免 UI 還顯示「正在同步」
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

    private func loadLocalCategories() -> [SimpleCategory] {
        guard fm.fileExists(atPath: localCategoriesURL.path),
              let data = try? Data(contentsOf: localCategoriesURL),
              let cats = try? JSONDecoder().decode([SimpleCategory].self, from: data) else {
            return []
        }
        return cats
    }

    private func saveLocalCategories(_ cats: [SimpleCategory]) {
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
        print("📥 Pulling from cloud first...")
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

    private func pushCategoriesWithRetry(_ categories: [SimpleCategory]) async throws {
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

        // 圖片：僅使用檔名，組出正確 URL 並確認檔案存在且非空
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

    private func pushSingleCategory(_ category: SimpleCategory) async throws {
        let rid = CKRecord.ID(recordName: "category-\(category.id.uuidString)")
        let rec = try await fetchOrCreate(recordType: "Category", id: rid)
        rec["id"] = category.id.uuidString as CKRecordValue
        rec["name"] = category.name as CKRecordValue
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
                // 使用固定命名（uuid.png），只存檔名
                finalImageName = "\(uuid.uuidString).png"
                let target = imageStore.fileURL(for: finalImageName)

                do {
                    try imageStore.ensureDirs()
                    if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }
                    try fm.copyItem(at: cloudURL, to: target)
                    print("✅ Downloaded image: \(finalImageName)")
                    // 清掉快取（若有）
                    ImageMemoryCache.shared.remove(finalImageName)
                } catch {
                    print("❌ Copy image failed: \(error)")
                    finalImageName = "" // 沒有可用圖片
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

        for r in all {
            guard
                let idStr = r["id"] as? String,
                let uuid = UUID(uuidString: idStr),
                let name = r["name"] as? String
            else { continue }

            if let idx = local.firstIndex(where: { $0.id == uuid }) {
                local[idx].name = name
            } else {
                local.append(.init(id: uuid, name: name))
            }
        }

        saveLocalCategories(local)
        print("✅ Categories pulled and saved: \(local.count)")
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
        // iOS 會保證 Documents 存在；這裡只保證 Images
        try imageStore.ensureDirs()
        // 額外驗證 Images 可寫
        guard fm.isWritableFile(atPath: localImagesDir.path) || !fm.fileExists(atPath: localImagesDir.path) else { return }
    }

    // 可在啟動時呼叫查看狀態
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
    
    /// 同步刪除操作到 iCloud
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
