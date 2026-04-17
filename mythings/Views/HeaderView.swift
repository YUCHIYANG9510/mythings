//
//  HeaderView.swift
//  mythings
//
//  Created by Designer on 2025/8/15.
//

import SwiftUI

enum SortKey: String, CaseIterable, Identifiable {
    case none
    case purchaseDate
    case price
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:         return L("sort_key_default")
        case .purchaseDate: return L("sort_key_purchase_date")
        case .price:        return L("sort_key_price")
        case .name:         return L("sort_key_name")
        }
    }

    var icon: String {
        switch self {
        case .none:         return "line.3.horizontal"
        case .purchaseDate: return "calendar"
        case .price:        return "dollarsign.circle"
        case .name:         return "a.circle"
        }
    }
}

enum SortOrder: String {
    case ascending
    case descending

    mutating func toggle() { self = (self == .ascending) ? .descending : .ascending }
    var arrow: String { self == .ascending ? "arrow.up" : "arrow.down" }
}

/// 實際顯示的選單文字
func sortLabel(for key: SortKey, order: SortOrder) -> String {
    switch (key, order) {
    case (.none, _):                   return L("sort_label_default")
    case (.purchaseDate, .descending): return L("sort_label_newest_first")
    case (.purchaseDate, .ascending):  return L("sort_label_oldest_first")
    case (.price, .ascending):         return L("sort_label_lowest_price")
    case (.price, .descending):        return L("sort_label_highest_price")
    case (.name, .ascending):          return L("sort_label_a_to_z")
    case (.name, .descending):         return L("sort_label_z_to_a")
    }
}

struct HeaderView: View {
    @Binding var isSearching: Bool
    @Binding var text: String
    @Binding var viewMode: ViewMode
    @Binding var sortKey: SortKey
    @Binding var sortOrder: SortOrder
    var navigateToSettings: () -> Void
    
    // 🌐 監聽語言變更
    @ObservedObject private var localizationManager = LocalizationManager.shared

    var body: some View {
        HStack {
            if isSearching {
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        TextField(L("search_by_name_or_brand"), text: $text)
                            .textFieldStyle(PlainTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        if !text.isEmpty {
                            Button(action: { text = "" }) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)

                    Button(L("cancel")) {
                        withAnimation { isSearching = false; text = "" }
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
                .padding(.horizontal)
            } else {
                Button(action: { navigateToSettings() }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .padding(.leading)
                        .foregroundColor(.primary)
                }

                Spacer()

                // Toggle Grid / List
                Button(action: { withAnimation { viewMode = viewMode == .grid ? .list : .grid } }) {
                    Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                        .font(.title2).foregroundColor(.primary)
                }
                .padding(.trailing, 8)

                // 🔽 Sort menu
                Menu {
                    // 依據
                    Picker(L("sort_by"), selection: $sortKey) {
                        ForEach(SortKey.allCases) { key in
                            Label(key.title, systemImage: key.icon).tag(key)
                        }
                    }

                    Divider()

                    // 升序／降序切換 → 顯示成直覺文字
                    Button {
                        sortOrder.toggle()
                    } label: {
                        Label(sortLabel(for: sortKey, order: sortOrder), systemImage: sortOrder.arrow)
                    }
                    .disabled(sortKey == .none)
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .padding(.trailing, 8)
                        .accessibilityLabel(L("sort"))
                }

                Button(action: { withAnimation { isSearching = true } }) {
                    Image(systemName: "magnifyingglass").font(.title2).padding(.trailing).foregroundColor(.primary)
                }
            }
        }
        .padding(.vertical)
    }
}
