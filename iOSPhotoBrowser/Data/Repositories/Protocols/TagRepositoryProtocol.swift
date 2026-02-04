//
//  TagRepositoryProtocol.swift
//  iOSPhotoBrowser
//

import Foundation

protocol TagRepositoryProtocol {
    func fetchAll() async throws -> [Tag]
    func fetch(byId id: UUID) async throws -> Tag?
    func fetch(byName name: String) async throws -> Tag?
    func save(_ tag: Tag) async throws
    func delete(_ tag: Tag) async throws
    func addTag(_ tag: Tag, to imageId: UUID) async throws
    func removeTag(_ tag: Tag, from imageId: UUID) async throws
}
