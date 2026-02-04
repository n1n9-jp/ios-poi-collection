//
//  ThumbnailGenerationService.swift
//  iOSPhotoBrowser
//

import Foundation
import UIKit

actor ThumbnailGenerationService {
    static let shared = ThumbnailGenerationService()

    private let cache = ThumbnailCache.shared
    private let storage = FileStorageManager.shared
    private let targetSize = CGSize(width: 300, height: 300)

    private init() {}

    func generate(from data: Data, id: UUID) async throws -> String {
        // Check cache first
        if let _ = cache.get(for: id) {
            return "\(id.uuidString)_thumb.jpg"
        }

        // Generate thumbnail
        guard let image = UIImage(data: data) else {
            throw ThumbnailError.invalidData
        }

        let thumbnail = await resize(image: image, to: targetSize)

        // Save to disk
        let fileName = try storage.saveThumbnail(thumbnail, id: id)

        // Store in memory cache
        cache.set(thumbnail, for: id)

        return fileName
    }

    func generate(from image: UIImage, id: UUID) async throws -> String {
        // Check cache first
        if let _ = cache.get(for: id) {
            return "\(id.uuidString)_thumb.jpg"
        }

        let thumbnail = await resize(image: image, to: targetSize)

        // Save to disk
        let fileName = try storage.saveThumbnail(thumbnail, id: id)

        // Store in memory cache
        cache.set(thumbnail, for: id)

        return fileName
    }

    private func resize(image: UIImage, to targetSize: CGSize) async -> UIImage {
        let size = image.size

        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        let ratio = max(widthRatio, heightRatio)

        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            let origin = CGPoint(
                x: (targetSize.width - newSize.width) / 2,
                y: (targetSize.height - newSize.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: newSize))
        }
    }
}

enum ThumbnailError: Error {
    case invalidData
    case generationFailed
    case saveFailed
}
