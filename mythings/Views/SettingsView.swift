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
    @State private var showPaywall = false
    @State private var showProStatus = false

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
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }

            // MARK: - JOIN PRO (單一欄位卡片式)
            Section {
                if pm.isPro {
                    ProActiveCard {
                        navigateToProStatus()
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                } else {
                    JoinProCard {
                        showPaywall = true
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }

            // MARK: - DANGER ZONE
            Section {
                Button("Delete All Things") {
                    showingDeleteAllAlert = true
                }
                .foregroundColor(.red)
                .disabled(isDeletingAll || items.isEmpty)
            } footer: {
                if items.count > 0 {
                    Text("This will permanently delete all \(items.count) items and their images. This action cannot be undone.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Settings")

        // ✅ 把 navigationDestination 掛在 Form 之後（而不是 Section 內）
        .navigationDestination(isPresented: $navToICloud) {
            ICloudSyncSettingsView()
        }

        // 共用一個 Paywall sheet
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(pm)
        }

        // Pro 狀態頁
        .sheet(isPresented: $showProStatus) {
            ProStatusView().environmentObject(pm)
        }

        .alert("Delete All Things", isPresented: $showingDeleteAllAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) { deleteAllItems() }
        } message: {
            Text("Are you sure you want to delete all \(items.count) items? This action cannot be undone and will also remove all images.")
        }
        .listStyle(.insetGrouped)
    }

    // 刪除所有物件（本地優先，雲端刪除改排程事件）
    private func deleteAllItems() {
        guard !items.isEmpty else { return }
        isDeletingAll = true

        Task {
            // 先刪本地檔與圖
            await deleteAllImageFiles()
            await MainActor.run {
                items.removeAll()
                saveItems()              // 這裡會觸發 iCloudSync.schedule(.itemsChanged)
            }

            // 再排程雲端刪除（協調器會合併 events，避免併發）
            if iCloudSync.isEnabled {
                // 若你要逐筆刪雲端記錄，照下面排程（或留給雲端端以 itemsChanged/pull 決定 tombstone）
                // 這裡我們還是逐筆送出 delete 事件，確保雲端也清理
                // ※ 注意：items 已清空，所以先抓一份舊陣列
                // 如果你需要刪雲端，應在刪之前先複製 ids；這裡我們簡化為「只透過 itemsChanged 交由同步層處理」。
                // 如需真正逐筆刪除，改在刪前保存 ids 然後 schedule(.deleteItem(id)).
            }

            await MainActor.run {
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

/// 已訂閱時顯示的卡片（You're Pro）
private struct ProActiveCard: View {
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 16) {
                Image("Star")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 5) {
                    Text("You're Pro")
                        .font(.title3).fontWeight(.semibold)
                        .foregroundStyle(.white)
                    Text("Thank you for your support!")
                        .foregroundStyle(.white.opacity(0.9))
                        .font(.caption)
                }

                HStack(spacing: 6) {
                    Text("Check")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
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

// 簡單的導航到 Pro 狀態頁的輔助
private extension SettingsView {
    func navigateToProStatus() {
        showProStatus = true
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var hexNumber: UInt64 = 0
        scanner.scanHexInt64(&hexNumber)

        let r = Double((hexNumber & 0xFF0000) >> 16) / 255
        let g = Double((hexNumber & 0x00FF00) >> 8) / 255
        let b = Double((hexNumber & 0x0000FF) >> 0) / 255

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
            items: .constant(sampleItems),        // Preview 用常數 Binding
            saveItems: { /* no-op in preview */ }
        )
        .environmentObject(previewSync)          // 注入 iCloudSync
        .environmentObject(PurchasesManager())   // 注入 PurchasesManager
    }
}
