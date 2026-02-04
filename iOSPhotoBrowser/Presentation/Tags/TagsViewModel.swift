//
//  TagsViewModel.swift
//  iOSPhotoBrowser
//

import Foundation
import Combine

@MainActor
final class TagsViewModel: ObservableObject {
    @Published private(set) var tags: [Tag] = []
    @Published private(set) var isLoading = false
    @Published var error: Error?
    @Published var showingError = false

    private let tagRepository: TagRepositoryProtocol

    init(tagRepository: TagRepositoryProtocol) {
        self.tagRepository = tagRepository
    }

    func loadTags() async {
        isLoading = true
        defer { isLoading = false }

        do {
            tags = try await tagRepository.fetchAll()
        } catch {
            self.error = error
            showingError = true
        }
    }

    func deleteTag(_ tag: Tag) async {
        do {
            try await tagRepository.delete(tag)
            tags.removeAll { $0.id == tag.id }
        } catch {
            self.error = error
            showingError = true
        }
    }
}
