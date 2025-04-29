//
//  ManageCategoriesView.swift
//  mythings
//
//  Created by Designer on 2025/4/29.
//
import SwiftUI

struct ManageCategoriesView: View {
    @ObservedObject var categoryStore: CategoryStore
    @Environment(\.dismiss) var dismiss
    @State private var showAddCategoryView = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                List {
                    ForEach(categoryStore.categories) { category in
                        HStack {
                            Text(category.name)
                                .font(.body)
                            Spacer()
                            Circle()
                                .fill(categoryStore.colorForName(category.color))
                                .frame(width: 24, height: 24)
                        }
                    }
                    .onDelete(perform: categoryStore.deleteCategory)
                    
                    Button(action: {
                        showAddCategoryView = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                            Text("Add Category")
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle("Manage Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") {
                        // Future enhancement: Implement edit mode
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showAddCategoryView) {
                AddCategoryView(categoryStore: categoryStore)
            }
        }
    }
}
