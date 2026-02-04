//
//  FileImportService.swift
//  iOSPhotoBrowser
//

import Foundation
import UIKit
import UniformTypeIdentifiers

final class FileImportService {
    static let shared = FileImportService()

    private init() {}

    func loadImageData(from url: URL) throws -> Data {
        // Start accessing the security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            throw FileImportError.accessDenied
        }

        defer {
            url.stopAccessingSecurityScopedResource()
        }

        return try Data(contentsOf: url)
    }

    func loadImage(from url: URL) throws -> UIImage {
        let data = try loadImageData(from: url)

        guard let image = UIImage(data: data) else {
            throw FileImportError.invalidImageData
        }

        return image
    }

    func getFileName(from url: URL) -> String {
        url.lastPathComponent
    }

    static var supportedTypes: [UTType] {
        [.image, .jpeg, .png, .heic, .gif, .webP, .tiff, .bmp]
    }
}

enum FileImportError: Error {
    case accessDenied
    case invalidImageData
    case fileNotFound
}
