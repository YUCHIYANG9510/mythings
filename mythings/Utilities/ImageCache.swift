//
//  ImageCache.swift
//  mythings
//
//  Created by Designer on 2025/8/25.
//

import SwiftUI

// MARK: - 小工具：取 Images 資料夾路徑
extension FileManager {
    static var imagesDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Images", isDirectory: true)
        // 確保資料夾存在
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

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

    func remove(_ key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    func clear() {
        cache.removeAllObjects()
    }

    /// 從 Images 資料夾載入圖片
    func loadImage(named imageName: String, completion: @escaping (UIImage?) -> Void) {
        if let cached = get(imageName) {
            completion(cached)
            return
        }

        let fileURL = FileManager.imagesDirectory.appendingPathComponent(imageName)
        DispatchQueue.global(qos: .userInitiated).async {
            let img = UIImage(contentsOfFile: fileURL.path)
            if let img { self.set(imageName, image: img) }
            DispatchQueue.main.async { completion(img) }
        }
    }
}

class ImageCacheManager: ObservableObject {
    static let shared = ImageCacheManager()
    @Published var cacheInvalidationTrigger = UUID()

    func invalidateCache(for imageName: String? = nil) {
        if let name = imageName {
            ImageMemoryCache.shared.remove(name)
        } else {
            ImageMemoryCache.shared.clear()
        }
        cacheInvalidationTrigger = UUID()
    }
}
