//
//  SortOption.swift
//  iOSPhotoBrowser
//

import Foundation

enum SortOption: String, CaseIterable, Identifiable {
    case capturedAtDescending = "撮影日（新しい順）"
    case capturedAtAscending = "撮影日（古い順）"
    case importedAtDescending = "取り込み日（新しい順）"
    case importedAtAscending = "取り込み日（古い順）"

    var id: String { rawValue }

    var sortDescriptor: NSSortDescriptor {
        switch self {
        case .capturedAtDescending:
            return NSSortDescriptor(key: "capturedAt", ascending: false)
        case .capturedAtAscending:
            return NSSortDescriptor(key: "capturedAt", ascending: true)
        case .importedAtDescending:
            return NSSortDescriptor(key: "importedAt", ascending: false)
        case .importedAtAscending:
            return NSSortDescriptor(key: "importedAt", ascending: true)
        }
    }
}
