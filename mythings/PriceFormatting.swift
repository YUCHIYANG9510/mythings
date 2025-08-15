//
//  PriceFormatting.swift
//  mythings
//
//  Created by Designer on 2025/8/15.
//

import Foundation

/// 將任意輸入（"1200" / "$1200" / "1,200" / "$1,200"）規一化為「$1,200」
func normalizedPriceString(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    // 去掉前導 $ 與千分位逗號
    let noDollar = trimmed.hasPrefix("$") ? String(trimmed.dropFirst()) : trimmed
    let digitsOnly = noDollar.replacingOccurrences(of: ",", with: "")

    // 嘗試轉成數字並用千分位格式化
    if let value = Double(digitsOnly) {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let body = f.string(from: NSNumber(value: value)) ?? digitsOnly
        return "$" + body
    } else {
        // 非法數字就僅保證前面只有一個 $
        return "$" + digitsOnly
    }
}

extension Item {
    /// 顯示用價錢（永遠一個 `$`，自動套千分位）
    var displayPrice: String {
        normalizedPriceString(price)
    }
}
