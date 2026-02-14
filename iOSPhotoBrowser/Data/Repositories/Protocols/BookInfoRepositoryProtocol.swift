//
//  POIInfoRepositoryProtocol.swift
//  iOSPhotoBrowser
//

import Foundation

protocol POIInfoRepositoryProtocol {
    func save(_ poiInfo: POIInfo, for imageId: UUID) async throws
    func fetch(for imageId: UUID) async throws -> POIInfo?
    func update(_ poiInfo: POIInfo) async throws
    func delete(for imageId: UUID) async throws
}
