//
//  SettingsView.swift
//  mythings
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("isDarkMode") private var isDarkMode = false

    @ObservedObject var categoryStore: CategoryStore
    @EnvironmentObject var iCloudSync: iCloudSyncManager

    @Binding var items: [Item]
    let saveItems: () -> Void

    @State private var showingDeleteAllAlert = false
    @State private var isDeletingAll = false

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
            Section("CATEGORIES") {
                NavigationLink("Manage Categories") {
                    ManageCategoriesView(categoryStore: categoryStore)
                }
            }

            Section("APPEARANCE") {
                Toggle("Dark Mode", isOn: $isDarkMode)
            }

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
        .navigationDestination(isPresented: $navToICloud) {
            ICloudSyncSettingsView()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(pm)
        }
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

    private func deleteAllItems() {
        guard !items.isEmpty else { return }
        isDeletingAll = true

        let itemsToDelete = items
        let itemIDs = itemsToDelete.map { $0.id }

        Task {
            // ✅ CRITICAL FIX: 先同步刪除到 iCloud，再清空本地
            // 這樣可以確保墓碑記錄先被創建，避免物件重新出現
            if iCloudSync.isEnabled {
                print("🗑️ Syncing deletion of \(itemsToDelete.count) items to iCloud...")
                
                do {
                    // 使用批量刪除方法（會等待所有刪除完成）
                    try await iCloudSync.deleteAllItemsSync(itemIDs)
                    print("✅ iCloud deletion sync completed")
                } catch {
                    print("❌ iCloud deletion failed: \(error)")
                    // 即使 iCloud 刪除失敗，仍然繼續刪除本地數據
                }
            }
            
            // 現在才刪除本地數據
            await deleteAllImageFiles()
            await MainActor.run {
                items.removeAll()
                saveItems()
            }
            
            await MainActor.run { isDeletingAll = false }
            ImageCacheManager.shared.invalidateCache()
            
            print("✅ Local deletion completed")
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

// ✅ 把準備工作移到 #Preview 外，避免 result builder 型別推斷錯誤
@MainActor
private func makeSettingsPreview() -> some View {
    let store = CategoryStore()
    store.categories = [
        Category(name: "3C Device", emoji: "🎧"),
        Category(name: "Clothes", emoji: "👕")
    ]
    let sampleCategoryID = store.categories.first?.id ?? UUID()
    let sampleItems: [Item] = [
        Item(
            id: UUID(),
            imageName: "test.png",
            brand: "Apple",
            categoryID: sampleCategoryID,
            name: "AirPods",
            price: "$199",
            date: Date()
        )
    ]
    return NavigationStack {
        SettingsView(
            categoryStore: store,
            items: .constant(sampleItems),
            saveItems: { }
        )
        .environmentObject(iCloudSyncManager())
        .environmentObject(PurchasesManager())
    }
}

#Preview {
    makeSettingsPreview()
}
