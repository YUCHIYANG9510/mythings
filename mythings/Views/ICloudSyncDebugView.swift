//
//  ICloudSyncDebugView.swift
//  mythings
//
//  Created by Designer on 2025/9/24.
//


import SwiftUI

struct ICloudSyncDebugView: View {
    @EnvironmentObject private var iCloudSync: iCloudSyncManager

    @State private var itemCount: Int?
    @State private var categoryCount: Int?
    @State private var working = false
    @State private var log: [String] = []

    var body: some View {
        List {
            Section("Cloud Counts (Private DB)") {
                HStack {
                    Text("Items")
                    Spacer()
                    Text(itemCount.map(String.init) ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Categories")
                    Spacer()
                    Text(categoryCount.map(String.init) ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Button(action: refreshCounts) {
                    Label("Refresh Counts", systemImage: "arrow.clockwise")
                }
                .disabled(working)
            }

            Section("Cloud Maintenance") {
                Button(role: .destructive) {
                    Task { await purgeItems() }
                } label: {
                    Label("Purge ALL Items (Cloud)", systemImage: "trash")
                }
                .disabled(working)

                Button(role: .destructive) {
                    Task { await purgeCategories() }
                } label: {
                    Label("Purge ALL Categories (Cloud)", systemImage: "trash")
                }
                .disabled(working)

                Button(role: .destructive) {
                    Task { await purgeAllCloud() }
                } label: {
                    Label("Purge EVERYTHING (Cloud)", systemImage: "trash.slash")
                }
                .disabled(working)
            }

            Section("Local Maintenance") {
                Button(role: .destructive) {
                    iCloudSync.wipeLocalStore()
                } label: {
                    Label("Wipe Local Store (JSON + Images)", systemImage: "folder.badge.minus")
                }
                .disabled(working)

                Button {
                    iCloudSync.schedule(.full)
                } label: {
                    Label("Schedule Full Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(working)
            }

            Section("Log") {
                ForEach(log.indices, id: \.self) { i in
                    Text(log[i]).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if working {
                ProgressView().padding().background(.ultraThinMaterial, in: Capsule())
                    .padding()
            }
        }
        .navigationTitle("iCloud Debug")
        .onAppear { refreshCounts() }
    }

    private func refreshCounts() {
        working = true
        Task {
            let (i, c) = await iCloudSync.countAllRecords()
            await MainActor.run {
                itemCount = i
                categoryCount = c
                working = false
                prepend("Counts → Items: \(i), Categories: \(c)")
            }
        }
    }

    private func purgeItems() async {
        working = true
        await iCloudSync.purgeAllItemsCloud()
        await MainActor.run { prepend("Purged all Items (cloud).") }
        refreshCounts()
    }

    private func purgeCategories() async {
        working = true
        await iCloudSync.purgeAllCategoriesCloud()
        await MainActor.run { prepend("Purged all Categories (cloud).") }
        refreshCounts()
    }

    private func purgeAllCloud() async {
        working = true
        await iCloudSync.purgeAllCloud()
        await MainActor.run { prepend("Purged EVERYTHING (cloud).") }
        refreshCounts()
    }

    @MainActor
    private func prepend(_ s: String) {
        log.insert("• \(s)", at: 0)
    }
}

#Preview {
    NavigationStack {
        ICloudSyncDebugView()
            .environmentObject(iCloudSyncManager())
    }
}
