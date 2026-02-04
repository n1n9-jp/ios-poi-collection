//
//  ThumbnailCache.swift
//  iOSPhotoBrowser
//

import Foundation
import UIKit

final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let memoryCache = NSCache<NSUUID, UIImage>()
    private let storageManager = FileStorageManager.shared

    private init() {
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }

    func get(for id: UUID) -> UIImage? {
        // Check memory cache first
        if let cached = memoryCache.object(forKey: id as NSUUID) {
            return cached
        }

        // Try disk cache
        let fileName = "\(id.uuidString)_thumb.jpg"
        if let diskCached = storageManager.loadThumbnail(fileName: fileName) {
            // Store in memory cache
            memoryCache.setObject(diskCached, forKey: id as NSUUID)
            return diskCached
        }

        return nil
    }

    func set(_ image: UIImage, for id: UUID) {
        memoryCache.setObject(image, forKey: id as NSUUID)
    }

    func remove(for id: UUID) {
        memoryCache.removeObject(forKey: id as NSUUID)
    }

    func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }
}
