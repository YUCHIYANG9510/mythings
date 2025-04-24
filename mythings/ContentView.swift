//
//  ContentView.swift
//  mythings
//
//  Created by Designer on 2025/4/23.
//

import SwiftUI
import PhotosUI

struct Item: Identifiable {
    let id = UUID()
    let imageName: String
    let brand: String
    let category: String
    let name: String
    let price: String
}

struct ContentView: View {
    let categories = ["All", "Tops", "Pants", "Outer", "Bags", "Shoes", "Other"]
    @State private var selectedCategory = "All"
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var showAddSheet = false
    @State private var items: [Item] = []
    
    
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
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(filteredItems) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    if let uiImage = UIImage(contentsOfFile: item.imageName) {
                                        ZStack {
                                            Color(.systemGray6) // 背景顏色與格子背景一致
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(height: 150)
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
                                        Text(item.price)
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                        }
                        .padding()
                    }
                }
            }
            
            // ✅ 固定在底部中央的 "+" 按鈕
            Button(action: {
                showImagePicker = true
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
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $selectedImage)
                .onDisappear {
                    if selectedImage != nil {
                        showAddSheet = true
                    }
                }
        }
        .sheet(isPresented: $showAddSheet) {
            AddItemView(selectedImage: $selectedImage) { newItem in
                items.append(newItem)
            }
        }
    }
    
    
    
    struct ImagePicker: UIViewControllerRepresentable {
        @Binding var selectedImage: UIImage?
        
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
            let parent: ImagePicker
            
            init(_ parent: ImagePicker) {
                self.parent = parent
            }
            
            func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
                picker.dismiss(animated: true)
                
                guard let provider = results.first?.itemProvider,
                      provider.canLoadObject(ofClass: UIImage.self) else { return }
                
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    DispatchQueue.main.async {
                        self.parent.selectedImage = image as? UIImage
                    }
                }
            }
        }
    }
}

struct AddItemView: View {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) var dismiss
    var onSave: (Item) -> Void
    @State private var name = ""
    @State private var brand = ""
    @State private var category = "Top"
    @State private var price = ""

    let categories = ["Top", "Pants", "Outer", "Shoes", "Bags", "Other"]

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

                Picker("Category", selection: $category) {
                    ForEach(categories, id: \.self) {
                        Text($0)
                    }
                }
            }
            .navigationTitle("Add item")
            
            .navigationBarItems(leading: Button("Cancel") {
                dismiss()
            }, trailing: Button("Save") {
                guard let image = selectedImage else { return }

                                // ✅ 儲存圖片到臨時路徑
                                let filename = UUID().uuidString + ".png"
                                let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                                if let data = image.pngData() {
                                    try? data.write(to: url)
                                }

                                let newItem = Item(
                                    imageName: url.path,
                                    brand: brand,
                                    category: category,
                                    name: name,
                                    price: "$\(price)"
                                )

                                onSave(newItem)
                dismiss()
            })
        }
    }
}


#Preview {
    ContentView()
}
