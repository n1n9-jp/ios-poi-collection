//
//  DeleteImageUseCase.swift
//  iOSPhotoBrowser
//

import Foundation

final class DeleteImageUseCase {
    private let imageRepository: ImageRepositoryProtocol
    private let storage: FileStorageManager
    private let cache: ThumbnailCache

    init(
        imageRepository: ImageRepositoryProtocol,
        storage: FileStorageManager = .shared,
        cache: ThumbnailCache = .shared
    ) {
        self.imageRepository = imageRepository
        self.storage = storage
        self.cache = cache
    }

    func execute(_ photo: PhotoItem) async throws {
        // 1. Delete from database
        try await imageRepository.delete(photo)

        // 2. Delete original image file
        try storage.deleteImage(fileName: photo.filePath)

        // 3. Delete thumbnail
        if let thumbnailPath = photo.thumbnailPath {
            try storage.deleteThumbnail(fileName: thumbnailPath)
        }

        // 4. Clear from cache
        cache.remove(for: photo.id)
    }
}
