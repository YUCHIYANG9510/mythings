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
    @StateObject private var iCloudSync = iCloudSyncManager()
    @State private var showingCloudAlert = false
    @State private var cloudAlertMessage = ""

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
                    // 尚未實作
                }
                .foregroundColor(.red)
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
}
