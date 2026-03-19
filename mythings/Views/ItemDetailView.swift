//
//  ItemDetailView.swift
//  mythings
//

import SwiftUI
import UIKit

extension UIDevice {
    static var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
}

struct ItemDetailView: View {
    let categoryStore: CategoryStore
    let brandStore: BrandStore
    var onEdited: ((Item) -> Void)? = nil

    @State private var item: Item
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @StateObject private var cacheManager = ImageCacheManager.shared

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
        if UIDevice.isIPad {
            iPadLayout
        } else {
            iPhoneLayout
        }
    }

    // MARK: - iPhone 排版

    private var iPhoneLayout: some View {
        VStack(spacing: 8) {
            HStack {
                if let d = item.date {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .foregroundColor(.secondary)
                        Text(Self.isoFormatter.string(from: d))
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundColor(.primary)
                    }
                } else {
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
            .padding(.vertical, 8)

            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 300)
                    .padding(.horizontal)
            }

            Text(item.name)
                .font(.title2)
                .padding(.top, 6)

            // ✅ 核心改動：從 categoryStore 用 UUID 查 name，不再讀 item.category
            Text("\(item.brand) · \(categoryStore.name(for: item.categoryID))")
                .foregroundColor(.gray)

            Text(formattedPrice(from: item.price))
                .font(.callout)
                .padding(.top, 2)
        }
        .padding(.bottom)
        .onTapGesture { dismiss() }
        .onAppear(perform: loadImage)
        .onChangeCompat(of: cacheManager.cacheInvalidationTrigger) { loadImage() }
        .sheet(isPresented: $showEdit) {
            AddItemView(
                selectedImage: Binding(get: { editImage }, set: { editImage = $0 }),
                existingItem: item,
                categoryStore: categoryStore,
                brandStore: brandStore,
                showManageCategories: .constant(false)
            ) { updated in
                handleItemUpdate(updated)
            }
        }
    }

    // MARK: - iPad 排版

    private var iPadLayout: some View {
        VStack(spacing: 8) {
            HStack {
                if let d = item.date {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .foregroundColor(.secondary)
                        Text(Self.isoFormatter.string(from: d))
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundColor(.primary)
                    }
                } else {
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
            .padding(.vertical, 8)

            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 400)
                    .padding(.horizontal)
            }

            Text(item.name)
                .font(.title2)
                .padding(.top, 6)

            // ✅ 核心改動：從 categoryStore 用 UUID 查 name
            Text("\(item.brand) · \(categoryStore.name(for: item.categoryID))")
                .foregroundColor(.gray)

            Text(formattedPrice(from: item.price))
                .font(.callout)
                .padding(.top, 2)
        }
        .padding(.bottom)
        .frame(maxWidth: 600)
        .onTapGesture { dismiss() }
        .onAppear(perform: loadImage)
        .onChangeCompat(of: cacheManager.cacheInvalidationTrigger) { loadImage() }
        .sheet(isPresented: $showEdit) {
            AddItemView(
                selectedImage: Binding(get: { editImage }, set: { editImage = $0 }),
                existingItem: item,
                categoryStore: categoryStore,
                brandStore: brandStore,
                showManageCategories: .constant(false)
            ) { updated in
                handleItemUpdate(updated)
            }
        }
    }

    // MARK: - 共用方法

    private func loadImage() {
        let fileName = (item.imageName as NSString).lastPathComponent
        guard !fileName.isEmpty else {
            image = nil
            return
        }
        ImageMemoryCache.shared.loadImage(named: fileName) { img in
            self.image = img
        }
    }

    private func formattedPrice(from raw: String) -> String {
        let digits = raw.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        guard let value = Double(digits) else {
            return raw.hasPrefix("$") ? raw : "$" + raw
        }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.usesGroupingSeparator = true
        let grouped = f.string(from: NSNumber(value: value)) ?? digits
        return "$" + grouped
    }

    private func handleItemUpdate(_ updated: Item) {
        let oldName = item.imageName
        self.item = updated
        self.editImage = nil

        ImageCacheManager.shared.invalidateCache(for: oldName)
        if oldName != updated.imageName {
            ImageCacheManager.shared.invalidateCache(for: updated.imageName)
        }
        loadImage()

        showEdit = false
        onEdited?(updated)
    }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
