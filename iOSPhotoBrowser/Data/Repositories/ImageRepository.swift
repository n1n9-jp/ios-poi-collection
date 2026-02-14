//
//  ImageRepository.swift
//  iOSPhotoBrowser
//

import Foundation
import CoreData

final class ImageRepository: ImageRepositoryProtocol {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func fetchAll(sortedBy sortOption: SortOption) async throws -> [PhotoItem] {
        try await context.perform {
            let request = ImageEntity.fetchRequest()
            request.sortDescriptors = [sortOption.sortDescriptor]

            let entities = try self.context.fetch(request)
            return entities.map { self.toPhotoItem($0) }
        }
    }

    func fetch(byId id: UUID) async throws -> PhotoItem? {
        try await context.perform {
            let request = ImageEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1

            guard let entity = try self.context.fetch(request).first else {
                return nil
            }
            return self.toPhotoItem(entity)
        }
    }

    func save(_ image: PhotoItem) async throws {
        try await context.perform {
            let entity = ImageEntity(context: self.context)
            self.updateEntity(entity, from: image)
            try self.context.save()
        }
    }

    func update(_ image: PhotoItem) async throws {
        try await context.perform {
            let request = ImageEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", image.id as CVarArg)
            request.fetchLimit = 1

            guard let entity = try self.context.fetch(request).first else {
                throw RepositoryError.notFound
            }

            self.updateEntity(entity, from: image)
            try self.context.save()
        }
    }

    func delete(_ image: PhotoItem) async throws {
        try await context.perform {
            let request = ImageEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", image.id as CVarArg)
            request.fetchLimit = 1

            guard let entity = try self.context.fetch(request).first else {
                throw RepositoryError.notFound
            }

            self.context.delete(entity)
            try self.context.save()
        }
    }

    func search(byTag tagName: String) async throws -> [PhotoItem] {
        try await context.perform {
            let request = ImageEntity.fetchRequest()
            request.predicate = NSPredicate(format: "ANY tags.name == %@", tagName)
            request.sortDescriptors = [NSSortDescriptor(key: "importedAt", ascending: false)]

            let entities = try self.context.fetch(request)
            return entities.map { self.toPhotoItem($0) }
        }
    }

    func fetchImages(inAlbum albumId: UUID) async throws -> [PhotoItem] {
        try await context.perform {
            let request = ImageEntity.fetchRequest()
            request.predicate = NSPredicate(format: "ANY albums.id == %@", albumId as CVarArg)
            request.sortDescriptors = [NSSortDescriptor(key: "importedAt", ascending: false)]

            let entities = try self.context.fetch(request)
            return entities.map { self.toPhotoItem($0) }
        }
    }

    func updateExtractedText(imageId: UUID, text: String, processedAt: Date) async throws {
        try await context.perform {
            let request = ImageEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", imageId as CVarArg)
            request.fetchLimit = 1

            guard let entity = try self.context.fetch(request).first else {
                throw RepositoryError.notFound
            }

            entity.extractedText = text
            entity.ocrProcessedAt = processedAt
            try self.context.save()
        }
    }

    func search(query: String) async throws -> [PhotoItem] {
        try await context.perform {
            let request = ImageEntity.fetchRequest()
            let predicates: [NSPredicate] = [
                NSPredicate(format: "ANY tags.name CONTAINS[cd] %@", query),
                NSPredicate(format: "extractedText CONTAINS[cd] %@", query),
                NSPredicate(format: "poiInfo.name CONTAINS[cd] %@", query),
                NSPredicate(format: "poiInfo.address CONTAINS[cd] %@", query),
                NSPredicate(format: "poiInfo.category CONTAINS[cd] %@", query)
            ]
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
            request.sortDescriptors = [NSSortDescriptor(key: "importedAt", ascending: false)]

            let entities = try self.context.fetch(request)
            return entities.map { self.toPhotoItem($0) }
        }
    }

    // MARK: - Private Helpers

    private func toPhotoItem(_ entity: ImageEntity) -> PhotoItem {
        let tags: [Tag] = (entity.tags as? Set<TagEntity>)?.map { tagEntity in
            Tag(
                id: tagEntity.id ?? UUID(),
                name: tagEntity.name ?? "",
                createdAt: tagEntity.createdAt ?? Date(),
                updatedAt: tagEntity.updatedAt ?? Date()
            )
        } ?? []

        let albums: [Album] = (entity.albums as? Set<AlbumEntity>)?.map { albumEntity in
            Album(
                id: albumEntity.id ?? UUID(),
                name: albumEntity.name ?? "",
                createdAt: albumEntity.createdAt ?? Date(),
                updatedAt: albumEntity.updatedAt ?? Date(),
                coverImageId: albumEntity.coverImageId
            )
        } ?? []

        var poiInfo: POIInfo?
        if let poiInfoEntity = entity.poiInfo {
            poiInfo = POIInfo(
                id: poiInfoEntity.id ?? UUID(),
                name: poiInfoEntity.name,
                address: poiInfoEntity.address,
                phoneNumber: poiInfoEntity.phoneNumber,
                businessHours: poiInfoEntity.businessHours,
                websiteUrl: poiInfoEntity.websiteUrl,
                category: poiInfoEntity.category,
                priceRange: poiInfoEntity.priceRange,
                notes: poiInfoEntity.notes,
                rating: poiInfoEntity.rating,
                visitStatus: VisitStatus(rawValue: poiInfoEntity.visitStatus) ?? .wantToVisit,
                latitude: poiInfoEntity.latitude == 0 ? nil : poiInfoEntity.latitude,
                longitude: poiInfoEntity.longitude == 0 ? nil : poiInfoEntity.longitude,
                createdAt: poiInfoEntity.createdAt ?? Date(),
                updatedAt: poiInfoEntity.updatedAt ?? Date()
            )
        }

        return PhotoItem(
            id: entity.id ?? UUID(),
            fileName: entity.fileName ?? "",
            filePath: entity.filePath ?? "",
            thumbnailPath: entity.thumbnailPath,
            width: Int(entity.width),
            height: Int(entity.height),
            orientation: Int(entity.orientation),
            capturedAt: entity.capturedAt,
            importedAt: entity.importedAt ?? Date(),
            latitude: entity.latitude,
            longitude: entity.longitude,
            cameraMake: entity.cameraMake,
            cameraModel: entity.cameraModel,
            fileSize: entity.fileSize,
            tags: tags,
            albums: albums,
            extractedText: entity.extractedText,
            ocrProcessedAt: entity.ocrProcessedAt,
            poiInfo: poiInfo
        )
    }

    private func updateEntity(_ entity: ImageEntity, from image: PhotoItem) {
        entity.id = image.id
        entity.fileName = image.fileName
        entity.filePath = image.filePath
        entity.thumbnailPath = image.thumbnailPath
        entity.width = Int32(image.width)
        entity.height = Int32(image.height)
        entity.orientation = Int16(image.orientation)
        entity.capturedAt = image.capturedAt
        entity.importedAt = image.importedAt
        entity.latitude = image.latitude ?? 0
        entity.longitude = image.longitude ?? 0
        entity.cameraMake = image.cameraMake
        entity.cameraModel = image.cameraModel
        entity.fileSize = image.fileSize
    }
}

enum RepositoryError: Error {
    case notFound
    case saveFailed
}
