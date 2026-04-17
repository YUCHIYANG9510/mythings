//
//  ProStatusView.swift
//  mythings
//

import SwiftUI

struct ProStatusView: View {
    @EnvironmentObject var pm: PurchasesManager
    @Environment(\.dismiss) private var dismiss
    
    // 🌐 監聽語言變更
    @ObservedObject private var localizationManager = LocalizationManager.shared

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
            .navigationTitle(L("pro_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("done")) { dismiss() }
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
            Text(pm.isPro ? L("pro_status_active") : L("pro_status_inactive"))
                .font(.title2).bold()
            Text(pm.isPro ? L("pro_thank_you") : L("pro_upgrade_message"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L("pro_subscription"))
                Spacer()
                Text(subscriptionTypeText)
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text(L("pro_valid_until"))
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
                Text(L("pro_manage_subscription"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .background(Color.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    
    private var subscriptionTypeText: String {
        if pm.isLifetime {
            return L("pro_lifetime")
        } else if pm.isPro {
            return L("pro_annual")
        } else {
            return L("pro_status_inactive")
        }
    }

    private var expirationText: String {
        if pm.isLifetime { return L("pro_forever") }
        guard let date = pm.proExpirationDate else { return "-" }
        let f = DateFormatter()
        f.locale = LocalizationManager.shared.locale
        f.dateStyle = .long
        return f.string(from: date)
    }
}

#Preview {
    ProStatusView().environmentObject(PurchasesManager())
}
