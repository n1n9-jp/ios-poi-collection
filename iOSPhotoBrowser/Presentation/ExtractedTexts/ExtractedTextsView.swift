//
//  POIListView.swift
//  iOSPhotoBrowser
//

import SwiftUI

struct POIListView: View {
    @StateObject private var viewModel = DependencyContainer.shared.makePOIListViewModel()
    @State private var selectedItem: ExtractedTextItem?
    @State private var showingFilterSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("読み込み中...")
                } else if viewModel.items.isEmpty {
                    emptyStateView
                } else {
                    tableListView
                }
            }
            .navigationTitle("スポット一覧")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.isGeneratingBatch {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("\(viewModel.batchProgress.current)/\(viewModel.batchProgress.total)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if viewModel.unlinkedItemCount > 0 {
                        Button {
                            Task {
                                await viewModel.generatePOIInfoForUnlinkedItems()
                            }
                        } label: {
                            Label("一括生成(\(viewModel.unlinkedItemCount))", systemImage: "sparkles")
                                .font(.caption)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFilterSheet = true
                    } label: {
                        Image(systemName: viewModel.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .task {
                await viewModel.loadItems()
            }
            .refreshable {
                await viewModel.loadItems()
            }
            .alert("エラー", isPresented: $viewModel.showingError) {
                Button("OK") {}
            } message: {
                Text(viewModel.error?.localizedDescription ?? "不明なエラー")
            }
            .alert("一括生成結果", isPresented: .init(
                get: { viewModel.batchResultMessage != nil },
                set: { if !$0 { viewModel.batchResultMessage = nil } }
            )) {
                Button("OK") { viewModel.batchResultMessage = nil }
            } message: {
                Text(viewModel.batchResultMessage ?? "")
            }
            .sheet(item: $selectedItem) { item in
                POIDetailSheetView(
                    item: item,
                    onStatusUpdate: { visitStatus in
                        Task {
                            await viewModel.updateStatus(
                                for: item.id,
                                visitStatus: visitStatus
                            )
                        }
                    },
                    onGenerate: {
                        Task {
                            await viewModel.generatePOIInfo(for: item.id)
                            selectedItem = nil
                        }
                    },
                    onDismiss: {
                        selectedItem = nil
                    }
                )
            }
            .sheet(isPresented: $showingFilterSheet) {
                filterSheet
            }
        }
    }

    // MARK: - Filter Sheet

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("訪問ステータス") {
                    Picker("訪問ステータス", selection: $viewModel.visitStatusFilter) {
                        ForEach(VisitStatusFilter.allCases, id: \.self) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if viewModel.hasActiveFilters {
                    Section {
                        Button("フィルターをクリア", role: .destructive) {
                            viewModel.clearFilters()
                        }
                    }
                }
            }
            .navigationTitle("フィルター")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        showingFilterSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            if viewModel.hasActiveFilters {
                Text("該当するスポット情報がありません")
                    .font(.headline)
                Text("フィルター条件を変更してみてください")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Button("フィルターをクリア") {
                    viewModel.clearFilters()
                }
                .buttonStyle(.bordered)
            } else {
                Text("スポット情報がありません")
                    .font(.headline)
                Text("詳細画面で「抽出」ボタンを押すと\nOCRでテキストを抽出し、\nスポット情報を取得できます")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    private var tableListView: some View {
        List {
            ForEach(viewModel.groupedItems) { group in
                Section {
                    ForEach(group.items) { item in
                        Button {
                            selectedItem = item
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    // POI name
                                    Text(item.poiName ?? item.displayTitle)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .lineLimit(2)

                                    // Address
                                    if let address = item.poiAddress {
                                        Text(address)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }

                                    // Category and visit status badge
                                    HStack(spacing: 8) {
                                        if let category = item.poiCategory {
                                            Text(category)
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                        statusBadge(
                                            icon: item.visitStatus.iconName,
                                            text: item.visitStatus.displayName,
                                            color: visitStatusColor(item.visitStatus)
                                        )
                                    }
                                }

                                Spacer()

                                // Chevron indicator
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text(group.category)
                        Spacer()
                        Text("\(group.items.count)件")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func statusBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 10))
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.1))
        .cornerRadius(4)
    }

    private func visitStatusColor(_ status: VisitStatus) -> Color {
        switch status {
        case .wantToVisit: return .orange
        case .visited: return .blue
        case .favorite: return .yellow
        }
    }
}

// MARK: - POI Detail Sheet View

struct POIDetailSheetView: View {
    let item: ExtractedTextItem
    let onStatusUpdate: (VisitStatus) -> Void
    let onGenerate: (() -> Void)?
    let onDismiss: () -> Void

    @State private var visitStatus: VisitStatus
    @State private var hasChanges = false

    init(
        item: ExtractedTextItem,
        onStatusUpdate: @escaping (VisitStatus) -> Void,
        onGenerate: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.item = item
        self.onStatusUpdate = onStatusUpdate
        self.onGenerate = onGenerate
        self.onDismiss = onDismiss
        _visitStatus = State(initialValue: item.visitStatus)
    }

    var body: some View {
        NavigationStack {
            List {
                // Thumbnail section
                if let path = item.thumbnailPath,
                   let image = FileStorageManager.shared.loadThumbnail(fileName: path) {
                    Section {
                        HStack {
                            Spacer()
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 200)
                                .cornerRadius(8)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                // Visit status section (editable)
                Section("訪問ステータス") {
                    Picker("訪問状況", selection: $visitStatus) {
                        ForEach(VisitStatus.allCases, id: \.self) { status in
                            Label(status.displayName, systemImage: status.iconName)
                                .tag(status)
                        }
                    }
                    .onChange(of: visitStatus) { _, _ in
                        hasChanges = true
                    }
                }

                // POI info section
                Section("スポット情報") {
                    if let name = item.poiName {
                        infoRow("施設名", value: name)
                    }
                    if let address = item.poiAddress {
                        infoRow("住所", value: address)
                    }
                    if let phone = item.poiPhone {
                        infoRow("電話", value: phone)
                    }
                    if let hours = item.poiHours {
                        infoRow("営業時間", value: hours)
                    }
                    if let category = item.poiCategory {
                        infoRow("カテゴリ", value: category)
                    }
                    if let priceRange = item.poiPriceRange {
                        infoRow("価格帯", value: priceRange)
                    }
                    if let processedAt = item.ocrProcessedAt {
                        infoRow("取得日時", value: formatDate(processedAt))
                    }
                }

                // Generate POI button (when no POI info exists but text is available)
                if !item.hasPOIInfo, let text = item.extractedText, !text.isEmpty, let onGenerate {
                    Section {
                        Button {
                            onGenerate()
                        } label: {
                            Label("テキストからスポット情報を生成", systemImage: "sparkles")
                        }
                    }
                }

                // Extracted text section
                if let text = item.extractedText, !text.isEmpty {
                    Section {
                        DisclosureGroup("抽出テキスト") {
                            Text(text)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(hasChanges ? "保存" : "閉じる") {
                        if hasChanges {
                            onStatusUpdate(visitStatus)
                        }
                        onDismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func infoRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
}
