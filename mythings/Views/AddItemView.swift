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
    @ObservedObject var brandStore: BrandStore
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
                
                HStack {
                    Text("$")
                        .foregroundColor(.gray)
                    TextField("Price", text: $price)
                        .keyboardType(.decimalPad)
                        .onChange(of: price) { _, newValue in
                            price = newValue.replacingOccurrences(of: "$", with: "")
                        }
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        TextField("Brand", text: $brand)
                            .autocapitalization(.words)

                        Button(action: {
                            let trimmed = brand.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty && !brandStore.brands.contains(trimmed) {
                                brandStore.brands.append(trimmed)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("Add Brand")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(20)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    if !brandStore.brands.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(brandStore.brands, id: \.self) { brandName in
                                    HStack(spacing: 10) {
                                        Button(action: {
                                            brand = brandName
                                        }) {
                                            Text(brandName)
                                                .foregroundColor(.black)
                                                .font(.caption)
                                        }

                                        Button(action: {
                                            if let index = brandStore.brands.firstIndex(of: brandName) {
                                                brandStore.brands.remove(at: index)
                                            }
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.gray)
                                                .frame(width: 10, height: 10)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.gray.opacity(0.2))
                                    .foregroundColor(Color.black)
                                    .cornerRadius(16)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical)
                
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
                    .foregroundColor(.blue) // 設定為藍色
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
                                
                                ImageCacheManager.shared.invalidateCache()
                                
                                onComplete(item)
                            }
                        } else {
                            showValidationAlert = true
                        }
                    }
                    .foregroundColor(.blue) // 設定為藍色
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
