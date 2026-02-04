//
//  ImportViewModel.swift
//  iOSPhotoBrowser
//

import Foundation
import Combine
import Photos
import PhotosUI
import SwiftUI

@MainActor
final class ImportViewModel: ObservableObject {
    @Published private(set) var isImporting = false
    @Published private(set) var importProgress: Double = 0
    @Published private(set) var importedCount = 0
    @Published private(set) var failedCount = 0
    @Published var showingPhotoPicker = false
    @Published var showingFilePicker = false
    @Published var error: Error?
    @Published var showingError = false

    private let importImageUseCase: ImportImageUseCase
    private let permissionService = PermissionService.shared

    var permissionStatus: PHAuthorizationStatus {
        permissionService.photoLibraryStatus
    }

    init(importImageUseCase: ImportImageUseCase) {
        self.importImageUseCase = importImageUseCase
    }

    func requestPhotoAccess() async {
        _ = await permissionService.requestPhotoLibraryAccess()
    }

    func importFromPhotos(results: [PHPickerResult]) async {
        guard !results.isEmpty else { return }

        isImporting = true
        importProgress = 0
        importedCount = 0
        failedCount = 0

        let total = results.count

        for (index, result) in results.enumerated() {
            do {
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    let image = try await loadImage(from: result.itemProvider)
                    guard let data = image.jpegData(compressionQuality: 0.9) else {
                        failedCount += 1
                        continue
                    }

                    let fileName = result.itemProvider.suggestedName ?? "image_\(UUID().uuidString).jpg"
                    _ = try await importImageUseCase.execute(imageData: data, originalFileName: fileName)
                    importedCount += 1
                }
            } catch {
                failedCount += 1
                print("Import error: \(error)")
            }

            importProgress = Double(index + 1) / Double(total)
        }

        isImporting = false
    }

    func importFromFiles(urls: [URL]) async {
        guard !urls.isEmpty else { return }

        isImporting = true
        importProgress = 0
        importedCount = 0
        failedCount = 0

        let total = urls.count

        for (index, url) in urls.enumerated() {
            do {
                _ = try await importImageUseCase.execute(from: url)
                importedCount += 1
            } catch {
                failedCount += 1
                print("Import error: \(error)")
            }

            importProgress = Double(index + 1) / Double(total)
        }

        isImporting = false
    }

    private func loadImage(from provider: NSItemProvider) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let image = object as? UIImage else {
                    continuation.resume(throwing: ImportError.invalidImage)
                    return
                }

                continuation.resume(returning: image)
            }
        }
    }
}

enum ImportError: Error {
    case invalidImage
    case accessDenied
}
