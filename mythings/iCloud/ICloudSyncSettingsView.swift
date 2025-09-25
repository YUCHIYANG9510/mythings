//
//  ICloudSyncSettingsView.swift
//  mythings
//

import SwiftUI
import Network

struct ICloudSyncSettingsView: View {
    @EnvironmentObject var iCloudSync: iCloudSyncManager

    // Set to false to hide the "Network" row
    private let showNetworkRow = false

    @State private var showingCloudAlert = false
    @State private var cloudAlertMessage = ""

    @StateObject private var networkMonitor = NetworkMonitor()

    // MARK: - Formatters
    private let lastSyncFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df
    }()

    // MARK: - Derived UI Text
    private var syncStatusText: String {
        guard iCloudSync.isEnabled else { return "Sync Disabled" }
        switch iCloudSync.syncStatus {
        case .syncing: return "Syncing…"
        case .success: return "Sync Successful"
        case .idle:
            return (iCloudSync.lastSyncDate == nil) ? "Not Synced Yet" : "Idle"
        case .error: return "Error Occurred"
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
            return "iCloud network can be unstable. If iCloud sync fails, please be patient, or check the iCloud service status in your Apple ID settings in iOS System Settings. You may also restart the app if necessary."
        } else {
            // Footer text when sync is disabled
            return "iCloud sync is disabled. Your data will only be stored locally and will not sync between devices. Collaboration space features will also be unavailable. Enable sync and restart the app to restore full functionality."
        }
    }

    var body: some View {
        Form {
            // MARK: - Toggle Switch
            Section {
                Toggle("Enable iCloud Sync", isOn: $iCloudSync.isEnabled)
                    .tint(.green)
            }

            // MARK: - Status Section
            if iCloudSync.isEnabled {
                Section {
                    // Sync Status
                    HStack {
                        Text("Sync Status")
                        Spacer()
                        Text(syncStatusText)
                            .foregroundStyle(.secondary)
                    }

                    // Network (optional)
                    if showNetworkRow {
                        HStack {
                            Text("Network")
                            Spacer()
                            Text(networkMonitor.isOnline ? "Available" : "Unavailable")
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Last Sync Time
                    HStack {
                        Text("Last Sync Time")
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
                        Text("Sync Status")
                        Spacer()
                        Text("Sync Disabled")
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
        .alert("iCloud Sync", isPresented: $showingCloudAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(cloudAlertMessage)
        }
        .onAppear { networkMonitor.start() }
        .onDisappear { networkMonitor.stop() }
    }
}

// MARK: - Simple Network Monitor (can be moved to separate file)
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
