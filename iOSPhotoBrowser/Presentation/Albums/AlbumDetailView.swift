//
//  AlbumDetailView.swift
//  iOSPhotoBrowser
//

import SwiftUI

struct AlbumDetailView: View {
    @StateObject private var viewModel: AlbumDetailViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    init(album: Album) {
        _viewModel = StateObject(wrappedValue: DependencyContainer.shared.makeAlbumDetailViewModel(album: album))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("読み込み中...")
            } else if viewModel.photos.isEmpty {
                EmptyStateView(
                    icon: "photo.on.rectangle",
                    title: "写真がありません",
                    message: "このアルバムにはまだ写真がありません"
                )
            } else {
                photoGrid
            }
        }
        .navigationTitle(viewModel.album.name)
        .task {
            await viewModel.loadPhotos()
        }
        .refreshable {
            await viewModel.loadPhotos()
        }
        .alert("エラー", isPresented: $viewModel.showingError) {
            Button("OK") {}
        } message: {
            Text(viewModel.error?.localizedDescription ?? "不明なエラー")
        }
    }

    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(viewModel.photos) { photo in
                    NavigationLink(value: photo) {
                        PhotoGridItem(photo: photo)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            Task {
                                await viewModel.removeImage(photo)
                            }
                        } label: {
                            Label("アルバムから削除", systemImage: "minus.circle")
                        }
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
