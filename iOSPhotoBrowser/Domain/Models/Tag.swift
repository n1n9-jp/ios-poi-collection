//
//  Tag.swift
//  iOSPhotoBrowser
//

import Foundation

struct Tag: Identifiable, Hashable {
    let id: UUID
    let name: String
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
