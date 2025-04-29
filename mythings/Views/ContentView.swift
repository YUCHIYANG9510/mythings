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
    

    
    
        
       
    
    
    

#Preview {
    ContentView()
}
