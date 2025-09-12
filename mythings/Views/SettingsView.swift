//
//  SettingsView.swift
//  mythings
//
//  Created by Designer on 2025/5/2.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var defaultCategory = "All"
    @State private var selectedAppIcon = "Default"
    @ObservedObject var categoryStore: CategoryStore
    @ObservedObject var iCloudSync: iCloudSyncManager  // ✅ 修正：改為 @ObservedObject
    @State private var showingCloudAlert = false
    @State private var cloudAlertMessage = ""
    
    // ✅ 新增：Delete All Things 相關參數
    @Binding var items: [Item]
    let saveItems: () -> Void
    @State private var showingDeleteAllAlert = false
    @State private var isDeletingAll = false

    let appIcons = ["Default", "Minimal", "Colorful"]
    
    // 計算屬性來檢查是否正在同步
    private var isSyncing: Bool {
        if case .syncing = iCloudSync.syncStatus {
            return true
        }
        return false
    }

    var body: some View {
        Form {
            // MARK: - ICLOUD SYNC
            Section {
                if iCloudSync.checkiCloudAvailability() {
                    Toggle("iCloud Sync", isOn: $iCloudSync.isEnabled)
                    
                    if iCloudSync.isEnabled {
                        HStack {
                            Text("Status")
                            Spacer()
                            syncStatusView
                        }
                        
                        if let lastSync = iCloudSync.lastSyncDate {
                            HStack {
                                Text("Last Sync")
                                Spacer()
                                Text(lastSync, style: .relative)
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                        
                        Button("Sync Now") {
                            iCloudSync.manualSync()
                        }
                        .disabled(isSyncing)
                    }
                } else {
                    HStack {
                        Image(systemName: "icloud.slash")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("iCloud Unavailable")
                                .font(.subheadline)
                            Text("Please sign in to iCloud in Settings")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("ICLOUD SYNC")
            }
            
            if iCloudSync.isEnabled {
                Text("Your items and images will be synced across all your devices.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .listRowBackground(Color.clear)
            }
            
            // MARK: - CATEGORIES
            Section("CATEGORIES") {
                NavigationLink("Manage Categories") {
                    ManageCategoriesView(categoryStore: categoryStore)
                }
            }
            
            // MARK: - APPEARANCE
            Section("APPEARANCE") {
                Toggle("Dark Mode", isOn: $isDarkMode)
                
                Picker("App Icon", selection: $selectedAppIcon) {
                    ForEach(appIcons, id: \.self) { icon in
                        Text(icon)
                    }
                }
            }
            
            // MARK: - SUPPORT
            Section("SUPPORT") {
                Button("Rate on App Store") {
                    // 尚未實作
                }
                .foregroundColor(.blue)
                
                Button("Subscribe to My Things Pro") {
                    // 尚未實作
                }
                .foregroundColor(.blue)
            }
            
            // MARK: - DANGER ZONE
            Section {
                Button("Delete All Things") {
                    showingDeleteAllAlert = true
                }
                .foregroundColor(.red)
                .disabled(isDeletingAll)
            } footer: {
                if items.count > 0 {
                    Text("This will permanently delete all \(items.count) items and their images. This action cannot be undone.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .alert("iCloud Sync", isPresented: $showingCloudAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(cloudAlertMessage)
        }
        .onReceive(iCloudSync.$syncStatus) { newStatus in
            if case .error(let message) = newStatus {
                cloudAlertMessage = message
                showingCloudAlert = true
            }
        }
        .alert("Delete All Things", isPresented: $showingDeleteAllAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                deleteAllItems()
            }
        } message: {
            Text("Are you sure you want to delete all \(items.count) items? This action cannot be undone and will also remove all images.")
        }
    }
    
    @ViewBuilder
    private var syncStatusView: some View {
        switch iCloudSync.syncStatus {
        case .idle:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.icloud")
                    .foregroundColor(.green)
                Text("Ready")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
        case .syncing:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Syncing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
        case .success:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.icloud.fill")
                    .foregroundColor(.green)
                Text("Synced")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            
        case .error(_):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.icloud")
                    .foregroundColor(.red)
                Text("Error")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
    
    // ✅ 修正：刪除所有物件的功能
    private func deleteAllItems() {
        guard !items.isEmpty else { return }
        
        isDeletingAll = true
        
        Task {
            // 1. 同步刪除到 iCloud（如果啟用）
            if iCloudSync.isEnabled {
                for item in items {
                    await iCloudSync.syncDeletion(for: item.id)  // ✅ 修正：直接調用
                }
            }
            
            // 2. 刪除本地圖片檔案
            await deleteAllImageFiles()
            
            // 3. 清空本地物件陣列
            await MainActor.run {
                items.removeAll()
                saveItems()
                isDeletingAll = false
            }
            
            // 4. 清除圖片快取
            ImageCacheManager.shared.invalidateCache()
        }
    }
    
    // ✅ 新增：刪除所有圖片檔案
    private func deleteAllImageFiles() async {
        let imagesDir = FileManager.imagesDirectory
        
        do {
            let fileManager = FileManager.default
            let imageFiles = try fileManager.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil)
            
            for fileURL in imageFiles {
                try? fileManager.removeItem(at: fileURL)
            }
            
            print("✅ Deleted all image files")
        } catch {
            print("❌ Error deleting image files: \(error)")
        }
    }
}
