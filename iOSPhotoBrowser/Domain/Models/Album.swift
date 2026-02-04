//
//  Album.swift
//  iOSPhotoBrowser
//

import Foundation

struct Album: Identifiable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date
    var updatedAt: Date
    var coverImageId: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        coverImageId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.coverImageId = coverImageId
    }
}
