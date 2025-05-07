//
//  SettingsView.swift
//  mythings
//
//  Created by Designer on 2025/5/2.
//

import SwiftUI


struct NavigationConfigurator: UIViewControllerRepresentable {
    var configure: (UINavigationController) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController() // 空的 view controller，只是為了拿到 navigation controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if let navController = uiViewController.navigationController {
            configure(navController)
        }
    }
}


struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var defaultCategory = "All"
    @State private var selectedAppIcon = "Default"
    @ObservedObject var categoryStore: CategoryStore

    let availableCategories = ["All", "Top", "Bottom", "Shoes", "Accessory", "Other"]
    let appIcons = ["Default", "Minimal", "Colorful"]

    var body: some View {
        ZStack {
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
                .foregroundColor(isDarkMode ? .white : .blue)
                
                Button("Subscribe to My Things Pro") {
                    // 尚未實作
                }
                .foregroundColor(isDarkMode ? .white : .blue)
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
        .navigationBarTitleDisplayMode(.inline)
        .background(
            NavigationConfigurator { navController in
                navController.navigationBar.tintColor = .systemBlue // 設定導航欄按鈕顏色
            }
        )
    }
    }
}

