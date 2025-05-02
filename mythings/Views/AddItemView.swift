//
//  AddItemView.swift
//  mythings
//
//  Created by Designer on 2025/4/29.
//

import SwiftUI

struct AddItemView: View {
    @Binding var selectedImage: UIImage?
    var existingItem: Item? = nil
    @ObservedObject var categoryStore: CategoryStore
    @Binding var showManageCategories: Bool
    
    @Environment(\.dismiss) var dismiss
    var onComplete: (Item) -> Void
    @State private var name: String = ""
    @State private var brand: String = ""
    @State private var category: String = ""
    @State private var price: String = ""
    @State private var showValidationAlert = false
    @State private var showCategoryManagement = false
    @State private var showImagePicker = false
   
    var body: some View {
        NavigationView {
            Form {
                if let image = selectedImage {
                    HStack {
                        Spacer()
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 200)
                            .onTapGesture {
                                            showImagePicker = true
                                        }
                        Spacer()
                    }
                    .padding(.vertical)
                }
                
                TextField("Name", text: $name)
                TextField("Brand", text: $brand)
                HStack {
                    Text("$")
                        .foregroundColor(.gray)
                    TextField("Price", text: $price)
                        .keyboardType(.decimalPad)
                        .onChange(of: price) { _, newValue in
                            price = newValue.replacingOccurrences(of: "$", with: "")
                        }
                }
                
                Section(header: Text("Category")) {
                    Picker("Category", selection: $category) {
                        ForEach(categoryStore.categories) { category in
                            Text(category.name).tag(category.name)
                        }
                    }
                    
                    Button(action: {
                        showCategoryManagement = true
                    }) {
                        HStack {
                            Text("Manage Categories")
                                .foregroundColor(.black)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .navigationTitle(existingItem == nil ? "Add item" : "Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if isFormValid() {
                            if let selectedImage = selectedImage {
                                let fileName = existingItem?.imageName ?? UUID().uuidString + ".png"
                                let fileURL = FileManager.documentsDirectory.appendingPathComponent(fileName)
                                
                                if let data = selectedImage.pngData() {
                                    try? data.write(to: fileURL)
                                }
                                
                                let item = Item(
                                    id: existingItem?.id ?? UUID(),
                                    imageName: fileName,
                                    brand: brand,
                                    category: category,
                                    name: name,
                                    price: price
                                )
                                
                                onComplete(item)
                            }
                        } else {
                            showValidationAlert = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showCategoryManagement) {
            ManageCategoriesView(categoryStore: categoryStore)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage)
        }
        .onAppear {
            if let item = existingItem {
                name = item.name
                brand = item.brand
                category = item.category
                price = item.price.replacingOccurrences(of: "$", with: "")
                if let image = UIImage(contentsOfFile: FileManager.documentsDirectory.appendingPathComponent(item.imageName).path) {
                    selectedImage = image
                }
            } else if !categoryStore.categories.isEmpty {
                category = categoryStore.categories[0].name
            }
        }
        .alert("請填寫所有欄位", isPresented: $showValidationAlert) {
            Button("OK", role: .cancel) {}
        }
    }
    
    private func isFormValid() -> Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !brand.trimmingCharacters(in: .whitespaces).isEmpty &&
        !category.isEmpty &&
        !price.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
