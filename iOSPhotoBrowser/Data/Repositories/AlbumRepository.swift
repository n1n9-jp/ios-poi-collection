//
//  AlbumRepository.swift
//  iOSPhotoBrowser
//

import Foundation
import CoreData

final class AlbumRepository: AlbumRepositoryProtocol {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func fetchAll() async throws -> [Album] {
        try await context.perform {
            let request = AlbumEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

            let entities = try self.context.fetch(request)
            return entities.map { self.toAlbum($0) }
        }
    }

    func fetch(byId id: UUID) async throws -> Album? {
        try await context.perform {
            let request = AlbumEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1

            guard let entity = try self.context.fetch(request).first else {
                return nil
            }
            return self.toAlbum(entity)
        }
    }

    func save(_ album: Album) async throws {
        try await context.perform {
            let entity = AlbumEntity(context: self.context)
            entity.id = album.id
            entity.name = album.name
            entity.createdAt = album.createdAt
            entity.updatedAt = album.updatedAt
            entity.coverImageId = album.coverImageId
            try self.context.save()
        }
    }

    func update(_ album: Album) async throws {
        try await context.perform {
            let request = AlbumEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", album.id as CVarArg)
            request.fetchLimit = 1

            guard let entity = try self.context.fetch(request).first else {
                throw RepositoryError.notFound
            }

            entity.name = album.name
            entity.updatedAt = album.updatedAt
            entity.coverImageId = album.coverImageId
            try self.context.save()
        }
    }

    func delete(_ album: Album) async throws {
        try await context.perform {
            let request = AlbumEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", album.id as CVarArg)
            request.fetchLimit = 1

            guard let entity = try self.context.fetch(request).first else {
                throw RepositoryError.notFound
            }

            self.context.delete(entity)
            try self.context.save()
        }
    }

    func addImage(_ imageId: UUID, to albumId: UUID) async throws {
        try await context.perform {
            let albumRequest = AlbumEntity.fetchRequest()
            albumRequest.predicate = NSPredicate(format: "id == %@", albumId as CVarArg)
            albumRequest.fetchLimit = 1

            guard let albumEntity = try self.context.fetch(albumRequest).first else {
                throw RepositoryError.notFound
            }

            let imageRequest = ImageEntity.fetchRequest()
            imageRequest.predicate = NSPredicate(format: "id == %@", imageId as CVarArg)
            imageRequest.fetchLimit = 1

            guard let imageEntity = try self.context.fetch(imageRequest).first else {
                throw RepositoryError.notFound
            }

            albumEntity.addToImages(imageEntity)

            // Set cover image if not set
            if albumEntity.coverImageId == nil {
                albumEntity.coverImageId = imageId
            }

            try self.context.save()
        }
    }

    func removeImage(_ imageId: UUID, from albumId: UUID) async throws {
        try await context.perform {
            let albumRequest = AlbumEntity.fetchRequest()
            albumRequest.predicate = NSPredicate(format: "id == %@", albumId as CVarArg)
            albumRequest.fetchLimit = 1

            guard let albumEntity = try self.context.fetch(albumRequest).first else {
                throw RepositoryError.notFound
            }

            let imageRequest = ImageEntity.fetchRequest()
            imageRequest.predicate = NSPredicate(format: "id == %@", imageId as CVarArg)
            imageRequest.fetchLimit = 1

            guard let imageEntity = try self.context.fetch(imageRequest).first else {
                throw RepositoryError.notFound
            }

            albumEntity.removeFromImages(imageEntity)
            try self.context.save()
        }
    }

    func fetchImageCount(for albumId: UUID) async throws -> Int {
        try await context.perform {
            let request = AlbumEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", albumId as CVarArg)
            request.fetchLimit = 1

            guard let entity = try self.context.fetch(request).first else {
                return 0
            }

            return entity.images?.count ?? 0
        }
    }

    private func toAlbum(_ entity: AlbumEntity) -> Album {
        Album(
            id: entity.id ?? UUID(),
            name: entity.name ?? "",
            createdAt: entity.createdAt ?? Date(),
            updatedAt: entity.updatedAt ?? Date(),
            coverImageId: entity.coverImageId
        )
    }
}
