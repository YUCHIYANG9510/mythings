//
//  ItemDetailView.swift
//  mythings
//
//  Created by Designer on 2025/4/29.
//

import SwiftUI
import UIKit



struct ItemDetailView: View {
    // 必要參數
    let categoryStore: CategoryStore
    let brandStore: BrandStore
    var onEdited: ((Item) -> Void)? = nil

    // 內部狀態：用 state 保存目前顯示的 item（編輯後可即時更新）
    @State private var item: Item
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @StateObject private var cacheManager = ImageCacheManager.shared

    // 開啟編輯用
    @State private var showEdit = false
    @State private var editImage: UIImage?

    init(item: Item,
         categoryStore: CategoryStore,
         brandStore: BrandStore,
         onEdited: ((Item) -> Void)? = nil) {
        self._item = State(initialValue: item)
        self.categoryStore = categoryStore
        self.brandStore = brandStore
        self.onEdited = onEdited
    }

    var body: some View {
        VStack(spacing: 8) {

            // Top bar: 左邊日期、右邊編輯
            HStack {
                if let d = item.date {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .foregroundColor(.secondary)
                        Text(Self.isoFormatter.string(from: d))
                            .font(.callout)
                            .monospacedDigit() // 等寬數字
                            .foregroundColor(.primary)
                    }
                } else {
                    // 沒日期就留空間或什麼都不放
                    Spacer().frame(height: 0)
                }

                Spacer()

                Button {
                    editImage = image
                    showEdit = true
                } label: {
                    Image("icon_pen")
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)
            .padding(.top, 12)

            // 圖片
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 300)
                    .padding(.horizontal)
            }

            // 文字資訊
            Text(item.name)
                .font(.title2)
                .padding(.top, 6)

            Text("\(item.brand) · \(item.category)")
                .foregroundColor(.gray)

            Text(formattedPrice(from: item.price))
                .font(.callout)
                .padding(.top, 2)
        }
        .padding(.bottom)
        .onTapGesture { dismiss() }
        .onAppear(perform: loadImage)
        .onChangeCompat(of: cacheManager.cacheInvalidationTrigger) { loadImage() }

        // 編輯 sheet
        .sheet(isPresented: $showEdit) {
            
            AddItemView(
                selectedImage: Binding(get: { editImage }, set: { editImage = $0 }),
                existingItem: item,
                categoryStore: categoryStore,
                brandStore: brandStore,
                showManageCategories: .constant(false)
            ) { updated in
                // 更新本畫面內容
                self.item = updated
                self.editImage = nil
                ImageCacheManager.shared.invalidateCache()
                loadImage()
                
                // ✅ 關閉編輯頁（sheet）
                showEdit = false
                
                // 回傳給外層讓資料保存
                onEdited?(updated)
            }
            
        }
    }

    private func loadImage() {
        let imagePath = FileManager.documentsDirectory.appendingPathComponent(item.imageName).path
        image = UIImage(contentsOfFile: imagePath)
    }
    
    private func formattedPrice(from raw: String) -> String {
        // 只取數字與小數點
        let digits = raw.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)

        guard let value = Double(digits) else {
            // 解析失敗就原樣（補一個 $）
            return raw.hasPrefix("$") ? raw : "$" + raw
        }

        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.usesGroupingSeparator = true

        let grouped = f.string(from: NSNumber(value: value)) ?? digits
        return "$" + grouped
    }


    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
