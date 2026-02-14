//
//  POIInfoRepository.swift
//  iOSPhotoBrowser
//

import Foundation
import CoreData

final class POIInfoRepository: POIInfoRepositoryProtocol {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func save(_ poiInfo: POIInfo, for imageId: UUID) async throws {
        try await context.perform {
            let imageRequest = ImageEntity.fetchRequest()
            imageRequest.predicate = NSPredicate(format: "id == %@", imageId as CVarArg)
            imageRequest.fetchLimit = 1

            guard let imageEntity = try self.context.fetch(imageRequest).first else {
                throw RepositoryError.notFound
            }

            let entity = POIInfoEntity(context: self.context)
            entity.id = poiInfo.id
            entity.name = poiInfo.name
            entity.address = poiInfo.address
            entity.phoneNumber = poiInfo.phoneNumber
            entity.businessHours = poiInfo.businessHours
            entity.websiteUrl = poiInfo.websiteUrl
            entity.category = poiInfo.category
            entity.priceRange = poiInfo.priceRange
            entity.notes = poiInfo.notes
            entity.rating = poiInfo.rating
            entity.visitStatus = poiInfo.visitStatus.rawValue
            entity.latitude = poiInfo.latitude ?? 0
            entity.longitude = poiInfo.longitude ?? 0
            entity.createdAt = poiInfo.createdAt
            entity.updatedAt = poiInfo.updatedAt

            entity.image = imageEntity
            imageEntity.poiInfo = entity

            try self.context.save()
        }
    }

    func fetch(for imageId: UUID) async throws -> POIInfo? {
        try await context.perform {
            let imageRequest = ImageEntity.fetchRequest()
            imageRequest.predicate = NSPredicate(format: "id == %@", imageId as CVarArg)
            imageRequest.fetchLimit = 1

            guard let imageEntity = try self.context.fetch(imageRequest).first,
                  let poiInfoEntity = imageEntity.poiInfo else {
                return nil
            }

            return self.toPOIInfo(poiInfoEntity)
        }
    }

    func update(_ poiInfo: POIInfo) async throws {
        try await context.perform {
            let request = POIInfoEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", poiInfo.id as CVarArg)
            request.fetchLimit = 1

            guard let entity = try self.context.fetch(request).first else {
                throw RepositoryError.notFound
            }

            entity.name = poiInfo.name
            entity.address = poiInfo.address
            entity.phoneNumber = poiInfo.phoneNumber
            entity.businessHours = poiInfo.businessHours
            entity.websiteUrl = poiInfo.websiteUrl
            entity.category = poiInfo.category
            entity.priceRange = poiInfo.priceRange
            entity.notes = poiInfo.notes
            entity.rating = poiInfo.rating
            entity.visitStatus = poiInfo.visitStatus.rawValue
            entity.latitude = poiInfo.latitude ?? 0
            entity.longitude = poiInfo.longitude ?? 0
            entity.updatedAt = Date()

            try self.context.save()
        }
    }

    func delete(for imageId: UUID) async throws {
        try await context.perform {
            let imageRequest = ImageEntity.fetchRequest()
            imageRequest.predicate = NSPredicate(format: "id == %@", imageId as CVarArg)
            imageRequest.fetchLimit = 1

            guard let imageEntity = try self.context.fetch(imageRequest).first,
                  let poiInfoEntity = imageEntity.poiInfo else {
                return
            }

            self.context.delete(poiInfoEntity)
            try self.context.save()
        }
    }

    // MARK: - Private Helpers

    private func toPOIInfo(_ entity: POIInfoEntity) -> POIInfo {
        POIInfo(
            id: entity.id ?? UUID(),
            name: entity.name,
            address: entity.address,
            phoneNumber: entity.phoneNumber,
            businessHours: entity.businessHours,
            websiteUrl: entity.websiteUrl,
            category: entity.category,
            priceRange: entity.priceRange,
            notes: entity.notes,
            rating: entity.rating,
            visitStatus: VisitStatus(rawValue: entity.visitStatus) ?? .wantToVisit,
            latitude: entity.latitude == 0 ? nil : entity.latitude,
            longitude: entity.longitude == 0 ? nil : entity.longitude,
            createdAt: entity.createdAt ?? Date(),
            updatedAt: entity.updatedAt ?? Date()
        )
    }
}
