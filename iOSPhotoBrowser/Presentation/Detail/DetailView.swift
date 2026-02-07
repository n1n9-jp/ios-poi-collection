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
                    // Book Info Section
                    bookInfoSection(photo: photo)

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
        .sheet(isPresented: $viewModel.showingBookInfoEditor) {
            bookInfoEditorSheet
        }
        .sheet(isPresented: $viewModel.showingTitleSearchSheet) {
            titleSearchSheet
        }
        .sheet(isPresented: $viewModel.showingSearchResults) {
            searchResultsSheet
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

    private func bookInfoSection(photo: PhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("書誌情報")
                    .font(.headline)

                Spacer()

                if viewModel.isProcessingOCR {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if photo.hasBookInfo {
                    Menu {
                        Button {
                            viewModel.startEditingBookInfo()
                        } label: {
                            Label("編集", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteBookInfo()
                            }
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                } else {
                    Button {
                        Task {
                            await viewModel.performOCRAndFetchBookInfo()
                        }
                    } label: {
                        Text("抽出")
                            .font(.subheadline)
                    }
                }
            }

            if viewModel.isProcessingOCR {
                HStack {
                    Spacer()
                    Text("処理中...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if let bookInfo = photo.bookInfo {
                VStack(alignment: .leading, spacing: 8) {
                    // User status badges
                    HStack(spacing: 12) {
                        statusBadge(
                            icon: bookInfo.readingStatus.iconName,
                            text: bookInfo.readingStatus.displayName,
                            color: readingStatusColor(bookInfo.readingStatus)
                        )
                        statusBadge(
                            icon: bookInfo.ownershipStatus.iconName,
                            text: bookInfo.ownershipStatus.displayName,
                            color: bookInfo.ownershipStatus == .owned ? .green : .gray
                        )
                    }

                    Divider()

                    if let title = bookInfo.title {
                        bookInfoRow("タイトル", value: title)
                    }
                    if let author = bookInfo.author {
                        bookInfoRow("著者", value: author)
                    }
                    if let publisher = bookInfo.publisher {
                        bookInfoRow("出版社", value: publisher)
                    }
                    bookInfoRow("ISBN", value: bookInfo.isbn)
                    if let publishedDate = bookInfo.publishedDate, !publishedDate.isEmpty {
                        bookInfoRow("出版日", value: publishedDate)
                    }
                    if let category = bookInfo.category {
                        bookInfoRow("カテゴリ", value: category)
                    }
                }
            } else if let message = viewModel.ocrMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button {
                        viewModel.startTitleSearch()
                    } label: {
                        Label("タイトルで検索", systemImage: "magnifyingglass")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("書誌情報がありません")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let extractedText = photo.extractedText, !extractedText.isEmpty, !photo.hasBookInfo {
                DisclosureGroup("抽出テキスト") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(extractedText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            UIPasteboard.general.string = extractedText
                        } label: {
                            Label("テキストをコピー", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .font(.subheadline)

                if viewModel.ocrMessage == nil {
                    Button {
                        viewModel.startTitleSearch()
                    } label: {
                        Label("タイトルで検索", systemImage: "magnifyingglass")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }

    private func statusBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(text)
                .font(.system(size: 12))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }

    private func readingStatusColor(_ status: ReadingStatus) -> Color {
        switch status {
        case .unread: return .gray
        case .reading: return .blue
        case .finished: return .green
        }
    }

    private func bookInfoRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
        }
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

    private var bookInfoEditorSheet: some View {
        NavigationStack {
            Form {
                if let binding = Binding($viewModel.editingBookInfo) {
                    Section("ユーザー情報") {
                        Picker("読書状況", selection: binding.readingStatus) {
                            ForEach(ReadingStatus.allCases, id: \.self) { status in
                                Label(status.displayName, systemImage: status.iconName)
                                    .tag(status)
                            }
                        }

                        Picker("所有状況", selection: binding.ownershipStatus) {
                            ForEach(OwnershipStatus.allCases, id: \.self) { status in
                                Label(status.displayName, systemImage: status.iconName)
                                    .tag(status)
                            }
                        }
                    }

                    Section("書誌情報") {
                        TextField("タイトル", text: Binding(
                            get: { binding.wrappedValue.title ?? "" },
                            set: { binding.wrappedValue.title = $0.isEmpty ? nil : $0 }
                        ))
                        TextField("著者", text: Binding(
                            get: { binding.wrappedValue.author ?? "" },
                            set: { binding.wrappedValue.author = $0.isEmpty ? nil : $0 }
                        ))
                        TextField("出版社", text: Binding(
                            get: { binding.wrappedValue.publisher ?? "" },
                            set: { binding.wrappedValue.publisher = $0.isEmpty ? nil : $0 }
                        ))
                        TextField("出版日", text: Binding(
                            get: { binding.wrappedValue.publishedDate ?? "" },
                            set: { binding.wrappedValue.publishedDate = $0.isEmpty ? nil : $0 }
                        ))
                    }

                    Section {
                        Text("ISBN: \(binding.wrappedValue.isbn)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("書誌情報を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        viewModel.showingBookInfoEditor = false
                        viewModel.editingBookInfo = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            await viewModel.updateBookInfo()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var titleSearchSheet: some View {
        NavigationStack {
            Form {
                Section("検索キーワード") {
                    TextField("タイトルや著者名を入力", text: $viewModel.searchKeyword)
                        .textInputAutocapitalization(.never)
                }

                if let extractedText = viewModel.photo?.extractedText, !extractedText.isEmpty {
                    Section {
                        // 行ごとに分割して、タップで検索キーワードに追加
                        let lines = extractedText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Button {
                                // 検索キーワードに追加（既存のキーワードがあればスペースで区切る）
                                if viewModel.searchKeyword.isEmpty {
                                    viewModel.searchKeyword = line
                                } else {
                                    viewModel.searchKeyword += " " + line
                                }
                            } label: {
                                HStack {
                                    Text(line)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("タップして追加")
                            Spacer()
                            Button {
                                UIPasteboard.general.string = extractedText
                            } label: {
                                Label("全てコピー", systemImage: "doc.on.doc")
                                    .font(.caption)
                            }
                        }
                    } footer: {
                        Text("行をタップすると検索キーワードに追加されます")
                    }
                }
            }
            .navigationTitle("タイトルで検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        viewModel.cancelTitleSearch()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSearching {
                        ProgressView()
                    } else {
                        Button("検索") {
                            Task {
                                await viewModel.searchByTitle()
                            }
                        }
                        .disabled(viewModel.searchKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var searchResultsSheet: some View {
        NavigationStack {
            List {
                if viewModel.searchResults.isEmpty {
                    Text("検索結果がありません")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.searchResults) { bookInfo in
                        Button {
                            Task {
                                await viewModel.selectBookInfo(bookInfo)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(bookInfo.title ?? "タイトル不明")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                if let author = bookInfo.author {
                                    Text(author)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                HStack {
                                    if let publisher = bookInfo.publisher {
                                        Text(publisher)
                                    }
                                    if !bookInfo.isbn.isEmpty {
                                        Text("ISBN: \(bookInfo.isbn)")
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("検索結果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        viewModel.cancelTitleSearch()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("再検索") {
                        viewModel.showingSearchResults = false
                        viewModel.showingTitleSearchSheet = true
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
