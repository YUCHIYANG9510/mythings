//
//  ImageCache.swift
//  mythings
//
//  Created by Designer on 2025/8/25.
//

import SwiftUI



final class ImageMemoryCache {
    static let shared = ImageMemoryCache()
    private let cache = NSCache<NSString, UIImage>()

    func get(_ key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func set(_ key: String, image: UIImage?) {
        guard let image else { return }
        cache.setObject(image, forKey: key as NSString)
    }

    // ✅ 新增：移除單一 key 與清空
    func remove(_ key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    func clear() {
        cache.removeAllObjects()
    }

    func loadImage(named imageName: String, completion: @escaping (UIImage?) -> Void) {
        if let cached = get(imageName) {
            completion(cached)
            return
        }
        let path = FileManager.documentsDirectory.appendingPathComponent(imageName).path
        DispatchQueue.global(qos: .userInitiated).async {
            let img = UIImage(contentsOfFile: path)
            if let img { self.set(imageName, image: img) }
            DispatchQueue.main.async { completion(img) }
        }
    }
}

class ImageCacheManager: ObservableObject {
    static let shared = ImageCacheManager()
    @Published var cacheInvalidationTrigger = UUID()

    // ✅ 新增：可指定 imageName，順便把記憶體快取清掉
    func invalidateCache(for imageName: String? = nil) {
        if let name = imageName {
            ImageMemoryCache.shared.remove(name)
        } else {
            ImageMemoryCache.shared.clear()
        }
        cacheInvalidationTrigger = UUID()
    }
}

