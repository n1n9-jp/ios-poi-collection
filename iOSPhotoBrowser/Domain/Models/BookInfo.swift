//
//  POIInfo.swift
//  iOSPhotoBrowser
//

import Foundation

// MARK: - Visit Status

enum VisitStatus: Int16, CaseIterable, Hashable {
    case wantToVisit = 0   // 行きたい
    case visited = 1       // 訪問済み
    case favorite = 2      // お気に入り

    var displayName: String {
        switch self {
        case .wantToVisit: return "行きたい"
        case .visited: return "訪問済み"
        case .favorite: return "お気に入り"
        }
    }

    var iconName: String {
        switch self {
        case .wantToVisit: return "mappin.circle"
        case .visited: return "checkmark.circle"
        case .favorite: return "star.fill"
        }
    }
}

// MARK: - POIInfo

struct POIInfo: Identifiable, Hashable {
    let id: UUID
    var name: String?
    var address: String?
    var phoneNumber: String?
    var businessHours: String?
    var websiteUrl: String?
    var category: String?
    var priceRange: String?
    var notes: String?
    var rating: Int16
    var visitStatus: VisitStatus
    var latitude: Double?
    var longitude: Double?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String? = nil,
        address: String? = nil,
        phoneNumber: String? = nil,
        businessHours: String? = nil,
        websiteUrl: String? = nil,
        category: String? = nil,
        priceRange: String? = nil,
        notes: String? = nil,
        rating: Int16 = 0,
        visitStatus: VisitStatus = .wantToVisit,
        latitude: Double? = nil,
        longitude: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.phoneNumber = phoneNumber
        self.businessHours = businessHours
        self.websiteUrl = websiteUrl
        self.category = category
        self.priceRange = priceRange
        self.notes = notes
        self.rating = rating
        self.visitStatus = visitStatus
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
