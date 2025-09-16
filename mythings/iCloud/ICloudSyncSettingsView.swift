//
//  ICloudSyncSettingsView.swift
//  mythings
//

import SwiftUI
import Network

struct ICloudSyncSettingsView: View {
    @EnvironmentObject var iCloudSync: iCloudSyncManager

    // 想隱藏「網路」這列就改成 false
    private let showNetworkRow = false

    @State private var showingCloudAlert = false
    @State private var cloudAlertMessage = ""

    @StateObject private var networkMonitor = NetworkMonitor()

    // MARK: - Formatters
    private let lastSyncFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "zh_TW")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df
    }()

    // MARK: - Derived UI Text
    private var syncStatusText: String {
        guard iCloudSync.isEnabled else { return "同步已停用" }
        switch iCloudSync.syncStatus {
        case .syncing: return "正在同步…"
        case .success: return "同步成功"
        case .idle:
            return (iCloudSync.lastSyncDate == nil) ? "尚未同步" : "待命中"
        case .error: return "發生錯誤"
        }
    }

    private var lastSyncText: String {
        if let last = iCloudSync.lastSyncDate {
            return lastSyncFormatter.string(from: last)
        } else {
            return "—"
        }
    }

    private var footerText: String {
        if iCloudSync.isEnabled {
            // 參考你第一張截圖下方的文字
            return "iCloud 網路波動較大，如 iCloud 同步失敗，請耐心等待，或者在 iOS 系統設定頁面的 Apple ID 頁面中，檢查 iCloud 服務狀態，必要時也可重啟應用。"
        } else {
            // 參考你第二張截圖下方的文字
            return "iCloud 同步已停用。您的資料將僅儲存在本機，不會在裝置間同步。協作空間功能也將無法使用。啟用同步並重新啟動應用程式以恢復完整功能。"
        }
    }

    var body: some View {
        Form {
            // MARK: - 開關
            Section {
                Toggle("啟用 iCloud 同步", isOn: $iCloudSync.isEnabled)
                    .tint(.green)
            }

            // MARK: - 狀態區
            if iCloudSync.isEnabled {
                Section {
                    // 同步狀態
                    HStack {
                        Text("同步狀態")
                        Spacer()
                        Text(syncStatusText)
                            .foregroundStyle(.secondary)
                    }

                    // 網路（可選）
                    if showNetworkRow {
                        HStack {
                            Text("網路")
                            Spacer()
                            Text(networkMonitor.isOnline ? "可用" : "不可用")
                                .foregroundStyle(.secondary)
                        }
                    }

                    // 上次同步時間
                    HStack {
                        Text("上次同步時間")
                        Spacer()
                        Text(lastSyncText)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } else {
                // 關閉同步時只顯示狀態與 iCloud 服務不可用提示（如果需要）
                Section {
                    HStack {
                        Text("同步狀態")
                        Spacer()
                        Text("同步已停用")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: - 說明
            Section {
                Text(footerText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("iCloud Sync")
        .onAppear {
                    iCloudSync.kickoffIfNeeded()
                }
        .onChange(of: iCloudSync.isEnabled) {
            iCloudSync.kickoffIfNeeded()
        }
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
        .onAppear { networkMonitor.start() }
        .onDisappear { networkMonitor.stop() }
    }
}

// MARK: - 簡易網路監控（可移到別檔）
final class NetworkMonitor: ObservableObject {
    @Published var isOnline: Bool = true
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "net.mon.queue")

    func start() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = (path.status == .satisfied)
            }
        }
        m.start(queue: queue)
        monitor = m
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }
}
