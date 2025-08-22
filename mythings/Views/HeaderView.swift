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
        case .none:         return "Default"
        case .purchaseDate: return "Purchase Date"
        case .price:        return "Price"
        case .name:         return "Name"
        }
    }

    var icon: String {
        switch self {
        case .none:         return "line.3.horizontal"
        case .purchaseDate: return "calendar"
        case .price:        return "dollarsign.circle"
        case .name:         return "textformat.abc"
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
    case (.none, _):                   return "Default Order"
    case (.purchaseDate, .descending): return "Newest First"
    case (.purchaseDate, .ascending):  return "Oldest First"
    case (.price, .ascending):         return "Lowest Price"
    case (.price, .descending):        return "Highest Price"
    case (.name, .ascending):          return "A → Z"
    case (.name, .descending):         return "Z → A"
    }
}

struct HeaderView: View {
    @Binding var isSearching: Bool
    @Binding var text: String
    @Binding var viewMode: ViewMode
    @Binding var sortKey: SortKey
    @Binding var sortOrder: SortOrder
    var navigateToSettings: () -> Void

    var body: some View {
        HStack {
            if isSearching {
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        TextField("Search by name or brand", text: $text)
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

                    Button("Cancel") {
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
                    Picker("Sort by", selection: $sortKey) {
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
                        .accessibilityLabel("Sort")
                }

                Button(action: { withAnimation { isSearching = true } }) {
                    Image(systemName: "magnifyingglass").font(.title2).padding(.trailing).foregroundColor(.primary)
                }
            }
        }
        .padding(.vertical)
    }
}
