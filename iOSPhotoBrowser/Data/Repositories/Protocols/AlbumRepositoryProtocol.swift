//
//  AlbumRepositoryProtocol.swift
//  iOSPhotoBrowser
//

import Foundation

protocol AlbumRepositoryProtocol {
    func fetchAll() async throws -> [Album]
    func fetch(byId id: UUID) async throws -> Album?
    func save(_ album: Album) async throws
    func update(_ album: Album) async throws
    func delete(_ album: Album) async throws
    func addImage(_ imageId: UUID, to albumId: UUID) async throws
    func removeImage(_ imageId: UUID, from albumId: UUID) async throws
    func fetchImageCount(for albumId: UUID) async throws -> Int
}
