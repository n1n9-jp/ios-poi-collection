//
//  ImageMetadata.swift
//  iOSPhotoBrowser
//

import Foundation

struct ImageMetadata {
    let width: Int
    let height: Int
    let orientation: Int
    let capturedAt: Date?
    let latitude: Double?
    let longitude: Double?
    let cameraMake: String?
    let cameraModel: String?
    let fileSize: Int64

    init(
        width: Int = 0,
        height: Int = 0,
        orientation: Int = 1,
        capturedAt: Date? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        fileSize: Int64 = 0
    ) {
        self.width = width
        self.height = height
        self.orientation = orientation
        self.capturedAt = capturedAt
        self.latitude = latitude
        self.longitude = longitude
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.fileSize = fileSize
    }
}
