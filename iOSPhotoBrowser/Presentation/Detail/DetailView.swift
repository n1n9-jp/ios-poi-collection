//
//  DetailView.swift
//  iOSPhotoBrowser
//

import SwiftUI

struct DetailView: View {
    @StateObject private var viewModel: DetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    init(photoId: UUID) {
        _viewModel = StateObject(wrappedValue: DependencyContainer.shared.makeDetailViewModel(photoId: photoId))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Image
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .cornerRadius(12)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            ProgressView()
                        }
                        .cornerRadius(12)
                }

                if let photo = viewModel.photo {
                    // Tags Section
                    tagsSection(photo: photo)

                    // Albums Section
                    albumsSection(photo: photo)

                    // Metadata Section
                    metadataSection(photo: photo)
                }
            }
            .padding()
        }
        .navigationTitle("詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        viewModel.showingDeleteConfirmation = true
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            await viewModel.loadPhoto()
            image = viewModel.loadImage()
        }
        .alert("削除確認", isPresented: $viewModel.showingDeleteConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                Task {
                    if await viewModel.deletePhoto() {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("この画像を削除しますか？この操作は取り消せません。")
        }
        .sheet(isPresented: $viewModel.showingTagEditor) {
            tagEditorSheet
        }
        .sheet(isPresented: $viewModel.showingAlbumSelector) {
            albumSelectorSheet
        }
        .alert("エラー", isPresented: $viewModel.showingError) {
            Button("OK") {}
        } message: {
            Text(viewModel.error?.localizedDescription ?? "不明なエラー")
        }
    }

    private func albumsSection(photo: PhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("アルバム")
                    .font(.headline)

                Spacer()

                Button {
                    Task {
                        await viewModel.loadAlbums()
                    }
                    viewModel.showingAlbumSelector = true
                } label: {
                    Image(systemName: "plus.circle")
                }
            }

            if photo.albums.isEmpty {
                Text("アルバムに登録されていません")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(photo.albums) { album in
                        HStack {
                            Image(systemName: "rectangle.stack.fill")
                                .foregroundColor(.blue)
                            Text(album.name)
                            Spacer()
                            Button {
                                Task {
                                    await viewModel.removeFromAlbum(album)
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }

    private func tagsSection(photo: PhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("タグ")
                    .font(.headline)

                Spacer()

                Button {
                    viewModel.showingTagEditor = true
                } label: {
                    Image(systemName: "plus.circle")
                }
            }

            if photo.tags.isEmpty {
                Text("タグがありません")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(photo.tags) { tag in
                        TagChip(tag: tag) {
                            Task {
                                await viewModel.removeTag(tag)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }

    private func metadataSection(photo: PhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("情報")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                metadataRow("ファイル名", value: photo.fileName)
                metadataRow("サイズ", value: photo.sizeDescription)
                metadataRow("ファイルサイズ", value: photo.fileSizeDescription)

                if let capturedAt = photo.capturedAt {
                    metadataRow("撮影日時", value: formatDate(capturedAt))
                }

                metadataRow("取り込み日時", value: formatDate(photo.importedAt))

                if let make = photo.cameraMake {
                    metadataRow("カメラメーカー", value: make)
                }

                if let model = photo.cameraModel {
                    metadataRow("カメラ機種", value: model)
                }

                if photo.hasLocation {
                    metadataRow("位置情報", value: "あり")
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }

    private var tagEditorSheet: some View {
        NavigationStack {
            Form {
                Section("新しいタグ") {
                    TextField("タグ名", text: $viewModel.newTagName)
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("タグを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        viewModel.showingTagEditor = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        Task {
                            await viewModel.addTag()
                            viewModel.showingTagEditor = false
                        }
                    }
                    .disabled(viewModel.newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var albumSelectorSheet: some View {
        NavigationStack {
            List {
                if viewModel.allAlbums.isEmpty {
                    Text("アルバムがありません")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.allAlbums) { album in
                        Button {
                            Task {
                                if viewModel.isInAlbum(album) {
                                    await viewModel.removeFromAlbum(album)
                                } else {
                                    await viewModel.addToAlbum(album)
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.stack")
                                Text(album.name)
                                Spacer()
                                if viewModel.isInAlbum(album) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .foregroundColor(.primary)
                        }
                    }
                }
            }
            .navigationTitle("アルバムに追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        viewModel.showingAlbumSelector = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// Simple FlowLayout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)

        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}
