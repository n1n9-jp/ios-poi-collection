//
//  MetadataExtractionService.swift
//  iOSPhotoBrowser
//

import Foundation
import UIKit
import ImageIO
import CoreLocation

final class MetadataExtractionService {
    static let shared = MetadataExtractionService()

    private init() {}

    func extract(from data: Data) -> ImageMetadata {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return ImageMetadata(fileSize: Int64(data.count))
        }

        // Basic properties
        let width = properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0
        let orientation = properties[kCGImagePropertyOrientation as String] as? Int ?? 1

        // EXIF data
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let capturedAt = extractDate(from: exif)

        // GPS data
        let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any]
        let (latitude, longitude) = extractGPS(from: gps)

        // TIFF data (camera info)
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let cameraMake = tiff?[kCGImagePropertyTIFFMake as String] as? String
        let cameraModel = tiff?[kCGImagePropertyTIFFModel as String] as? String

        return ImageMetadata(
            width: width,
            height: height,
            orientation: orientation,
            capturedAt: capturedAt,
            latitude: latitude,
            longitude: longitude,
            cameraMake: cameraMake,
            cameraModel: cameraModel,
            fileSize: Int64(data.count)
        )
    }

    func extract(from url: URL) -> ImageMetadata? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return extract(from: data)
    }

    private func extractDate(from exif: [String: Any]?) -> Date? {
        guard let exif = exif else { return nil }

        // Try DateTimeOriginal first, then DateTimeDigitized
        let dateString = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String
            ?? exif[kCGImagePropertyExifDateTimeDigitized as String] as? String

        guard let dateString = dateString else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: dateString)
    }

    private func extractGPS(from gps: [String: Any]?) -> (Double?, Double?) {
        guard let gps = gps else { return (nil, nil) }

        guard let latitudeValue = gps[kCGImagePropertyGPSLatitude as String] as? Double,
              let latitudeRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String,
              let longitudeValue = gps[kCGImagePropertyGPSLongitude as String] as? Double,
              let longitudeRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String else {
            return (nil, nil)
        }

        let latitude = latitudeRef == "S" ? -latitudeValue : latitudeValue
        let longitude = longitudeRef == "W" ? -longitudeValue : longitudeValue

        return (latitude, longitude)
    }
}
