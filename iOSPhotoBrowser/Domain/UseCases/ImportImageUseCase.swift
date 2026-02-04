//
//  ImportImageUseCase.swift
//  iOSPhotoBrowser
//

import Foundation
import UIKit
import Photos

final class ImportImageUseCase {
    private let imageRepository: ImageRepositoryProtocol
    private let storage: FileStorageManager
    private let thumbnailService: ThumbnailGenerationService
    private let metadataService: MetadataExtractionService

    init(
        imageRepository: ImageRepositoryProtocol,
        storage: FileStorageManager = .shared,
        thumbnailService: ThumbnailGenerationService = .shared,
        metadataService: MetadataExtractionService = .shared
    ) {
        self.imageRepository = imageRepository
        self.storage = storage
        self.thumbnailService = thumbnailService
        self.metadataService = metadataService
    }

    func execute(imageData: Data, originalFileName: String) async throws -> PhotoItem {
        // 1. Generate unique ID
        let id = UUID()

        // 2. Extract metadata
        let metadata = metadataService.extract(from: imageData)

        // 3. Save original image
        let filePath = try storage.saveImage(data: imageData, id: id)

        // 4. Generate thumbnail (background)
        let thumbnailPath = try await thumbnailService.generate(from: imageData, id: id)

        // 5. Create PhotoItem
        let photo = PhotoItem(
            id: id,
            fileName: originalFileName,
            filePath: filePath,
            thumbnailPath: thumbnailPath,
            width: metadata.width,
            height: metadata.height,
            orientation: metadata.orientation,
            capturedAt: metadata.capturedAt,
            importedAt: Date(),
            latitude: metadata.latitude,
            longitude: metadata.longitude,
            cameraMake: metadata.cameraMake,
            cameraModel: metadata.cameraModel,
            fileSize: metadata.fileSize,
            tags: [],
            albums: []
        )

        // 6. Save to database
        try await imageRepository.save(photo)

        return photo
    }

    func execute(from asset: PHAsset) async throws -> PhotoItem {
        let photoService = PhotoLibraryService.shared
        let data = try await photoService.fetchImageData(from: asset)
        let fileName = photoService.getOriginalFileName(from: asset) ?? "image_\(UUID().uuidString).jpg"

        return try await execute(imageData: data, originalFileName: fileName)
    }

    func execute(from url: URL) async throws -> PhotoItem {
        let fileService = FileImportService.shared
        let data = try fileService.loadImageData(from: url)
        let fileName = fileService.getFileName(from: url)

        return try await execute(imageData: data, originalFileName: fileName)
    }
}
