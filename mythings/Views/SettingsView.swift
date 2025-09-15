//
//  SettingsView.swift
//  mythings
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var defaultCategory = "All"
    @State private var selectedAppIcon = "Default"

    @ObservedObject var categoryStore: CategoryStore

    // ⬇️ 改這裡：用 EnvironmentObject 拿 iCloudSync
    @EnvironmentObject var iCloudSync: iCloudSyncManager

    // Delete All Things 相關
    @Binding var items: [Item]
    let saveItems: () -> Void
    @State private var showingDeleteAllAlert = false
    @State private var isDeletingAll = false

    let appIcons = ["Default", "Minimal", "Colorful"]

    private var isSyncing: Bool {
        if case .syncing = iCloudSync.syncStatus { return true }
        return false
    }

    var body: some View {
        Form {
            // MARK: - ICLOUD
            Section("ICLOUD") {
                NavigationLink("iCloud Sync") {
                    // ⬇️ 不再傳入參數，子頁也用 EnvironmentObject
                    ICloudSyncSettingsView()
                }
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
                    ForEach(appIcons, id: \.self) { Text($0) }
                }
            }

            // MARK: - SUPPORT
            Section("SUPPORT") {
                Button("Rate on App Store") { }
                    .foregroundColor(.blue)

                Button("Subscribe to My Things Pro") { }
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
        .alert("Delete All Things", isPresented: $showingDeleteAllAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) { deleteAllItems() }
        } message: {
            Text("Are you sure you want to delete all \(items.count) items? This action cannot be undone and will also remove all images.")
        }
    }

    // 刪除所有物件
    private func deleteAllItems() {
        guard !items.isEmpty else { return }
        isDeletingAll = true

        Task {
            if iCloudSync.isEnabled {
                for item in items {
                    await iCloudSync.syncDeletion(for: item.id)
                }
            }

            await deleteAllImageFiles()

            await MainActor.run {
                items.removeAll()
                saveItems()
                isDeletingAll = false
            }

            ImageCacheManager.shared.invalidateCache()
        }
    }

    private func deleteAllImageFiles() async {
        let imagesDir = FileManager.imagesDirectory
        do {
            let fileManager = FileManager.default
            let imageFiles = try fileManager.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil)
            for fileURL in imageFiles { try? fileManager.removeItem(at: fileURL) }
            print("✅ Deleted all image files")
        } catch {
            print("❌ Error deleting image files: \(error)")
        }
    }
}
