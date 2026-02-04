//
//  PhotoGridItem.swift
//  iOSPhotoBrowser
//

import SwiftUI

struct PhotoGridItem: View {
    let photo: PhotoItem
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .cornerRadius(8)
        .task {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        // Check cache first
        if let cached = ThumbnailCache.shared.get(for: photo.id) {
            thumbnail = cached
            return
        }

        // Load from disk
        if let thumbnailPath = photo.thumbnailPath,
           let image = FileStorageManager.shared.loadThumbnail(fileName: thumbnailPath) {
            thumbnail = image
            ThumbnailCache.shared.set(image, for: photo.id)
        }
    }
}
