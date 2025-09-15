//
//  ICloudSyncSettingsView.swift
//  mythings
//

import SwiftUI

struct ICloudSyncSettingsView: View {
    @EnvironmentObject var iCloudSync: iCloudSyncManager

    @State private var showingCloudAlert = false
    @State private var cloudAlertMessage = ""

    private var lastSyncText: String {
        // 關閉同步時：固定顯示相對時間或「尚未同步」
        if !iCloudSync.isEnabled {
            if let last = iCloudSync.lastSyncDate {
                return RelativeDateTimeFormatter().localizedString(for: last, relativeTo: Date())
            } else {
                return "尚未同步"
            }
        }
        // 開啟同步時：依狀態顯示
        switch iCloudSync.syncStatus {
        case .syncing: return "正在同步…"
        case .error(_): return "發生錯誤"
        case .success, .idle:
            if let last = iCloudSync.lastSyncDate {
                return RelativeDateTimeFormatter().localizedString(for: last, relativeTo: Date())
            } else {
                return "尚未同步"
            }
        }
    }

    var body: some View {
        Form {
            Section {
                if iCloudSync.checkiCloudAvailability() {
                    Toggle("iCloud 同步", isOn: $iCloudSync.isEnabled)
                        .tint(.green)

                    HStack {
                        Text("上次同步：")
                        Spacer()
                        Text(lastSyncText)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "icloud.slash")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("iCloud 無法使用").font(.subheadline)
                            Text("請到系統「設定」登入 iCloud。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Text("在此裝置上停用同步不會在其他裝置上停用同步。如果您希望全面停止同步，請在您的每台裝置上停用同步。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("同步")
        .onReceive(iCloudSync.$syncStatus) { newStatus in
            if case .error(let message) = newStatus {
                cloudAlertMessage = message
                showingCloudAlert = true
            }
        }
        .alert("iCloud 同步", isPresented: $showingCloudAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(cloudAlertMessage)
        }
    }
}
