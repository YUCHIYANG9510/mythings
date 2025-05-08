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
                                .foregroundStyle(.black)
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle("Manage Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
            .sheet(isPresented: $showAddCategoryView) {
                AddCategoryView(categoryStore: categoryStore)
            }
        }
        .toolbarColorScheme(.light) // For light mode navigation buttons
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
