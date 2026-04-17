//
//  ICloudSyncSettingsView.swift
//  mythings
//

import SwiftUI

struct ICloudSyncSettingsView: View {
    @EnvironmentObject var iCloudSync: iCloudSyncManager
    
    // 🌐 監聽語言變更
    @ObservedObject private var localizationManager = LocalizationManager.shared

    @State private var showingCloudAlert = false
    @State private var cloudAlertMessage = ""

    // MARK: - Formatters
    private var lastSyncFormatter: DateFormatter {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = localizationManager.locale
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df
    }

    // MARK: - Derived UI Text
    private var syncStatusText: String {
        guard iCloudSync.isEnabled else { return L("sync_disabled") }
        switch iCloudSync.syncStatus {
        case .syncing: return L("syncing")
        case .success: return L("sync_successful")
        case .idle:
            return (iCloudSync.lastSyncDate == nil) ? L("not_synced_yet") : L("idle")
        case .error: return L("error_occurred")
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
            // Footer text when sync is enabled
            return L("icloud_sync_enabled_footer")
        } else {
            // Footer text when sync is disabled
            return L("icloud_sync_disabled_footer")
        }
    }

    var body: some View {
        Form {
            // MARK: - Toggle Switch
            Section {
                Toggle(L("enable_icloud_sync"), isOn: $iCloudSync.isEnabled)
                    .tint(.green)
            }

            // MARK: - Status Section
            if iCloudSync.isEnabled {
                Section {
                    // Sync Status
                    HStack {
                        Text(L("sync_status"))
                        Spacer()
                        Text(syncStatusText)
                            .foregroundStyle(.secondary)
                    }

                    // Last Sync Time
                    HStack {
                        Text(L("last_sync_time"))
                        Spacer()
                        Text(lastSyncText)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } else {
                // When sync is disabled, only show status
                Section {
                    HStack {
                        Text(L("sync_status"))
                        Spacer()
                        Text(L("sync_disabled"))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: - Description
            Section {
                Text(footerText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle(L("icloud_sync_title"))
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
        .alert(L("icloud_sync_alert_title"), isPresented: $showingCloudAlert) {
            Button(L("ok"), role: .cancel) { }
        } message: {
            Text(cloudAlertMessage)
        }
    }
}
