//
//  AddCategoryView.swift
//  mythings
//
//  Created by Designer on 2025/4/29.
//

import SwiftUI

struct AddCategoryView: View {
    @ObservedObject var categoryStore: CategoryStore
    @Environment(\.dismiss) var dismiss
    @State private var categoryName = ""
    @State private var showAlert = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Category Name")) {
                    TextField("Name", text: $categoryName)
                }
            }
            .navigationTitle("Add Category")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            showAlert = true
                        } else {
                            categoryStore.addCategory(name: categoryName)
                            dismiss()
                        }
                    }
                    .foregroundColor(.blue)

                }
            }
            .alert("Please enter a category name", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}


