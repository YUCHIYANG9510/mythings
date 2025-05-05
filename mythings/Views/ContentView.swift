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

enum NavigationTarget: Hashable {
    case settings
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
    @State private var dragOffset = CGSize.zero
    @State private var path: [NavigationTarget] = []

    @StateObject private var categoryStore = CategoryStore()
    @StateObject private var brandStore = BrandStore()

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
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                VStack {
                    HeaderView {
                        path.append(.settings)
                    }

                    CategoryScrollView(
                        categoryNames: categoryNames,
                        selectedCategory: $selectedCategory
                    )

                    ItemsGridView(
                        filteredItems: filteredItems,
                        selectedItem: $selectedItem,
                        editingItem: $editingItem,
                        items: $items,
                        saveItems: saveItems
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                self.dragOffset = gesture.translation
                            }
                            .onEnded { gesture in
                                if abs(gesture.translation.width) > abs(gesture.translation.height) {
                                    if abs(gesture.translation.width) > UIScreen.main.bounds.width * 0.05 {
                                        changeCategoryOnSwipe(gesture.translation.width)
                                    }
                                }
                                self.dragOffset = .zero
                            }
                    )
                }

                AddButton(
                    showActionSheet: $showActionSheet,
                    showCamera: $showCamera,
                    showImagePicker: $showImagePicker
                )
            }
            .navigationDestination(for: NavigationTarget.self) { target in
                switch target {
                case .settings:
                    SettingsView()
                }
            }
        }
        .sheet(isPresented: $showManageCategories) {
            ManageCategoriesView(categoryStore: categoryStore)
        }
        .sheet(isPresented: $showImagePicker) {
            PhotoPicker(selectedImage: $selectedImage, shouldRemoveBackground: false)
                .onDisappear {
                    if selectedImage != nil {
                        isAddingNewItem = true
                    }
                }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker(selectedImage: $selectedImage)
                .onDisappear {
                    if selectedImage != nil {
                        isAddingNewItem = true
                    }
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
                brandStore: brandStore,
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
                brandStore: brandStore,
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

    private func changeCategoryOnSwipe(_ translationWidth: CGFloat) {
        guard !categoryNames.isEmpty else { return }

        if let currentIndex = categoryNames.firstIndex(of: selectedCategory) {
            var newIndex: Int
            if translationWidth < 0 {
                newIndex = (currentIndex + 1) % categoryNames.count
            } else {
                newIndex = (currentIndex - 1 + categoryNames.count) % categoryNames.count
            }

            if categoryNames[newIndex] != selectedCategory {
                selectedCategory = categoryNames[newIndex]
                triggerHapticFeedback()
            }
        }
    }

    private func triggerHapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
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


// MARK: - Subviews
struct HeaderView: View {
    var navigateToSettings: () -> Void

    var body: some View {
        HStack {
            Button(action: {
                navigateToSettings()
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .padding(.leading)
                    .foregroundStyle(.black)
            }

            Spacer()

            Text("My Things")
                .font(.title3)
                .bold()

            Spacer()

            Spacer().frame(width: 40)
        }
        .padding(.vertical)
    }
}


struct CategoryScrollView: View {
    let categoryNames: [String]
    @Binding var selectedCategory: String
    
    var body: some View {
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
    }
}

struct ItemsGridView: View {
    let filteredItems: [Item]
    @Binding var selectedItem: Item?
    @Binding var editingItem: Item?
    @Binding var items: [Item]
    let saveItems: () -> Void
    
    var body: some View {
        ScrollView {
            if filteredItems.isEmpty {
                EmptyStateView()
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(filteredItems) { item in
                        ItemCell(
                            item: item,
                            selectedItem: $selectedItem,
                            editingItem: $editingItem,
                            items: $items,
                            saveItems: saveItems
                        )
                    }
                }
                .padding()
            }
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
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
}

struct ItemCell: View {
    let item: Item
    @Binding var selectedItem: Item?
    @Binding var editingItem: Item?
    @Binding var items: [Item]
    let saveItems: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ItemImageView(imageName: item.imageName)
            
            Text("\(item.brand) · \(item.category)")
                .font(.caption)
                .foregroundColor(.gray)
            
            HStack {
                Text(item.name)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                if let price = Double(item.price) {
                    Text("$\(formattedPrice(price))")
                        .font(.caption2)
                        .foregroundColor(.gray)
                } else {
                    Text("$\(item.price)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
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
    
    private func formattedPrice(_ price: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: price)) ?? "\(price)"
    }
}

struct ItemImageView: View {
    let imageName: String
    
    var body: some View {
        let imagePath = FileManager.documentsDirectory.appendingPathComponent(imageName).path
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
        } else {
            ZStack {
                Color(.systemGray6)
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 60)
                    .foregroundColor(.gray)
            }
            .frame(height: 150)
            .cornerRadius(8)
        }
    }
}

struct AddButton: View {
    @Binding var showActionSheet: Bool
    @Binding var showCamera: Bool
    @Binding var showImagePicker: Bool
    
    var body: some View {
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
}

// MARK: - Helper Functions
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
