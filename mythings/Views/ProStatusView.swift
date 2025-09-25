//
//  ProStatusView.swift
//  mythings
//

import SwiftUI

struct ProStatusView: View {
    @EnvironmentObject var pm: PurchasesManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    statusCard
                    actions
                }
                .padding(20)
            }
            .navigationTitle("My Things Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image("Star")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
            Text(pm.isPro ? "You are Pro" : "Not Subscribed")
                .font(.title2).bold()
            Text(pm.isPro ? "Thank you for your support!" : "Upgrade to unlock all features.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Subscription")
                Spacer()
                Text(pm.isLifetime ? "Lifetime Purchase" : (pm.isPro ? "Annual Subscription" : "Not Subscribed"))
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text("Valid Until")
                Spacer()
                Text(expirationText)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.quaternaryLabel), lineWidth: 1))
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                pm.openManageSubscriptions()
            } label: {
                Text("Manage Subscription")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .background(Color.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var expirationText: String {
        if pm.isLifetime { return "Forever" }
        guard let date = pm.proExpirationDate else { return "-" }
        let f = DateFormatter()
        f.locale = Locale(identifier: Locale.preferredLanguages.first ?? "en")
        f.dateStyle = .long
        return f.string(from: date)
    }
}

#Preview {
    ProStatusView().environmentObject(PurchasesManager())
}
