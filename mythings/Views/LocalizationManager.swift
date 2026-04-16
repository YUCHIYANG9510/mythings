//
//  LocalizationManager.swift
//  mythings
//

import Foundation
import SwiftUI

/// 語言管理器 - 支援手動切換語言
class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "app_language")
            // 重新載入語言包
            loadLanguageBundle()
        }
    }
    
    // 當前語言的 Bundle
    private(set) var languageBundle: Bundle?
    
    private init() {
        // 嘗試從 UserDefaults 讀取使用者選擇的語言
        if let savedLanguage = UserDefaults.standard.string(forKey: "app_language"),
           let language = AppLanguage(rawValue: savedLanguage) {
            self.currentLanguage = language
        } else {
            // 自動偵測系統語言
            self.currentLanguage = Self.detectSystemLanguage()
        }
        loadLanguageBundle()
    }
    
    /// 載入當前語言的 Bundle
    private func loadLanguageBundle() {
        if let path = Bundle.main.path(forResource: currentLanguage.rawValue, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            self.languageBundle = bundle
        } else {
            self.languageBundle = Bundle.main
        }
    }
    
    /// 取得本地化字串
    func localizedString(_ key: String, comment: String = "") -> String {
        if let bundle = languageBundle {
            return NSLocalizedString(key, tableName: nil, bundle: bundle, comment: comment)
        }
        return NSLocalizedString(key, comment: comment)
    }
    
    /// 自動偵測系統語言
    static func detectSystemLanguage() -> AppLanguage {
        let preferredLanguages = Locale.preferredLanguages
        
        // 檢查首選語言
        guard let firstLanguage = preferredLanguages.first else {
            return .english
        }
        
        // 繁體中文：台灣、香港、澳門
        if firstLanguage.hasPrefix("zh-Hant") || 
           firstLanguage.hasPrefix("zh-TW") || 
           firstLanguage.hasPrefix("zh-HK") || 
           firstLanguage.hasPrefix("zh-MO") {
            return .traditionalChinese
        }
        
        // 簡體中文：中國大陸、新加坡
        if firstLanguage.hasPrefix("zh-Hans") || 
           firstLanguage.hasPrefix("zh-CN") || 
           firstLanguage.hasPrefix("zh-SG") {
            return .simplifiedChinese
        }
        
        // 預設使用英文
        return .english
    }
    
    /// 取得當前語言的 Locale
    var locale: Locale {
        return Locale(identifier: currentLanguage.localeIdentifier)
    }
}

/// 支援的語言
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case traditionalChinese = "zh-Hant"
    case simplifiedChinese = "zh-Hans"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .traditionalChinese:
            return "繁體中文"
        case .simplifiedChinese:
            return "简体中文"
        }
    }
    
    var localeIdentifier: String {
        switch self {
        case .english:
            return "en_US"
        case .traditionalChinese:
            return "zh_TW"
        case .simplifiedChinese:
            return "zh_CN"
        }
    }
}

/// 全域本地化函數 - 取代 NSLocalizedString
func L(_ key: String, comment: String = "") -> String {
    return LocalizationManager.shared.localizedString(key, comment: comment)
}

/// String Extension - 用於手動語言切換時的本地化
extension String {
    func localized(language: AppLanguage) -> String {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(self, comment: "")
        }
        return NSLocalizedString(self, tableName: nil, bundle: bundle, comment: "")
    }
    
    /// 使用當前選擇的語言本地化
    var localized: String {
        return LocalizationManager.shared.localizedString(self)
    }
}
