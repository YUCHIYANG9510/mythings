//
//  iCloudSync.swift
//  mythings
//
//  Created by Designer on 2025/9/9.
//


//
//  CloudKitSyncManager.swift
//  mythings
//

import Foundation
import SwiftUI
import Combine
import CloudKit
import UIKit

enum iCloudSyncStatus {
    case idle
    case syncing
    case success
    case error(String)
}

final class iCloudSyncManager: ObservableObject {
    // MARK: Public state
    @Published var syncStatus: iCloudSyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "icloud.sync.enabled")
            if isEnabled { enableCloudSync() } else { disableCloudSync() }
        }
    }

    // MARK: Private
    private lazy var container = CKContainer(identifier: "iCloud.com.daisyyang.mythings.v2")
    private lazy var privateDB = container.privateCloudDatabase

    private var cancellables = Set<AnyCancellable>()
    private let fm = FileManager.default

    private var documentsDir: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var localItemsURL: URL { documentsDir.appendingPathComponent("items.json") }
    private var localCategoriesURL: URL { documentsDir.appendingPathComponent("categories.json") }
    private var localImagesDir: URL { documentsDir.appendingPathComponent("Images", isDirectory: true) }

    // Local mirror models
    private struct SimpleCategory: Codable, Identifiable, Equatable {
        let id: UUID
        var name: String
    }

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "icloud.sync.enabled")
        self.lastSyncDate = UserDefaults.standard.object(forKey: "icloud.sync.lastDate") as? Date
        if isEnabled { enableCloudSync() }
    }

    // MARK: Public API
    func manualSync() {
        guard isEnabled else { return }
        Task { @MainActor in
            syncStatus = .syncing
            do {
                try await runFullSync()
                syncStatus = .success
                updateLastSyncDate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.syncStatus = .idle
                }
            } catch {
                syncStatus = .error(error.localizedDescription)
            }
        }
    }

    func checkiCloudAvailability() -> Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    // MARK: Enable/Disable
    private func enableCloudSync() {
        // 用同一個指定容器做檢查，避免拿到 default 容器
        let container = self.container

        print("=== CloudKit Debug Info ===")
        print("Container ID: \(container.containerIdentifier ?? "nil")")
        print("App Bundle ID: \(Bundle.main.bundleIdentifier ?? "nil")")

        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                print("Account status: \(status)")
                if let error = error {
                    let nsError = error as NSError
                    print("Error domain: \(nsError.domain)")
                    print("Error code: \(nsError.code)")
                    print("Error description: \(error.localizedDescription)")
                    print("Error debug: \(nsError.debugDescription)")
                    self?.syncStatus = .error("Debug: \(nsError.domain) - \(nsError.code)")
                } else {
                    print("Account status OK: \(status)")
                }
            }
        }
    }

    private func disableCloudSync() {
        cancellables.removeAll()
    }

    // MARK: Core Sync (push local → pull remote；以 updatedAt 做 LWW)
    private func runFullSync() async throws {
        print("=== Starting Full Sync ===")
        do {
            try ensureLocalFolders()
            print("✓ Local folders ensured")

            // 載入本地資料（可能是空的）
            let items = loadLocalItems() ?? []
            let categories = loadLocalCategories() ?? []

            print("Local items count: \(items.count)")
            print("Local categories count: \(categories.count)")

            // 只有當有資料時才推送
            if !items.isEmpty {
                try await pushItems(items)
                print("✓ Items pushed")
            }
            if !categories.isEmpty {
                try await pushCategories(categories)
                print("✓ Categories pushed")
            }

            // 從雲端拉取資料
            try await pullItems()
            print("✓ Items pulled")

            try await pullCategories()
            print("✓ Categories pulled")

        } catch {
            print("❌ Sync failed: \(error)")
            throw error
        }
    }

    private func ensureLocalFolders() throws {
        if !fm.fileExists(atPath: localImagesDir.path) {
            try fm.createDirectory(at: localImagesDir, withIntermediateDirectories: true)
        }
    }

    // MARK: Local IO
    private func loadLocalItems() -> [Item]? {
        guard FileManager.default.fileExists(atPath: localItemsURL.path) else {
            print("items.json doesn't exist yet, returning empty array")
            return []
        }
        guard let data = try? Data(contentsOf: localItemsURL) else {
            print("Failed to read items.json")
            return []
        }
        return (try? JSONDecoder().decode([Item].self, from: data)) ?? []
    }

    private func saveLocalItems(_ items: [Item]) {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: localItemsURL, options: .atomic)
        } catch {
            print("Save items.json failed: \(error)")
        }
    }

    private func loadLocalCategories() -> [SimpleCategory]? {
        guard FileManager.default.fileExists(atPath: localCategoriesURL.path) else {
            print("categories.json doesn't exist yet, returning empty array")
            return []
        }
        guard let data = try? Data(contentsOf: localCategoriesURL) else {
            print("Failed to read categories.json")
            return []
        }
        return (try? JSONDecoder().decode([SimpleCategory].self, from: data)) ?? []
    }

    private func saveLocalCategories(_ cats: [SimpleCategory]) {
        do {
            let data = try JSONEncoder().encode(cats)
            try data.write(to: localCategoriesURL, options: .atomic)
        } catch {
            print("Save categories.json failed: \(error)")
        }
    }

    // MARK: Push (Local → CloudKit) using continuations (SDK 相容)
    private func pushItems(_ items: [Item]) async throws {
        for item in items {
            let rid = CKRecord.ID(recordName: "item-\(item.id.uuidString)")
            let record = try await fetchOrCreate(recordType: "Item", id: rid)

            record["id"] = item.id.uuidString as CKRecordValue
            record["brand"] = item.brand as CKRecordValue
            record["category"] = item.category as CKRecordValue
            record["name"] = item.name as CKRecordValue
            record["price"] = item.price as CKRecordValue
            if let d = item.date { record["date"] = d as CKRecordValue }
            record["updatedAt"] = Date() as CKRecordValue

            // ✅ 只有在檔案存在且不是資料夾時才上傳 CKAsset，避免 "Not a regular file"
            let imageURL = localImagesDir.appendingPathComponent(item.imageName)
            var isDir: ObjCBool = false
            if !item.imageName.isEmpty,
               fm.fileExists(atPath: imageURL.path, isDirectory: &isDir),
               !isDir.boolValue {
                record["image"] = CKAsset(fileURL: imageURL)
            } else {
                record["image"] = nil // 沒圖就不要帶
            }

            _ = try await dbSave(record)
        }
    }

    private func pushCategories(_ categories: [SimpleCategory]) async throws {
        for cat in categories {
            let rid = CKRecord.ID(recordName: "category-\(cat.id.uuidString)")
            let record = try await fetchOrCreate(recordType: "Category", id: rid)
            record["id"] = cat.id.uuidString as CKRecordValue
            record["name"] = cat.name as CKRecordValue
            record["updatedAt"] = Date() as CKRecordValue
            _ = try await dbSave(record)
        }
    }

    // MARK: Pull (CloudKit → Local) using recordMatchedBlock
    private func pullItems() async throws {
        let query = CKQuery(recordType: "Item", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: true)]

        var all: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor? = nil

        repeat {
            let page = try await performQuery(recordType: "Item", query: query, cursor: cursor)
            all.append(contentsOf: page.records)
            cursor = page.cursor
        } while cursor != nil

        var local = loadLocalItems() ?? []
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

            var downloadedName: String? = nil
            if let asset = r["image"] as? CKAsset, let fileURL = asset.fileURL {
                let targetURL = localImagesDir.appendingPathComponent(fileURL.lastPathComponent)
                if !fm.fileExists(atPath: targetURL.path) {
                    try? fm.copyItem(at: fileURL, to: targetURL)
                }
                downloadedName = targetURL.lastPathComponent // ✅ 寫回本地檔名
            }

            if let idx = local.firstIndex(where: { $0.id == uuid }) {
                local[idx] = Item(
                    id: uuid,
                    imageName: downloadedName ?? local[idx].imageName, // ✅ 更新為下載到的檔名
                    brand: brand,
                    category: category,
                    name: name,
                    price: price,
                    date: date
                )
            } else {
                let newItem = Item(
                    id: uuid,
                    imageName: downloadedName ?? "", // ✅ 新增時就寫正確檔名（或空字串）
                    brand: brand,
                    category: category,
                    name: name,
                    price: price,
                    date: date
                )
                local.append(newItem)
            }
        }
        saveLocalItems(local)
    }

    private func pullCategories() async throws {
        let query = CKQuery(recordType: "Category", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: true)]

        var all: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor? = nil

        repeat {
            let page = try await performQuery(recordType: "Category", query: query, cursor: cursor)
            all.append(contentsOf: page.records)
            cursor = page.cursor
        } while cursor != nil

        var local = loadLocalCategories() ?? []
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
    }

    // MARK: CK helpers (continuations，避免 SDK 差異造成 await 錯)
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
        do {
            return try await dbFetch(recordID: id)
        } catch {
            if let ck = error as? CKError, ck.code == .unknownItem {
                return CKRecord(recordType: recordType, recordID: id)
            }
            throw error
        }
    }

    private func performQuery(recordType: String, query: CKQuery, cursor: CKQueryOperation.Cursor?) async throws -> (records: [CKRecord], cursor: CKQueryOperation.Cursor?) {
        try await withCheckedThrowingContinuation { cont in
            let op: CKQueryOperation = {
                if let cursor { return CKQueryOperation(cursor: cursor) }
                else { return CKQueryOperation(query: query) }
            }()

            var fetched: [CKRecord] = []

            // iOS 15+ 推薦：recordMatchedBlock（取代 recordFetchedBlock）
            op.recordMatchedBlock = { recordID, result in
                switch result {
                case .success(let record):
                    fetched.append(record)
                case .failure(let err):
                    print("record \(recordID) failed: \(err)")
                }
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
}
