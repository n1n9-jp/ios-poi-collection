//
//  AlbumsListView.swift
//  iOSPhotoBrowser
//

import SwiftUI

struct AlbumsListView: View {
    @StateObject private var viewModel: AlbumsViewModel

    init() {
        _viewModel = StateObject(wrappedValue: DependencyContainer.shared.makeAlbumsViewModel())
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("読み込み中...")
                } else if viewModel.albums.isEmpty {
                    EmptyStateView(
                        icon: "rectangle.stack",
                        title: "アルバムがありません",
                        message: "新しいアルバムを作成して写真を整理しましょう",
                        action: { viewModel.showingCreateSheet = true },
                        actionTitle: "アルバムを作成"
                    )
                } else {
                    albumsList
                }
            }
            .navigationTitle("アルバム")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showingCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task {
                await viewModel.loadAlbums()
            }
            .refreshable {
                await viewModel.loadAlbums()
            }
            .sheet(isPresented: $viewModel.showingCreateSheet) {
                createAlbumSheet
            }
            .alert("エラー", isPresented: $viewModel.showingError) {
                Button("OK") {}
            } message: {
                Text(viewModel.error?.localizedDescription ?? "不明なエラー")
            }
        }
    }

    private var albumsList: some View {
        List {
            ForEach(viewModel.albums) { album in
                NavigationLink(value: album) {
                    AlbumRow(
                        album: album,
                        imageCount: viewModel.albumImageCounts[album.id] ?? 0
                    )
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let album = viewModel.albums[index]
                    Task {
                        await viewModel.deleteAlbum(album)
                    }
                }
            }
        }
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
        }
    }

    private var createAlbumSheet: some View {
        NavigationStack {
            Form {
                Section("アルバム名") {
                    TextField("名前を入力", text: $viewModel.newAlbumName)
                }
            }
            .navigationTitle("新規アルバム")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        viewModel.showingCreateSheet = false
                        viewModel.newAlbumName = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("作成") {
                        Task {
                            await viewModel.createAlbum()
                        }
                    }
                    .disabled(viewModel.newAlbumName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct AlbumRow: View {
    let album: Album
    let imageCount: Int

    var body: some View {
        HStack(spacing: 12) {
            // Cover image placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 60, height: 60)
                .overlay {
                    Image(systemName: "photo.on.rectangle")
                        .foregroundColor(.gray)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.headline)

                Text("\(imageCount)枚")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
