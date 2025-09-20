//
//  SettingsView.swift
//  mythings
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("isDarkMode") private var isDarkMode = false

    @ObservedObject var categoryStore: CategoryStore
    @EnvironmentObject var iCloudSync: iCloudSyncManager

    // Delete All Things
    @Binding var items: [Item]
    let saveItems: () -> Void

    @State private var showingDeleteAllAlert = false
    @State private var isDeletingAll = false

    // 🔑 RevenueCat
    @EnvironmentObject var pm: PurchasesManager
    @State private var navToICloud = false
    @State private var showPaywall = false   // ← 只保留這一個

    private var isSyncing: Bool {
        if case .syncing = iCloudSync.syncStatus { return true }
        return false
    }

    var body: some View {
        Form {
            // MARK: - CATEGORIES
            Section("CATEGORIES") {
                NavigationLink("Manage Categories") {
                    ManageCategoriesView(categoryStore: categoryStore)
                }
            }

            // MARK: - APPEARANCE
            Section("APPEARANCE") {
                Toggle("Dark Mode", isOn: $isDarkMode)
            }

            // MARK: - ICLOUD
            Section("ICLOUD") {
                Button {
                    if pm.canUseICloud {
                        navToICloud = true
                    } else {
                        showPaywall = true
                    }
                } label: {
                    HStack {
                        Text("iCloud Sync")
                        if !pm.canUseICloud {
                            Spacer()
                            Text("Pro")
                                .font(.caption)
                                .padding(6)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }
            // iOS 17 的布林導航（可保留）
            .navigationDestination(isPresented: $navToICloud) {
                ICloudSyncSettingsView()
            }

            // MARK: - JOIN PRO (單一欄位卡片式)
            Section {
                JoinProCard {
                    showPaywall = true
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
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

        // 共用一個 Paywall sheet（任何地方觸發都使用這個）
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(pm)
        }

        .alert("Delete All Things", isPresented: $showingDeleteAllAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) { deleteAllItems() }
        } message: {
            Text("Are you sure you want to delete all \(items.count) items? This action cannot be undone and will also remove all images.")
        }
        .listStyle(.insetGrouped)
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

/// 參考附圖的「Join Pro」卡片
private struct JoinProCard: View {
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 16) {
                Image("Star")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Join Pro")
                        .font(.title3).fontWeight(.semibold)
                        .foregroundStyle(.white)
                    Text("Subscription or one-time purchase")
                        .foregroundStyle(.white.opacity(0.9))
                        .font(.caption)
                }

                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                    Text("Upgrade")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(hex: "62AFF7"))
                .clipShape(RoundedRectangle(cornerRadius: 100, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 100, style: .continuous)
                        .stroke(Color(hex: "BCDFFF"), lineWidth: 1)
                )

            }
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.11, green: 0.46, blue: 0.98),
                        Color(red: 0.17, green: 0.67, blue: 1.0)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var hexNumber: UInt64 = 0
        scanner.scanHexInt64(&hexNumber)

        let r = Double((hexNumber & 0xFF0000) >> 16) / 255
        let g = Double((hexNumber & 0x00FF00) >> 8) / 255
        let b = Double(hexNumber & 0x0000FF) / 255

        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    // 測試用 CategoryStore
    let previewCategoryStore = CategoryStore()
    previewCategoryStore.categories = [
        Category(name: "3C Device", emoji: "🎧"),
        Category(name: "Clothes", emoji: "👕")
    ]

    // 測試用 iCloudSyncManager
    let previewSync = iCloudSyncManager()

    // 測試用 items（常數）
    let sampleItems: [Item] = [
        Item(id: UUID(),
             imageName: "test.png",
             brand: "Apple",
             category: "3C Device",
             name: "AirPods",
             price: "$199",
             date: Date())
    ]

    return NavigationStack {
        SettingsView(
            categoryStore: previewCategoryStore,
            items: .constant(sampleItems),        // ✅ 用常數 Binding
            saveItems: { /* no-op in preview */ }
        )
        .environmentObject(previewSync)          // 注入 iCloudSync
        .environmentObject(PurchasesManager())   // 注入 PurchasesManager
    }
}

