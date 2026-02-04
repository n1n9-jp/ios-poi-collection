//
//  TagRepository.swift
//  iOSPhotoBrowser
//

import Foundation
import CoreData

final class TagRepository: TagRepositoryProtocol {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func fetchAll() async throws -> [Tag] {
        try await context.perform {
            let request = TagEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

            let entities = try self.context.fetch(request)
            return entities.map { self.toTag($0) }
        }
    }

    func fetch(byId id: UUID) async throws -> Tag? {
        try await context.perform {
            let request = TagEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1

            guard let entity = try self.context.fetch(request).first else {
                return nil
            }
            return self.toTag(entity)
        }
    }

    func fetch(byName name: String) async throws -> Tag? {
        try await context.perform {
            let request = TagEntity.fetchRequest()
            request.predicate = NSPredicate(format: "name == %@", name)
            request.fetchLimit = 1

            guard let entity = try self.context.fetch(request).first else {
                return nil
            }
            return self.toTag(entity)
        }
    }

    func save(_ tag: Tag) async throws {
        try await context.perform {
            let entity = TagEntity(context: self.context)
            entity.id = tag.id
            entity.name = tag.name
            entity.createdAt = tag.createdAt
            entity.updatedAt = tag.updatedAt
            try self.context.save()
        }
    }

    func delete(_ tag: Tag) async throws {
        try await context.perform {
            let request = TagEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", tag.id as CVarArg)
            request.fetchLimit = 1

            guard let entity = try self.context.fetch(request).first else {
                throw RepositoryError.notFound
            }

            self.context.delete(entity)
            try self.context.save()
        }
    }

    func addTag(_ tag: Tag, to imageId: UUID) async throws {
        try await context.perform {
            let imageRequest = ImageEntity.fetchRequest()
            imageRequest.predicate = NSPredicate(format: "id == %@", imageId as CVarArg)
            imageRequest.fetchLimit = 1

            guard let imageEntity = try self.context.fetch(imageRequest).first else {
                throw RepositoryError.notFound
            }

            // Find or create tag
            let tagRequest = TagEntity.fetchRequest()
            tagRequest.predicate = NSPredicate(format: "name == %@", tag.name)
            tagRequest.fetchLimit = 1

            let tagEntity: TagEntity
            if let existing = try self.context.fetch(tagRequest).first {
                tagEntity = existing
            } else {
                tagEntity = TagEntity(context: self.context)
                tagEntity.id = tag.id
                tagEntity.name = tag.name
                tagEntity.createdAt = tag.createdAt
                tagEntity.updatedAt = tag.updatedAt
            }

            imageEntity.addToTags(tagEntity)
            try self.context.save()
        }
    }

    func removeTag(_ tag: Tag, from imageId: UUID) async throws {
        try await context.perform {
            let imageRequest = ImageEntity.fetchRequest()
            imageRequest.predicate = NSPredicate(format: "id == %@", imageId as CVarArg)
            imageRequest.fetchLimit = 1

            guard let imageEntity = try self.context.fetch(imageRequest).first else {
                throw RepositoryError.notFound
            }

            let tagRequest = TagEntity.fetchRequest()
            tagRequest.predicate = NSPredicate(format: "id == %@", tag.id as CVarArg)
            tagRequest.fetchLimit = 1

            guard let tagEntity = try self.context.fetch(tagRequest).first else {
                throw RepositoryError.notFound
            }

            imageEntity.removeFromTags(tagEntity)
            try self.context.save()
        }
    }

    private func toTag(_ entity: TagEntity) -> Tag {
        Tag(
            id: entity.id ?? UUID(),
            name: entity.name ?? "",
            createdAt: entity.createdAt ?? Date(),
            updatedAt: entity.updatedAt ?? Date()
        )
    }
}
