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

struct Item: Identifiable {
    let id = UUID()
    let imageName: String
    let brand: String
    let category: String
    let name: String
    let price: String
}

extension FileManager {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

struct ContentView: View {
    let categories = ["All", "Tops", "Pants", "Outer", "Bags", "Shoes", "Other"]
    @State private var selectedCategory = "All"
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var showActionSheet = false
    @State private var selectedImage: UIImage?
    @State private var showAddSheet = false
    @State private var items: [Item] = []
    @State private var selectedItem: Item? // 被點擊的 item（用於放大預覽）
    @State private var showDetailView = false
    @State private var editingItem: Item? // 用來編輯 item
    
    
    
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
                        ForEach(categories, id: \.self) { category in
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
                    }
                    else {
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
                                    showDetailView = true
                                }
                                .contextMenu {
                                    Button("編輯") {
                                        editingItem = item
                                        showAddSheet = true
                                    }
                                    Button("刪除", role: .destructive) {
                                        items.removeAll { $0.id == item.id }
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            
            // 固定在底部中央的 "+" 按鈕
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
        .sheet(isPresented: $showImagePicker) {
            PhotoPicker(selectedImage: $selectedImage, shouldRemoveBackground: false)
                .onDisappear {
                    if selectedImage != nil {
                        showAddSheet = true
                    }
                }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker(selectedImage: $selectedImage)
                .onDisappear {
                    if selectedImage != nil {
                        showAddSheet = true
                    }
                }
        }
        .sheet(isPresented: $showDetailView) {
            if let selectedItem = selectedItem {
                ItemDetailView(item: selectedItem)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddItemView(selectedImage: $selectedImage, existingItem: editingItem) { newItem in
                if let editing = editingItem {
                    // 編輯模式：更新現有項目
                    if let index = items.firstIndex(where: { $0.id == editing.id }) {
                        items[index] = newItem
                    }
                    editingItem = nil
                } else {
                    // 新增模式：加入新項目
                    items.append(newItem)
                }
                selectedImage = nil  // Reset selected image
                showAddSheet = false // Dismiss the sheet
            }
        }
    }
    
    struct ItemDetailView: View {
        let item: Item
        @Environment(\.dismiss) var dismiss
        
        var body: some View {
            VStack {
                let imagePath = FileManager.documentsDirectory.appendingPathComponent(item.imageName).path
                if let uiImage = UIImage(contentsOfFile: imagePath) {
                    Image(uiImage: uiImage)
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
    
    struct AddItemView: View {
        @Binding var selectedImage: UIImage?
        var existingItem: Item? = nil
        @Environment(\.dismiss) var dismiss
        var onComplete: (Item) -> Void
        @State private var name: String = ""
        @State private var brand: String = ""
        @State private var category: String = ""
        @State private var price: String = ""
        
        let categories = ["Tops", "Pants", "Outer", "Shoes", "Bags", "Other"]
        
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
                            // Remove any existing "$" before adding a new one
                            price = newValue.replacingOccurrences(of: "$", with: "")
                        }
                    
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) {
                            Text($0)
                        }
                    }
                }
                .navigationTitle("Add item")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            dismiss()
                        }) {
                            Text("Cancel")
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            if let selectedImage = selectedImage {
                                let fileName = existingItem?.imageName ?? UUID().uuidString + ".png"
                                let fileURL = FileManager.documentsDirectory.appendingPathComponent(fileName)
                                
                                if let data = selectedImage.pngData() {
                                    try? data.write(to: fileURL)
                                }
                                
                                let item = Item(
                                    imageName: fileName,
                                    brand: brand,
                                    category: category,
                                    name: name,
                                    price: price
                                )
                                
                                onComplete(item)
                                dismiss()
                            }
                        }) {
                            Text("新增")
                        }
                    }
                }
                .onAppear {
                    if let item = existingItem {
                        name = item.name
                        brand = item.brand
                        category = item.category
                        // Remove "$" when editing
                        price = item.price.replacingOccurrences(of: "$", with: "")
                        
                        if let image = UIImage(contentsOfFile: FileManager.documentsDirectory.appendingPathComponent(item.imageName).path) {
                            selectedImage = image
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
