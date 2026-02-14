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
                    // POI Info Section
                    poiInfoSection(photo: photo)

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
        .sheet(isPresented: $viewModel.showingPOIInfoEditor) {
            poiInfoEditorSheet
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

    private func poiInfoSection(photo: PhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("スポット情報")
                    .font(.headline)

                Spacer()

                if viewModel.isProcessingOCR {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if photo.hasPOIInfo {
                    Menu {
                        Button {
                            viewModel.startEditingPOIInfo()
                        } label: {
                            Label("編集", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deletePOIInfo()
                            }
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                } else {
                    Menu {
                        Button {
                            Task {
                                await viewModel.performOCRAndExtractPOIInfo()
                            }
                        } label: {
                            Label("画像から抽出", systemImage: "doc.text.viewfinder")
                        }
                        if photo.extractedText != nil && !photo.extractedText!.isEmpty {
                            Button {
                                Task {
                                    await viewModel.generatePOIInfoFromExtractedText()
                                }
                            } label: {
                                Label("テキストから生成", systemImage: "sparkles")
                            }
                            Button {
                                viewModel.startCreatingPOIInfo()
                            } label: {
                                Label("手動で作成", systemImage: "square.and.pencil")
                            }
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
            } else if let poiInfo = photo.poiInfo {
                VStack(alignment: .leading, spacing: 8) {
                    // Visit status badge
                    HStack(spacing: 12) {
                        statusBadge(
                            icon: poiInfo.visitStatus.iconName,
                            text: poiInfo.visitStatus.displayName,
                            color: visitStatusColor(poiInfo.visitStatus)
                        )
                    }

                    Divider()

                    if let name = poiInfo.name {
                        poiInfoRow("施設名", value: name)
                    }
                    if let address = poiInfo.address {
                        poiInfoRow("住所", value: address)
                    }
                    if let phoneNumber = poiInfo.phoneNumber {
                        poiInfoRow("電話", value: phoneNumber)
                    }
                    if let businessHours = poiInfo.businessHours {
                        poiInfoRow("営業時間", value: businessHours)
                    }
                    if let category = poiInfo.category {
                        poiInfoRow("カテゴリ", value: category)
                    }
                    if let priceRange = poiInfo.priceRange {
                        poiInfoRow("価格帯", value: priceRange)
                    }
                }
            } else if let message = viewModel.ocrMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("スポット情報がありません")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let extractedText = photo.extractedText, !extractedText.isEmpty, !photo.hasPOIInfo {
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

    private func visitStatusColor(_ status: VisitStatus) -> Color {
        switch status {
        case .wantToVisit: return .orange
        case .visited: return .blue
        case .favorite: return .yellow
        }
    }

    private func poiInfoRow(_ label: String, value: String) -> some View {
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

    private var poiInfoEditorSheet: some View {
        NavigationStack {
            Form {
                if let binding = Binding($viewModel.editingPOIInfo) {
                    Section("訪問ステータス") {
                        Picker("訪問状況", selection: binding.visitStatus) {
                            ForEach(VisitStatus.allCases, id: \.self) { status in
                                Label(status.displayName, systemImage: status.iconName)
                                    .tag(status)
                            }
                        }
                    }

                    Section("スポット情報") {
                        TextField("施設名", text: Binding(
                            get: { binding.wrappedValue.name ?? "" },
                            set: { binding.wrappedValue.name = $0.isEmpty ? nil : $0 }
                        ))
                        TextField("住所", text: Binding(
                            get: { binding.wrappedValue.address ?? "" },
                            set: { binding.wrappedValue.address = $0.isEmpty ? nil : $0 }
                        ))
                        TextField("電話番号", text: Binding(
                            get: { binding.wrappedValue.phoneNumber ?? "" },
                            set: { binding.wrappedValue.phoneNumber = $0.isEmpty ? nil : $0 }
                        ))
                        TextField("営業時間", text: Binding(
                            get: { binding.wrappedValue.businessHours ?? "" },
                            set: { binding.wrappedValue.businessHours = $0.isEmpty ? nil : $0 }
                        ))
                        TextField("カテゴリ", text: Binding(
                            get: { binding.wrappedValue.category ?? "" },
                            set: { binding.wrappedValue.category = $0.isEmpty ? nil : $0 }
                        ))
                        TextField("価格帯", text: Binding(
                            get: { binding.wrappedValue.priceRange ?? "" },
                            set: { binding.wrappedValue.priceRange = $0.isEmpty ? nil : $0 }
                        ))
                        TextField("メモ", text: Binding(
                            get: { binding.wrappedValue.notes ?? "" },
                            set: { binding.wrappedValue.notes = $0.isEmpty ? nil : $0 }
                        ))
                    }

                    // 新規作成時に抽出テキストを参照表示
                    if viewModel.isCreatingNewPOI,
                       let extractedText = viewModel.photo?.extractedText, !extractedText.isEmpty {
                        Section("参考: 抽出テキスト") {
                            Text(extractedText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle(viewModel.isCreatingNewPOI ? "スポット情報を作成" : "スポット情報を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        viewModel.showingPOIInfoEditor = false
                        viewModel.editingPOIInfo = nil
                        viewModel.isCreatingNewPOI = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            await viewModel.savePOIInfo()
                        }
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
