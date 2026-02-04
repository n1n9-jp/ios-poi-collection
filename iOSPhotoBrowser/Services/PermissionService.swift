//
//  PermissionService.swift
//  iOSPhotoBrowser
//

import Foundation
import Photos

final class PermissionService {
    static let shared = PermissionService()

    private init() {}

    var photoLibraryStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    var isPhotoLibraryAuthorized: Bool {
        let status = photoLibraryStatus
        return status == .authorized || status == .limited
    }

    func requestPhotoLibraryAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }
}
