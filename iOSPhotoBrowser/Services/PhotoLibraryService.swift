//
//  PhotoLibraryService.swift
//  iOSPhotoBrowser
//

import Foundation
import Photos
import UIKit

final class PhotoLibraryService {
    static let shared = PhotoLibraryService()

    private init() {}

    func fetchImageData(from asset: PHAsset) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data = data else {
                    continuation.resume(throwing: PhotoLibraryError.dataNotAvailable)
                    return
                }

                continuation.resume(returning: data)
            }
        }
    }

    func fetchImage(from asset: PHAsset, targetSize: CGSize = PHImageManagerMaximumSize) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { image, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let image = image else {
                    continuation.resume(throwing: PhotoLibraryError.imageNotAvailable)
                    return
                }

                continuation.resume(returning: image)
            }
        }
    }

    func getOriginalFileName(from asset: PHAsset) -> String? {
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.first?.originalFilename
    }
}

enum PhotoLibraryError: Error {
    case dataNotAvailable
    case imageNotAvailable
    case accessDenied
}
