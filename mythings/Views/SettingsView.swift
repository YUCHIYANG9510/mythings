//
//  SettingsView.swift
//  mythings
//
//  Created by Designer on 2025/5/2.
//

import SwiftUI



struct SettingsView: View {
    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var defaultCategory = "All"
    @State private var selectedAppIcon = "Default"
    @ObservedObject var categoryStore: CategoryStore

    let appIcons = ["Default", "Minimal", "Colorful"]

    var body: some View {
       
        Form {
            // MARK: - CATEGORIES
            Section(header: Text("CATEGORIES")) {
                
                NavigationLink("Manage Categories") {
                    ManageCategoriesView(categoryStore: categoryStore)
                }
            }
            
            // MARK: - APPEARANCE
            Section(header: Text("APPEARANCE")) {
                Toggle("Dark Mode", isOn: $isDarkMode)
                
                Picker("App Icon", selection: $selectedAppIcon) {
                    ForEach(appIcons, id: \.self) { icon in
                        Text(icon)
                    }
                }
            }
            
            // MARK: - SUPPORT
            Section(header: Text("SUPPORT")) {
                Button("Rate on App Store") {
                    // 尚未實作
                }
                .foregroundColor(.blue)
                
                Button("Subscribe to My Things Pro") {
                    // 尚未實作
                }
                .foregroundColor(.blue)
            }
            
            // MARK: - DANGER ZONE
            Section {
                Button("Delete All Things") {
                    // 尚未實作
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Settings")

    }
}

