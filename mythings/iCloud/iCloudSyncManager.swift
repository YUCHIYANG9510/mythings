//
//  iCloudSync.swift
//  mythings
//
//  Created by Designer on 2025/9/9.
//

import Foundation
import SwiftUI
import Combine

enum iCloudSyncStatus {
    case idle
    case syncing
    case success
    case error(String)
}

class iCloudSyncManager: ObservableObject {
    @Published var syncStatus: iCloudSyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "icloud.sync.enabled")
            if isEnabled {
                enableiCloudSync()
            } else {
                disableiCloudSync()
            }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    private let fileManager = FileManager.default
    
    // 取得 Documents 目錄
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    // 本地文件路徑
    private var localItemsURL: URL {
        documentsDirectory.appendingPathComponent("items.json")
    }
    
    private var localCategoriesURL: URL {
        documentsDirectory.appendingPathComponent("categories.json")
    }
    
    // iCloud 容器路徑
    private var iCloudItemsURL: URL? {
        guard let containerURL = fileManager.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        return containerURL.appendingPathComponent("Documents/items.json")
    }
    
    private var iCloudCategoriesURL: URL? {
        guard let containerURL = fileManager.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        return containerURL.appendingPathComponent("Documents/categories.json")
    }
    
    // iCloud 圖片資料夾
    private var iCloudImagesURL: URL? {
        guard let containerURL = fileManager.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        return containerURL.appendingPathComponent("Documents/Images/")
    }
    
    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "icloud.sync.enabled")
        self.lastSyncDate = UserDefaults.standard.object(forKey: "icloud.sync.lastDate") as? Date
        
        if isEnabled {
            enableiCloudSync()
        }
    }
    
    // MARK: - Public Methods
    
    func manualSync() {
        guard isEnabled else { return }
        
        Task { @MainActor in
            syncStatus = .syncing
            
            do {
                try await performSync()
                syncStatus = .success
                updateLastSyncDate()
                
                // 3秒後重置狀態
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.syncStatus = .idle
                }
            } catch {
                syncStatus = .error(error.localizedDescription)
            }
        }
    }
    
    func checkiCloudAvailability() -> Bool {
        return fileManager.url(forUbiquityContainerIdentifier: nil) != nil
    }
    
    // MARK: - Private Methods
    
    private func enableiCloudSync() {
        guard checkiCloudAvailability() else {
            syncStatus = .error("iCloud is not available")
            return
        }
        
        // 監聽 iCloud 文件變化
        startMonitoring()
        
        // 首次啟用時進行同步
        manualSync()
    }
    
    private func disableiCloudSync() {
        cancellables.removeAll()
    }
    
    private func startMonitoring() {
        // 監聽 iCloud 文件變化的通知
        NotificationCenter.default
            .publisher(for: .NSMetadataQueryDidUpdate)
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleiCloudUpdate()
            }
            .store(in: &cancellables)
    }
    
    private func handleiCloudUpdate() {
        guard isEnabled else { return }
        
        Task { @MainActor in
            do {
                try await performSync()
            } catch {
                print("Auto sync failed: \(error)")
            }
        }
    }
    
    @MainActor
    private func performSync() async throws {
        // 1. 確保 iCloud 目錄存在
        try createiCloudDirectories()
        
        // 2. 同步 items.json
        try await syncItemsFile()
        
        // 3. 同步 categories.json
        try await syncCategoriesFile()
        
        // 4. 同步圖片文件
        try await syncImages()
    }
    
    private func createiCloudDirectories() throws {
        guard let iCloudImagesURL = iCloudImagesURL else {
            throw iCloudSyncError.iCloudUnavailable
        }
        
        if !fileManager.fileExists(atPath: iCloudImagesURL.path) {
            try fileManager.createDirectory(at: iCloudImagesURL, withIntermediateDirectories: true)
        }
    }
    
    private func syncItemsFile() async throws {
        guard let iCloudURL = iCloudItemsURL else {
            throw iCloudSyncError.iCloudUnavailable
        }
        
        try await syncFile(local: localItemsURL, iCloud: iCloudURL)
    }
    
    private func syncCategoriesFile() async throws {
        guard let iCloudURL = iCloudCategoriesURL else {
            throw iCloudSyncError.iCloudUnavailable
        }
        
        try await syncFile(local: localCategoriesURL, iCloud: iCloudURL)
    }
    
    private func syncFile(local: URL, iCloud: URL) async throws {
        let localExists = fileManager.fileExists(atPath: local.path)
        let iCloudExists = fileManager.fileExists(atPath: iCloud.path)
        
        if !localExists && !iCloudExists {
            return // 兩邊都沒有文件
        }
        
        if localExists && !iCloudExists {
            // 本地有，iCloud 沒有 -> 上傳到 iCloud
            try fileManager.copyItem(at: local, to: iCloud)
        } else if !localExists && iCloudExists {
            // iCloud 有，本地沒有 -> 下載到本地
            try fileManager.copyItem(at: iCloud, to: local)
        } else {
            // 兩邊都有 -> 比較修改時間
            let localDate = try fileManager.attributesOfItem(atPath: local.path)[.modificationDate] as? Date ?? .distantPast
            let iCloudDate = try fileManager.attributesOfItem(atPath: iCloud.path)[.modificationDate] as? Date ?? .distantPast
            
            if localDate > iCloudDate {
                // 本地更新 -> 上傳到 iCloud
                try fileManager.removeItem(at: iCloud)
                try fileManager.copyItem(at: local, to: iCloud)
            } else if iCloudDate > localDate {
                // iCloud 更新 -> 下載到本地
                try fileManager.removeItem(at: local)
                try fileManager.copyItem(at: iCloud, to: local)
            }
        }
    }
    
    private func syncImages() async throws {
        guard let iCloudImagesURL = iCloudImagesURL else {
            throw iCloudSyncError.iCloudUnavailable
        }
        
        let localImagesURL = documentsDirectory.appendingPathComponent("Images")
        
        // 確保本地圖片目錄存在
        if !fileManager.fileExists(atPath: localImagesURL.path) {
            try fileManager.createDirectory(at: localImagesURL, withIntermediateDirectories: true)
        }
        
        // 同步本地到 iCloud
        let localImages = try fileManager.contentsOfDirectory(at: localImagesURL, includingPropertiesForKeys: nil)
        for localImage in localImages {
            let iCloudImage = iCloudImagesURL.appendingPathComponent(localImage.lastPathComponent)
            
            if !fileManager.fileExists(atPath: iCloudImage.path) {
                try fileManager.copyItem(at: localImage, to: iCloudImage)
            }
        }
        
        // 同步 iCloud 到本地
        let iCloudImages = try fileManager.contentsOfDirectory(at: iCloudImagesURL, includingPropertiesForKeys: nil)
        for iCloudImage in iCloudImages {
            let localImage = localImagesURL.appendingPathComponent(iCloudImage.lastPathComponent)
            
            if !fileManager.fileExists(atPath: localImage.path) {
                try fileManager.copyItem(at: iCloudImage, to: localImage)
            }
        }
    }
    
    private func updateLastSyncDate() {
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: "icloud.sync.lastDate")
    }
}

enum iCloudSyncError: LocalizedError {
    case iCloudUnavailable
    case syncFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud is not available. Please check your iCloud settings."
        case .syncFailed(let message):
            return "Sync failed: \(message)"
        }
    }
}
