//
//  HeaderView.swift
//  mythings
//
//  Created by Designer on 2025/8/15.
//

import SwiftUI

struct HeaderView: View {
    @Binding var isSearching: Bool
    @Binding var text: String
    @Binding var viewMode: ViewMode
    var navigateToSettings: () -> Void
    
    var body: some View {
        HStack {
            if isSearching {
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        TextField("搜尋名稱或品牌", text: $text)
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
                    Image(systemName: "gearshape.fill").font(.title2).padding(.leading).foregroundColor(.primary)
                }
                Spacer()
                Text("My Things").font(.title3).bold()
                Spacer()
                Button(action: { withAnimation { viewMode = viewMode == .grid ? .list : .grid } }) {
                    Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                        .font(.title2).foregroundColor(.primary)
                }
                .padding(.trailing, 8)
                Button(action: { withAnimation { isSearching = true } }) {
                    Image(systemName: "magnifyingglass").font(.title2).padding(.trailing).foregroundColor(.primary)
                }
            }
        }
        .padding(.vertical)
    }
}
