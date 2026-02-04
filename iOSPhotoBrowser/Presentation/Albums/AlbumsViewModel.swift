//
//  AlbumsViewModel.swift
//  iOSPhotoBrowser
//

import Foundation
import Combine

@MainActor
final class AlbumsViewModel: ObservableObject {
    @Published private(set) var albums: [Album] = []
    @Published private(set) var albumImageCounts: [UUID: Int] = [:]
    @Published private(set) var isLoading = false
    @Published var showingCreateSheet = false
    @Published var newAlbumName = ""
    @Published var error: Error?
    @Published var showingError = false

    private let albumRepository: AlbumRepositoryProtocol
    private let imageRepository: ImageRepositoryProtocol

    init(
        albumRepository: AlbumRepositoryProtocol,
        imageRepository: ImageRepositoryProtocol
    ) {
        self.albumRepository = albumRepository
        self.imageRepository = imageRepository
    }

    func loadAlbums() async {
        isLoading = true
        defer { isLoading = false }

        do {
            albums = try await albumRepository.fetchAll()

            // Load image counts for each album
            for album in albums {
                let count = try await albumRepository.fetchImageCount(for: album.id)
                albumImageCounts[album.id] = count
            }
        } catch {
            self.error = error
            showingError = true
        }
    }

    func createAlbum() async {
        guard !newAlbumName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let album = Album(name: newAlbumName.trimmingCharacters(in: .whitespaces))

        do {
            try await albumRepository.save(album)
            await loadAlbums()
            newAlbumName = ""
            showingCreateSheet = false
        } catch {
            self.error = error
            showingError = true
        }
    }

    func deleteAlbum(_ album: Album) async {
        do {
            try await albumRepository.delete(album)
            albums.removeAll { $0.id == album.id }
        } catch {
            self.error = error
            showingError = true
        }
    }

    func updateAlbum(_ album: Album, name: String) async {
        var updatedAlbum = album
        updatedAlbum.name = name
        updatedAlbum.updatedAt = Date()

        do {
            try await albumRepository.update(updatedAlbum)
            await loadAlbums()
        } catch {
            self.error = error
            showingError = true
        }
    }
}
