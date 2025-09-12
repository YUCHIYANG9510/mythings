//
//  CachedLocalImage.swift
//  mythings
//
//  Created by Designer on 2025/9/12.
//

import SwiftUI

struct CachedLocalImage: View {
    let imageName: String
    let cornerRadius: CGFloat
    let contentMode: ContentMode   // .fill or .fit
    let showsPlaceholder: Bool

    @State private var uiImage: UIImage?
    @State private var isLoading = false
    @ObservedObject private var cacheMgr = ImageCacheManager.shared

    init(
        _ imageName: String,
        cornerRadius: CGFloat = 12,
        contentMode: ContentMode = .fill,
        showsPlaceholder: Bool = true
    ) {
        self.imageName = (imageName as NSString).lastPathComponent
        self.cornerRadius = cornerRadius
        self.contentMode = contentMode
        self.showsPlaceholder = showsPlaceholder
    }

    var body: some View {
        ZStack {
            if let img = uiImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .clipped()
            } else if isLoading {
                ProgressView()
            } else if showsPlaceholder {
                Rectangle().opacity(0.06)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 22, weight: .light))
                            .opacity(0.35)
                    )
            }
        }
        .background(Color.black.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear(perform: load)
        .onChange(of: cacheMgr.cacheInvalidationTrigger) { _ in reload() }
        .onChange(of: imageName) { _ in reload() }
    }

    private func load() {
        let key = imageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isLoading = true
        ImageMemoryCache.shared.loadImage(named: key) { img in
            self.uiImage = img
            self.isLoading = false
        }
    }

    private func reload() {
        self.uiImage = nil
        load()
    }
}
