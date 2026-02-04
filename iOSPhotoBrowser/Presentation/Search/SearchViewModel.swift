//
//  SearchViewModel.swift
//  iOSPhotoBrowser
//

import Foundation
import Combine

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var searchText = ""
    @Published private(set) var searchResults: [PhotoItem] = []
    @Published private(set) var isSearching = false
    @Published var error: Error?
    @Published var showingError = false

    private let imageRepository: ImageRepositoryProtocol

    init(imageRepository: ImageRepositoryProtocol) {
        self.imageRepository = imageRepository
    }

    func search() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            searchResults = try await imageRepository.search(byTag: query)
        } catch {
            self.error = error
            showingError = true
        }
    }

    func clearSearch() {
        searchText = ""
        searchResults = []
    }
}
