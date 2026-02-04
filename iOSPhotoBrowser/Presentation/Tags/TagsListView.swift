//
//  TagsListView.swift
//  iOSPhotoBrowser
//

import SwiftUI

struct TagsListView: View {
    @StateObject private var viewModel: TagsViewModel

    init() {
        _viewModel = StateObject(wrappedValue: DependencyContainer.shared.makeTagsViewModel())
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("読み込み中...")
                } else if viewModel.tags.isEmpty {
                    EmptyStateView(
                        icon: "tag",
                        title: "タグがありません",
                        message: "写真の詳細画面からタグを追加できます"
                    )
                } else {
                    tagsList
                }
            }
            .navigationTitle("タグ")
            .task {
                await viewModel.loadTags()
            }
            .refreshable {
                await viewModel.loadTags()
            }
            .alert("エラー", isPresented: $viewModel.showingError) {
                Button("OK") {}
            } message: {
                Text(viewModel.error?.localizedDescription ?? "不明なエラー")
            }
        }
    }

    private var tagsList: some View {
        List {
            ForEach(viewModel.tags) { tag in
                NavigationLink(value: tag) {
                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundColor(.blue)
                        Text(tag.name)
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let tag = viewModel.tags[index]
                    Task {
                        await viewModel.deleteTag(tag)
                    }
                }
            }
        }
        .navigationDestination(for: Tag.self) { tag in
            TagImagesView(tag: tag)
        }
    }
}

struct TagImagesView: View {
    let tag: Tag
    @State private var photos: [PhotoItem] = []
    @State private var isLoading = false

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        Group {
            if isLoading {
                ProgressView("読み込み中...")
            } else if photos.isEmpty {
                EmptyStateView(
                    icon: "photo.on.rectangle",
                    title: "写真がありません",
                    message: "このタグが付いた写真はありません"
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(photos) { photo in
                            NavigationLink(value: photo) {
                                PhotoGridItem(photo: photo)
                            }
                        }
                    }
                    .padding(4)
                }
                .navigationDestination(for: PhotoItem.self) { photo in
                    DetailView(photoId: photo.id)
                }
            }
        }
        .navigationTitle(tag.name)
        .task {
            await loadPhotos()
        }
    }

    private func loadPhotos() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let repository = DependencyContainer.shared.imageRepository
            photos = try await repository.search(byTag: tag.name)
        } catch {
            print("Error loading photos: \(error)")
        }
    }
}
