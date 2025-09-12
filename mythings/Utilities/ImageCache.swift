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

    /// 從 Images 資料夾載入圖片（含防呆）
    func loadImage(named imageName: String, completion: @escaping (UIImage?) -> Void) {
        // 1) 避免空字串
        let trimmed = imageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { completion(nil); return }

        // 2) 僅取檔名，避免整條 path
        let fileName = (trimmed as NSString).lastPathComponent

        if let cached = get(fileName) {
            completion(cached)
            return
        }

        let fileURL = FileManager.imagesDirectory.appendingPathComponent(fileName)

        DispatchQueue.global(qos: .userInitiated).async {
            // 3) 確保不是資料夾
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir),
                  !isDir.boolValue
            else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let img = UIImage(contentsOfFile: fileURL.path)
            if let img { self.set(fileName, image: img) }
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
