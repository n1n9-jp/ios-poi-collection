//
//  SearchView.swift
//  iOSPhotoBrowser
//

import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    init() {
        _viewModel = StateObject(wrappedValue: DependencyContainer.shared.makeSearchViewModel())
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.searchText.isEmpty {
                    searchPromptView
                } else if viewModel.isSearching {
                    ProgressView("検索中...")
                } else if viewModel.searchResults.isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "結果がありません",
                        message: "「\(viewModel.searchText)」に一致する写真が見つかりませんでした"
                    )
                } else {
                    searchResultsGrid
                }
            }
            .navigationTitle("検索")
            .searchable(text: $viewModel.searchText, prompt: "タグで検索")
            .onSubmit(of: .search) {
                Task {
                    await viewModel.search()
                }
            }
            .onChange(of: viewModel.searchText) { _, newValue in
                if newValue.isEmpty {
                    viewModel.clearSearch()
                }
            }
            .alert("エラー", isPresented: $viewModel.showingError) {
                Button("OK") {}
            } message: {
                Text(viewModel.error?.localizedDescription ?? "不明なエラー")
            }
        }
    }

    private var searchPromptView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text("タグで写真を検索")
                .font(.headline)

            Text("検索バーにタグ名を入力してください")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var searchResultsGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(viewModel.searchResults.count)件の結果")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(viewModel.searchResults) { photo in
                        NavigationLink(value: photo) {
                            PhotoGridItem(photo: photo)
                        }
                    }
                }
                .padding(4)
            }
        }
        .navigationDestination(for: PhotoItem.self) { photo in
            DetailView(photoId: photo.id)
        }
    }
}
