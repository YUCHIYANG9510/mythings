//
//  ContentView.swift
//  mythings
//
//  Created by Designer on 2025/4/23.
//

import SwiftUI
import PhotosUI
import UIKit
import Foundation




extension FileManager {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}



struct ContentView: View {
    @State private var selectedCategory = "All"
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var showActionSheet = false
    @State private var selectedImage: UIImage?
    @State private var items: [Item] = []
    @State private var selectedItem: Item?
    @State private var editingItem: Item?
    @State private var showManageCategories = false
    @State private var isAddingNewItem = false
    
    @StateObject private var categoryStore = CategoryStore()
    
    private var savePath: URL {
        FileManager.documentsDirectory.appendingPathComponent("items.json")
    }
    
    var categoryNames: [String] {
        var names = ["All"]
        names.append(contentsOf: categoryStore.categories.map { $0.name })
        return names
    }
    
    var filteredItems: [Item] {
        selectedCategory == "All" ? items : items.filter { $0.category == selectedCategory }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack {
                Text("My Things")
                    .font(.title3)
                    .bold()
                    .padding(.vertical)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categoryNames, id: \.self) { category in
                            Button(action: {
                                selectedCategory = category
                            }) {
                                Text(category)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .font(.caption)
                                    .background(selectedCategory == category ? Color.black : Color(.systemGray5))
                                    .foregroundColor(selectedCategory == category ? .white : .black)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                ScrollView {
                    if filteredItems.isEmpty {
                        VStack(spacing: 24) {
                            Image(systemName: "tray")
                                .resizable()
                                .frame(width: 40, height: 30)
                                .foregroundColor(.gray)
                            Text("It's empty here...")
                                .foregroundColor(.gray)
                                .font(.subheadline)
                        }
                        .padding(.top, 250)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(filteredItems) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    let imagePath = FileManager.documentsDirectory.appendingPathComponent(item.imageName).path
                                    if let uiImage = UIImage(contentsOfFile: imagePath) {
                                        ZStack {
                                            Color(.systemGray6)
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(height: 120)
                                                .cornerRadius(8)
                                                
                                        }
                                        .frame(height: 150)
                                        .cornerRadius(8)
                                    }
                                    
                                    Text("\(item.brand) · \(item.category)")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    
                                    HStack {
                                        Text(item.name)
                                            .font(.subheadline)
                                        Spacer()
                                        Text("$\(item.price)")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                                .onTapGesture {
                                    selectedItem = item
                                }
                                .contextMenu {
                                    Button("編輯") {
                                        editingItem = item
                                    }
                                    Button("刪除", role: .destructive) {
                                        items.removeAll { $0.id == item.id }
                                        saveItems()
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            
            Button(action: {
                showActionSheet = true
            }) {
                Image(systemName: "plus")
                    .font(.largeTitle)
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.black)
                    .clipShape(Circle())
                    .shadow(radius: 5)
            }
            .padding(.bottom, 30)
            .confirmationDialog("選擇照片來源", isPresented: $showActionSheet, titleVisibility: .visible) {
                Button("拍照") {
                    showCamera = true
                }
                Button("從相簿選擇") {
                    showImagePicker = true
                }
                Button("取消", role: .cancel) {}
            }
        }
        .sheet(isPresented: $showManageCategories) {
            ManageCategoriesView(categoryStore: categoryStore)
        }
        .sheet(isPresented: $showImagePicker) {
            PhotoPicker(selectedImage: $selectedImage, shouldRemoveBackground: false)
                .onDisappear {
                    if selectedImage != nil {
                        isAddingNewItem = true                    }
                }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker(selectedImage: $selectedImage)
                .onDisappear {
                    if selectedImage != nil {
                        isAddingNewItem = true                    }
                }
        }
        .sheet(item: $selectedItem) { item in
            ItemDetailView(item: item)
        }
        .sheet(item: $editingItem) { editing in
            AddItemView(
                selectedImage: $selectedImage,
                existingItem: editing,
                categoryStore: categoryStore,
                showManageCategories: $showManageCategories
            ) { newItem in
                if let index = items.firstIndex(where: { $0.id == editing.id }) {
                    items[index] = newItem
                }
                self.editingItem = nil
                selectedImage = nil
                saveItems()
            }
        }
        .sheet(isPresented: $isAddingNewItem) {
            AddItemView(
                selectedImage: $selectedImage,
                existingItem: nil,
                categoryStore: categoryStore,
                showManageCategories: $showManageCategories
            ) { newItem in
                items.append(newItem)
                selectedImage = nil
                isAddingNewItem = false
                saveItems()
            }
        }
        .onAppear {
            loadItems()
        }
    }
    
    private func saveItems() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: savePath)
        } catch {
            print("儲存失敗：\(error)")
        }
    }
    
    private func loadItems() {
        do {
            let data = try Data(contentsOf: savePath)
            items = try JSONDecoder().decode([Item].self, from: data)
        } catch {
            print("讀取失敗或尚無資料：\(error)")
        }
    }
    
    
    
    struct ItemDetailView: View {
        let item: Item
        @Environment(\.dismiss) var dismiss
        @State private var image: UIImage?
        
        var body: some View {
            VStack {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 300)
                        .padding()
                }
                Text(item.name)
                    .font(.title2)
                    .padding(.vertical)
                Text("\(item.brand) · \(item.category)")
                    .foregroundColor(.gray)
                    .padding(.bottom, 4)
                Text("$\(item.price)")
                    .font(.headline)
            }
            .padding()
            .onTapGesture {
                dismiss()
            }
            .onAppear {
                let imagePath = FileManager.documentsDirectory.appendingPathComponent(item.imageName).path
                if let uiImage = UIImage(contentsOfFile: imagePath) {
                    self.image = uiImage
                }
            }
        }
    }
    
