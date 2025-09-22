//
//  PaywallView.swift
//  mythings
//
//  Created by Designer on 2025/9/19.
//

import SwiftUI

struct PaywallView: View {

    // 你原本的兩種方案
    enum Plan: String, CaseIterable, Identifiable {
        case annual, lifetime
        var id: String { rawValue }
        var title: String { self == .annual ? "Annual" : "Lifetime" }
        var subtitle: String { self == .annual ? "Billed annually" : "Yours forever" }
    }

    // 從環境取得購買管理與關閉方法
    @EnvironmentObject var pm: PurchasesManager
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Plan = .annual

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    featuresCard
                    planSelector
                }
                .padding(.top, 40)
                .padding(.bottom, 40) // ✅ 預留空間給底部固定 CTA
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(false) // 可下滑關閉
            .safeAreaInset(edge: .bottom) { bottomBar } // 固定置底 CTA
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.systemGray6))
                    .frame(width: 96, height: 96)
                Image("pro app icon")
                    .resizable().scaledToFit().frame(width: 80, height: 80)
            }
            Text("My Things Premium")
                .font(.system(size: 28, weight: .bold))
            Text("Unlock your full potential with\nMy Things Premium.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Features Card
    private var featuresCard: some View {
        VStack(spacing: 0) {
            featureRow(image: Image("icon_cube"),
                       title: "Unlimited Objects",
                       desc: "Create as many objects as you need and never worry about hitting storage limits")

            Divider().padding(.horizontal, 24)

            featureRow(image: Image("icon_categories"),
                       title: "Unlimited Categories",
                       desc: "Organize your items into endless categories for perfect classification and easy access")

            Divider().padding(.horizontal, 24)

            featureRow(image: Image("icon_icloud"),
                       title: "iCloud Sync & Backup",
                       desc: "Keep your data safe and accessible across all your devices with seamless iCloud integration")
        }
        .padding(.vertical, 20)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.systemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(.quaternaryLabel), lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        .padding(.horizontal, 20)
    }

    private var planSelector: some View {
        VStack(spacing: 0) {
            planRow(plan: .annual, selected: $selected)
            Divider().padding(.leading, 20)
            planRow(plan: .lifetime, selected: $selected)
        }
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.systemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(.quaternaryLabel), lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        .padding(.horizontal, 20)
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            Button {
                Task {
                    let ok = await pm.purchase(plan: paywallPlan(from: selected))
                    if ok { dismiss() }
                }
            } label: {
                Text(selected == .annual ? "Subscribe annually" : "Buy lifetime")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .disabled(pm.isBusy)
            .background(Color.black)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .padding(.horizontal, 20)

            HStack(spacing: 18) {
                Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                Circle().frame(width: 3, height: 3).foregroundStyle(.tertiary)
                Link("Terms", destination: URL(string: "https://example.com/terms")!)
                Circle().frame(width: 3, height: 3).foregroundStyle(.tertiary)
                Button("Restore purchases") {
                    Task { await pm.restore(); if pm.isPro { dismiss() } }
                }
                .disabled(pm.isBusy)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial) // ✅ 底部做出半透明浮層感
    }

    // MARK: - Reusable rows

    private func featureRow(image: Image, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            image
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func planRow(plan: Plan, selected: Binding<Plan>) -> some View {
        Button {
            selected.wrappedValue = plan
        } label: {
            HStack(spacing: 16) {
                Image(systemName: selected.wrappedValue == plan ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected.wrappedValue == plan ? Color.black : Color.secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.title).font(.headline)
                    Text(plan.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                // ✅ 價格改為 RevenueCat 的本地化價格
                Text(pm.priceText(for: paywallPlan(from: plan)) ?? "…")
                    .font(.headline)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Plan ↔︎ PurchasesManager 用的 PaywallPlan 映射
    private func paywallPlan(from plan: Plan) -> PaywallPlan {
        plan == .annual ? .annual : .lifetime
    }
}


// MARK: - Preview

#Preview("Paywall") {
    PaywallView()
        .environmentObject(PurchasesManager()) // 預覽需要注入，避免編譯錯
}
