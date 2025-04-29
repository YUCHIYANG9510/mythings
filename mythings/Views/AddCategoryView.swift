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
    @State private var selectedColor = "blue"
    @State private var showAlert = false
    
    let colorOptions = [
        "blue", "green", "red", "purple", "indigo", "orange", "pink", "yellow", "teal"
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Category Name")) {
                    TextField("Name", text: $categoryName)
                }
                
                Section(header: Text("Color")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 10) {
                        ForEach(colorOptions, id: \.self) { color in
                            Circle()
                                .fill(categoryStore.colorForName(color))
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                        .padding(-4)
                                        .opacity(selectedColor == color ? 1 : 0)
                                )
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Add Category")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            showAlert = true
                        } else {
                            categoryStore.addCategory(name: categoryName, color: selectedColor)
                            dismiss()
                        }
                    }
                }
            }
            .alert("Please enter a category name", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}
