//
//  LibraryViewModel.swift
//  iOSPhotoBrowser
//

import Foundation
import Combine

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var photos: [PhotoItem] = []
    @Published private(set) var isLoading = false
    @Published var sortOption: SortOption = .importedAtDescending
    @Published var error: Error?
    @Published var showingError = false

    private let imageRepository: ImageRepositoryProtocol
    private let deleteImageUseCase: DeleteImageUseCase

    init(
        imageRepository: ImageRepositoryProtocol,
        deleteImageUseCase: DeleteImageUseCase
    ) {
        self.imageRepository = imageRepository
        self.deleteImageUseCase = deleteImageUseCase
    }

    func loadPhotos() async {
        isLoading = true
        defer { isLoading = false }

        do {
            photos = try await imageRepository.fetchAll(sortedBy: sortOption)
        } catch {
            self.error = error
            showingError = true
        }
    }

    func deletePhoto(_ photo: PhotoItem) async {
        do {
            try await deleteImageUseCase.execute(photo)
            photos.removeAll { $0.id == photo.id }
        } catch {
            self.error = error
            showingError = true
        }
    }

    func changeSortOption(_ option: SortOption) {
        sortOption = option
        Task {
            await loadPhotos()
        }
    }
}
