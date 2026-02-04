//
//  ImageRepositoryProtocol.swift
//  iOSPhotoBrowser
//

import Foundation

protocol ImageRepositoryProtocol {
    func fetchAll(sortedBy: SortOption) async throws -> [PhotoItem]
    func fetch(byId id: UUID) async throws -> PhotoItem?
    func save(_ image: PhotoItem) async throws
    func update(_ image: PhotoItem) async throws
    func delete(_ image: PhotoItem) async throws
    func search(byTag tagName: String) async throws -> [PhotoItem]
    func fetchImages(inAlbum albumId: UUID) async throws -> [PhotoItem]
}
