//
//  DependencyContainer.swift
//  iOSPhotoBrowser
//

import Foundation

@MainActor
final class DependencyContainer {
    static let shared = DependencyContainer()

    // MARK: - Core
    let coreDataStack = CoreDataStack.shared

    // MARK: - Storage
    let fileStorage = FileStorageManager.shared
    let thumbnailCache = ThumbnailCache.shared

    // MARK: - Services
    let thumbnailService = ThumbnailGenerationService.shared
    let metadataService = MetadataExtractionService.shared
    let permissionService = PermissionService.shared
    let photoLibraryService = PhotoLibraryService.shared
    let fileImportService = FileImportService.shared

    // MARK: - Repositories
    lazy var imageRepository: ImageRepositoryProtocol = ImageRepository(
        context: coreDataStack.viewContext
    )
    lazy var tagRepository: TagRepositoryProtocol = TagRepository(
        context: coreDataStack.viewContext
    )
    lazy var albumRepository: AlbumRepositoryProtocol = AlbumRepository(
        context: coreDataStack.viewContext
    )

    // MARK: - UseCases
    lazy var importImageUseCase = ImportImageUseCase(
        imageRepository: imageRepository
    )
    lazy var deleteImageUseCase = DeleteImageUseCase(
        imageRepository: imageRepository
    )

    // MARK: - ViewModels
    func makeLibraryViewModel() -> LibraryViewModel {
        LibraryViewModel(
            imageRepository: imageRepository,
            deleteImageUseCase: deleteImageUseCase
        )
    }

    func makeImportViewModel() -> ImportViewModel {
        ImportViewModel(importImageUseCase: importImageUseCase)
    }

    func makeDetailViewModel(photoId: UUID) -> DetailViewModel {
        DetailViewModel(
            photoId: photoId,
            imageRepository: imageRepository,
            tagRepository: tagRepository,
            albumRepository: albumRepository,
            deleteImageUseCase: deleteImageUseCase
        )
    }

    func makeAlbumsViewModel() -> AlbumsViewModel {
        AlbumsViewModel(
            albumRepository: albumRepository,
            imageRepository: imageRepository
        )
    }

    func makeAlbumDetailViewModel(album: Album) -> AlbumDetailViewModel {
        AlbumDetailViewModel(
            album: album,
            albumRepository: albumRepository,
            imageRepository: imageRepository
        )
    }

    func makeTagsViewModel() -> TagsViewModel {
        TagsViewModel(tagRepository: tagRepository)
    }

    func makeSearchViewModel() -> SearchViewModel {
        SearchViewModel(imageRepository: imageRepository)
    }

    private init() {}
}