    struct PhotoPicker: UIViewControllerRepresentable {
        @Binding var selectedImage: UIImage?
        var shouldRemoveBackground: Bool
        
        func makeUIViewController(context: Context) -> PHPickerViewController {
            var config = PHPickerConfiguration()
            config.filter = .images
            config.selectionLimit = 1
            
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = context.coordinator
            return picker
        }
        
        func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
        
        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }
        
        class Coordinator: NSObject, PHPickerViewControllerDelegate {
            let parent: PhotoPicker
            
            init(_ parent: PhotoPicker) {
                self.parent = parent
            }
            
            func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
                picker.dismiss(animated: true)
                
                guard let provider = results.first?.itemProvider,
                      provider.canLoadObject(ofClass: UIImage.self) else { return }
                
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    DispatchQueue.main.async {
                        if let selectedImage = image as? UIImage {
                            self.parent.selectedImage = selectedImage
                        }
                    }
                }
            }
        }
    }
    
    struct CameraPicker: UIViewControllerRepresentable {
        @Binding var selectedImage: UIImage?
        @Environment(\.presentationMode) var presentationMode
        
        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.delegate = context.coordinator
            picker.sourceType = .camera
            return picker
        }
        
        func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
        
        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }
        
        class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
            let parent: CameraPicker
            
            init(_ parent: CameraPicker) {
                self.parent = parent
            }
            
            func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
                if let image = info[.originalImage] as? UIImage {
                    parent.selectedImage = image
                }
                parent.presentationMode.wrappedValue.dismiss()
            }
            
            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
                parent.presentationMode.wrappedValue.dismiss()
            }
        }
    }
    
    struct ManageCategoriesView: View {
        @ObservedObject var categoryStore: CategoryStore
        @Environment(\.dismiss) var dismiss
        @State private var newCategoryName = ""
        @State private var selectedColor = "blue"
        @State private var showAddCategoryView = false
        
        let colorOptions = [
            "blue", "green", "red", "purple", "indigo", "orange", "pink", "yellow", "teal"
        ]
        
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
                                    .fill(colorForName(category.color))
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
                                    .fill(colorForName(color))
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
        
        func colorForName(_ name: String) -> Color {
            switch name {
            case "blue": return .blue
            case "green": return .green
            case "red": return .red
            case "purple": return .purple
            case "indigo": return .indigo
            case "orange": return .orange
            case "pink": return .pink
            case "yellow": return .yellow
            case "teal": return .teal
            default: return .blue
            }
        }
    }

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
                            Spacer()
                        }
                    }
                    
                    TextField("Name", text: $name)
                    TextField("Brand", text: $brand)
                    TextField("Price", text: $price)
                        .keyboardType(.decimalPad)
                        .onChange(of: price) { _, newValue in
                            price = newValue.replacingOccurrences(of: "$", with: "")
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
    
    
    
}

#Preview {
    ContentView()
}
