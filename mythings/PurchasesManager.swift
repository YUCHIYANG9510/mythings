//
//  PurchasesManager.swift
//  mythings
//
//  Created by Designer on 2025/9/20.
//

import Foundation
import RevenueCat
#if canImport(UIKit)
import UIKit
#endif

// 不要在類別層級加 @MainActor，避免與 PurchasesDelegate 衝突（Swift 6 更嚴格）
final class PurchasesManager: NSObject, ObservableObject, PurchasesDelegate {

    // === 你的 RC entitlement 名稱 ===
    private let entitlementID = "Premium"

    // === 你現在的商品 ID ===
    enum SKU {
        static let lifetime     = "com.mythings.lifetime"       // 非消耗性
        static let yearly       = "com.mythings.yearly"         // 年費
        static var annualCandidates: [String] { [yearly] }
        static var all: [String] { [lifetime, yearly] }
    }

    // 對外狀態
    @Published private(set) var isPro: Bool = false
    @Published private(set) var offerings: Offerings?
    @Published private(set) var isBusy: Bool = false
    @Published private(set) var latestCustomerInfo: CustomerInfo?

    private var productMap: [String: StoreProduct] = [:]

    override init() {
        super.init()

        // ✅ 註冊委派，之後每次 CustomerInfo 更新都會回調到下方 delegate
        Purchases.shared.delegate = self

        Task {
            await refreshCustomerInfo()
            await fetchOfferings()
            await preloadProducts()

            // 啟動時補抓一次（新版名稱 getCustomerInfo）
            Purchases.shared.getCustomerInfo { [weak self] info, _ in
                guard let self else { return }
                Task { await self.applyCustomerInfo(info) }
            }
        }
    }

    // MARK: - Gating helpers（免費版：50 物品 / 6 分類；Pro 全開）

    func canAddItem(currentCount: Int) -> Bool { isPro || currentCount < 50 }
    func canAddCategory(currentCount: Int) -> Bool { isPro || currentCount < 6 }
    var canUseICloud: Bool { isPro }

    /// 顯示在付費牆的本地化價格字串
    func priceText(for plan: PaywallPlan) -> String? {
        switch plan {
        case .annual:
            if let p = productMap[SKU.yearly] { return p.localizedPriceString }
        case .lifetime:
            if let p = productMap[SKU.lifetime] { return p.localizedPriceString }
        }
        return nil
    }

    // MARK: - Purchases

    @MainActor
    func purchase(plan: PaywallPlan) async -> Bool {
        isBusy = true
        defer { isBusy = false }

        do {
            if let pkg = await pickPackage(from: plan) {
                let result = try await Purchases.shared.purchase(package: pkg)
                applyCustomerInfo(result.customerInfo)   // Remove await - already on MainActor
                return isPro
            }

            let product = try await pickProductByID(for: plan)
            let result = try await Purchases.shared.purchase(product: product)
            applyCustomerInfo(result.customerInfo)  // Remove await - already on MainActor
            return isPro

        } catch {
            print("purchase error: \(error)")
            return false
        }
    }

    func restore() async {
        do {
            let info = try await Purchases.shared.restorePurchases()
            await applyCustomerInfo(info)
        } catch {
            print("restore error: \(error)")
        }
    }

    // MARK: - Data fetchers

    /// 抓取使用者權益
    func refreshCustomerInfo() async {
        do {
            // v5 這個 API 是 async throws
            let info = try await Purchases.shared.customerInfo()
            await applyCustomerInfo(info)
        } catch {
            print("customerInfo error: \(error)")
        }
    }

    /// 抓取 Offerings（可能拋錯）
    func fetchOfferings() async {
        do {
            let fetchedOfferings = try await Purchases.shared.offerings()
            await MainActor.run {
                offerings = fetchedOfferings
            }
        } catch {
            print("offerings error: \(error)")
        }
    }

    /// 預先載入產品（v5：async，**不拋錯**）
    func preloadProducts() async {
        let products = await Purchases.shared.products(SKU.all)
        var dict: [String: StoreProduct] = [:]
        for p in products { dict[p.productIdentifier] = p }
        productMap = dict
    }

    /// 從 Offerings 選擇方案（不拋錯）
    private func pickPackage(from plan: PaywallPlan) async -> Package? {
        if let current = offerings?.current {
            return current.availablePackages.first { matches($0, plan: plan) }
        } else {
            await fetchOfferings()
            return offerings?.current?.availablePackages.first { matches($0, plan: plan) }
        }
    }

    private func matches(_ pkg: Package, plan: PaywallPlan) -> Bool {
        switch plan {
        case .annual:
            return pkg.packageType == .annual ||
                   SKU.annualCandidates.contains(pkg.storeProduct.productIdentifier)
        case .lifetime:
            return pkg.packageType == .lifetime ||
                   pkg.storeProduct.productIdentifier == SKU.lifetime
        }
    }

    /// 若無 Offerings，改用 Product ID 取得產品；這裡僅在「找不到產品」時自訂拋錯
    private func pickProductByID(for plan: PaywallPlan) async throws -> StoreProduct {
        enum PMError: Error { case productNotFound(String) }

        switch plan {
        case .annual:
            if let p = productMap[SKU.yearly] { return p }
            let ps = await Purchases.shared.products(SKU.annualCandidates)
            if let p = ps.first { return p }
            throw PMError.productNotFound("annual")

        case .lifetime:
            if let p = productMap[SKU.lifetime] { return p }
            let ps = await Purchases.shared.products([SKU.lifetime])
            if let p = ps.first { return p }
            throw PMError.productNotFound("lifetime")
        }
    }

    // MARK: - 主執行緒上更新 UI 狀態

    @MainActor
    private func applyCustomerInfo(_ info: CustomerInfo?) {
        latestCustomerInfo = info
        isPro = info?.entitlements[entitlementID]?.isActive == true
        #if DEBUG
        if let info {
            let active = info.entitlements[entitlementID]?.isActive == true
            let pid = info.entitlements[entitlementID]?.productIdentifier ?? "-"
            let exp = info.entitlements[entitlementID]?.expirationDate?.description ?? "nil"
            print("[PM] applyCustomerInfo -> isPro=\(active) pid=\(pid) exp=\(exp)")
        } else {
            print("[PM] applyCustomerInfo -> info nil")
        }
        #endif
    }

    // MARK: - PurchasesDelegate

    // 注意：此協定方法是「非隔離」，Swift 6 下不能標 @MainActor；改用 Task 切回主執行緒
    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { await self.applyCustomerInfo(customerInfo) }
    }
}

// Paywall 用的方案 enum（與你的 PaywallView 映射一致）
enum PaywallPlan { case annual, lifetime }

// MARK: - Pro 狀態查詢輔助
extension PurchasesManager {
    /// 目前啟用中的 entitlement 對應的產品 ID（若有）
    var proProductIdentifier: String? {
        latestCustomerInfo?.entitlements[entitlementID]?.productIdentifier
    }

    /// 若為訂閱，回傳到期日；若為終身購買通常為 nil
    var proExpirationDate: Date? {
        latestCustomerInfo?.entitlements[entitlementID]?.expirationDate
    }

    /// 簡易判斷是否為終身購買
    var isLifetime: Bool {
        proProductIdentifier == SKU.lifetime && isPro
    }

    /// 嘗試開啟系統的訂閱管理頁面
    func openManageSubscriptions() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        #if canImport(UIKit)
        DispatchQueue.main.async {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
