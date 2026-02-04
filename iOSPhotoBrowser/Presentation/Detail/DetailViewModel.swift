//
//  DetailViewModel.swift
//  iOSPhotoBrowser
//

import Foundation
import Combine
import UIKit

@MainActor
final class DetailViewModel: ObservableObject {
    @Published private(set) var photo: PhotoItem?
    @Published private(set) var allAlbums: [Album] = []
    @Published private(set) var isLoading = false
    @Published var newTagName = ""
    @Published var showingTagEditor = false
    @Published var showingAlbumSelector = false
    @Published var showingDeleteConfirmation = false
    @Published var error: Error?
    @Published var showingError = false

    let photoId: UUID
    private let imageRepository: ImageRepositoryProtocol
    private let tagRepository: TagRepositoryProtocol
    private let albumRepository: AlbumRepositoryProtocol
    private let deleteImageUseCase: DeleteImageUseCase

    init(
        photoId: UUID,
        imageRepository: ImageRepositoryProtocol,
        tagRepository: TagRepositoryProtocol,
        albumRepository: AlbumRepositoryProtocol,
        deleteImageUseCase: DeleteImageUseCase
    ) {
        self.photoId = photoId
        self.imageRepository = imageRepository
        self.tagRepository = tagRepository
        self.albumRepository = albumRepository
        self.deleteImageUseCase = deleteImageUseCase
    }

    func loadPhoto() async {
        isLoading = true
        defer { isLoading = false }

        do {
            photo = try await imageRepository.fetch(byId: photoId)
        } catch {
            self.error = error
            showingError = true
        }
    }

    func addTag() async {
        guard !newTagName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let tagName = newTagName.trimmingCharacters(in: .whitespaces)
        let tag = Tag(name: tagName)

        do {
            try await tagRepository.addTag(tag, to: photoId)
            await loadPhoto()
            newTagName = ""
        } catch {
            self.error = error
            showingError = true
        }
    }

    func removeTag(_ tag: Tag) async {
        do {
            try await tagRepository.removeTag(tag, from: photoId)
            await loadPhoto()
        } catch {
            self.error = error
            showingError = true
        }
    }

    func deletePhoto() async -> Bool {
        guard let photo = photo else { return false }

        do {
            try await deleteImageUseCase.execute(photo)
            return true
        } catch {
            self.error = error
            showingError = true
            return false
        }
    }

    func loadImage() -> UIImage? {
        guard let photo = photo else { return nil }
        return FileStorageManager.shared.loadImage(fileName: photo.filePath)
    }

    func loadAlbums() async {
        do {
            allAlbums = try await albumRepository.fetchAll()
        } catch {
            self.error = error
            showingError = true
        }
    }

    func addToAlbum(_ album: Album) async {
        do {
            try await albumRepository.addImage(photoId, to: album.id)
            await loadPhoto()
        } catch {
            self.error = error
            showingError = true
        }
    }

    func removeFromAlbum(_ album: Album) async {
        do {
            try await albumRepository.removeImage(photoId, from: album.id)
            await loadPhoto()
        } catch {
            self.error = error
            showingError = true
        }
    }

    func isInAlbum(_ album: Album) -> Bool {
        photo?.albums.contains { $0.id == album.id } ?? false
    }
}
