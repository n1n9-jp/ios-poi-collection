//
//  LLMSettingsView.swift
//  iOSPhotoBrowser
//

import SwiftUI
import UniformTypeIdentifiers

struct LLMSettingsView: View {
    @StateObject private var modelManager = LLMModelManager.shared
    @StateObject private var vlmModelManager = VLMModelManager.shared
    @State private var enginePreference: LLMEnginePreference = .auto
    @State private var showingDeleteConfirmation = false
    @State private var showingDownloadConfirmation = false
    @State private var showingVLMDeleteConfirmation = false
    @State private var showingVLMImportPicker = false
    @State private var downloadError: String?
    @State private var showingError = false
    @State private var importSuccessMessage: String?
    @State private var showingImportSuccess = false

    var body: some View {
        List {
            // MARK: - エンジン選択
            Section {
                Picker("LLMエンジン", selection: $enginePreference) {
                    ForEach(LLMEnginePreference.allCases, id: \.self) { preference in
                        VStack(alignment: .leading) {
                            Text(preference.displayName)
                        }
                        .tag(preference)
                    }
                }
                .onChange(of: enginePreference) { _, newValue in
                    modelManager.enginePreference = newValue
                }
            } header: {
                Text("AI処理設定")
            } footer: {
                Text(enginePreference.description)
            }

            // MARK: - Apple Intelligence
            Section {
                HStack {
                    Label("Apple Intelligence", systemImage: "apple.intelligence")
                    Spacer()
                    if #available(iOS 26.0, *) {
                        Text("利用可能")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("iOS 26以降")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Apple Intelligence")
            } footer: {
                Text("iOS 26以降のデバイスで、システムに組み込まれたAIを使用します。追加のダウンロードは不要です。")
            }

            // MARK: - ローカルモデル
            Section {
                HStack {
                    Label(LlamaService.ModelInfo.name, systemImage: "cpu")
                    Spacer()
                    if modelManager.isModelDownloaded {
                        Text("ダウンロード済み")
                            .foregroundStyle(.green)
                    } else {
                        Text("未ダウンロード")
                            .foregroundStyle(.secondary)
                    }
                }

                if modelManager.isModelDownloaded {
                    HStack {
                        Text("モデルサイズ")
                        Spacer()
                        Text(modelManager.displayDownloadedModelSize ?? "-")
                            .foregroundStyle(.secondary)
                    }

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("モデルを削除", systemImage: "trash")
                    }
                } else if modelManager.isDownloading {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("ダウンロード中...")
                            Spacer()
                            Text("\(Int(modelManager.downloadProgress * 100))%")
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: modelManager.downloadProgress)

                        Button(role: .destructive) {
                            modelManager.cancelDownload()
                        } label: {
                            Text("キャンセル")
                        }
                    }
                } else {
                    Button {
                        showingDownloadConfirmation = true
                    } label: {
                        Label("モデルをダウンロード", systemImage: "arrow.down.circle")
                    }

                    HStack {
                        Text("必要容量")
                        Spacer()
                        Text(LlamaService.ModelInfo.displayFileSize)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("ローカルモデル（テキスト処理）")
            } footer: {
                Text("OCRで抽出したテキストから書籍情報を解析するローカルAIモデルです。")
            }

            // MARK: - VLM（Vision Language Model）
            Section {
                HStack {
                    Label(VLMModelManager.ModelInfo.name, systemImage: "eye")
                    Spacer()
                    if vlmModelManager.isModelDownloaded {
                        Text("ダウンロード済み")
                            .foregroundStyle(.green)
                    } else {
                        Text("未ダウンロード")
                            .foregroundStyle(.secondary)
                    }
                }

                if vlmModelManager.isModelDownloaded {
                    HStack {
                        Text("必要容量")
                        Spacer()
                        Text(VLMModelManager.ModelInfo.displayFileSize)
                            .foregroundStyle(.secondary)
                    }

                    Button(role: .destructive) {
                        showingVLMDeleteConfirmation = true
                    } label: {
                        Label("VLMモデルを削除", systemImage: "trash")
                    }
                } else if vlmModelManager.isDownloading {
                    // ダウンロード中の表示（2段階表示）
                    VStack(alignment: .leading, spacing: 12) {
                        // ステップ1: ビジョンモデル
                        HStack(spacing: 8) {
                            if vlmModelManager.hasVisionProjector {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else if vlmModelManager.currentDownloadFile.contains("mmproj") {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                            }
                            Text("ビジョンモデル (~960MB)")
                                .font(.subheadline)
                            Spacer()
                            if vlmModelManager.hasVisionProjector {
                                Text("完了")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else if vlmModelManager.currentDownloadFile.contains("mmproj") {
                                Text("\(Int(vlmModelManager.downloadProgress / 0.3 * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // ステップ2: 言語モデル
                        HStack(spacing: 8) {
                            if vlmModelManager.hasLanguageModel {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else if vlmModelManager.currentDownloadFile.contains("ggml") {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                            }
                            Text("言語モデル (~2GB)")
                                .font(.subheadline)
                            Spacer()
                            if vlmModelManager.hasLanguageModel {
                                Text("完了")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else if vlmModelManager.currentDownloadFile.contains("ggml") {
                                let langProgress = (vlmModelManager.downloadProgress - 0.3) / 0.7
                                Text("\(Int(max(0, langProgress) * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // 全体進捗バー
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: vlmModelManager.downloadProgress)
                            Text("全体: \(Int(vlmModelManager.downloadProgress * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Button(role: .destructive) {
                            vlmModelManager.cancelDownload()
                        } label: {
                            Text("キャンセル")
                        }
                    }
                } else {
                    // インポート状態の表示
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: vlmModelManager.hasLanguageModel ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(vlmModelManager.hasLanguageModel ? .green : .secondary)
                            Text("言語モデル (~2GB)")
                                .font(.caption)
                            if vlmModelManager.hasLanguageModel {
                                Text("済")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                        }
                        HStack {
                            Image(systemName: vlmModelManager.hasVisionProjector ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(vlmModelManager.hasVisionProjector ? .green : .secondary)
                            Text("ビジョン (~960MB)")
                                .font(.caption)
                            if vlmModelManager.hasVisionProjector {
                                Text("済")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    // ダウンロードボタン
                    Button {
                        startVLMDownload()
                    } label: {
                        Label("モデルをダウンロード", systemImage: "arrow.down.circle")
                    }

                    // ファイルからインポート（代替手段）
                    Button {
                        showingVLMImportPicker = true
                    } label: {
                        Label("ファイルからインポート", systemImage: "doc.badge.plus")
                    }
                    .foregroundStyle(.secondary)

                    HStack {
                        Text("必要容量")
                        Spacer()
                        Text(VLMModelManager.ModelInfo.displayFileSize)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Vision Language Model（画像認識）")
            } footer: {
                Text("画像から直接書籍情報を認識できるAIモデルです。OCRを経由せず、より高精度な抽出が可能です。")
            }

            // MARK: - 情報
            Section {
                NavigationLink {
                    LLMInfoView()
                } label: {
                    Label("LLMについて", systemImage: "info.circle")
                }
            }
        }
        .navigationTitle("AI処理")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            enginePreference = modelManager.enginePreference
        }
        .confirmationDialog(
            "モデルを削除しますか？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                deleteModel()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("モデルを削除すると、再度使用するにはダウンロードが必要です。")
        }
        .confirmationDialog(
            "モデルをダウンロードしますか？",
            isPresented: $showingDownloadConfirmation,
            titleVisibility: .visible
        ) {
            Button("ダウンロード") {
                startDownload()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("約\(LlamaService.ModelInfo.displayFileSize)のダウンロードが必要です。Wi-Fi環境での実行を推奨します。")
        }
        .alert("エラー", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(downloadError ?? "不明なエラーが発生しました")
        }
        .confirmationDialog(
            "VLMモデルを削除しますか？",
            isPresented: $showingVLMDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                deleteVLMModel()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("VLMモデルを削除すると、再度使用するには手動でダウンロードが必要です。")
        }
        .fileImporter(
            isPresented: $showingVLMImportPicker,
            allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            handleVLMImport(result)
        }
        .alert("インポート完了", isPresented: $showingImportSuccess) {
            Button("OK") {}
        } message: {
            Text(importSuccessMessage ?? "")
        }
    }

    private func deleteVLMModel() {
        do {
            try vlmModelManager.deleteModel()
        } catch {
            downloadError = error.localizedDescription
            showingError = true
        }
    }

    private func startDownload() {
        Task {
            do {
                try await modelManager.startDownload()
            } catch {
                downloadError = error.localizedDescription
                showingError = true
            }
        }
    }

    private func deleteModel() {
        do {
            try modelManager.deleteModel()
        } catch {
            downloadError = error.localizedDescription
            showingError = true
        }
    }

    private func handleVLMImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            var lastResult: VLMModelManager.ImportResult?
            for url in urls {
                // セキュリティスコープへのアクセスを開始
                guard url.startAccessingSecurityScopedResource() else {
                    downloadError = "ファイルへのアクセス権限がありません"
                    showingError = true
                    continue
                }
                defer { url.stopAccessingSecurityScopedResource() }

                do {
                    lastResult = try vlmModelManager.importModel(from: url)
                } catch {
                    downloadError = error.localizedDescription
                    showingError = true
                }
            }
            if let result = lastResult {
                importSuccessMessage = result.message
                showingImportSuccess = true
            }
        case .failure(let error):
            downloadError = error.localizedDescription
            showingError = true
        }
    }

    private func startVLMDownload() {
        Task {
            do {
                try await vlmModelManager.startDownload()
                importSuccessMessage = "VLMモデルのダウンロードが完了しました"
                showingImportSuccess = true
            } catch {
                if !(error is CancellationError) {
                    downloadError = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}

// MARK: - LLM Info View

struct LLMInfoView: View {
    var body: some View {
        List {
            Section("概要") {
                Text("このアプリでは、本の表紙や奥付からOCRで読み取ったテキストを、AIを使って解析し、タイトル・著者名・ISBNなどの書籍情報を自動抽出します。")
                    .font(.body)
            }

            Section("Apple Intelligence") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("iOS 26以降で利用可能なAppleのオンデバイスAIです。")
                    Text("• 追加のダウンロード不要")
                    Text("• システムに最適化された高速処理")
                    Text("• プライバシー保護（データは端末外に送信されません）")
                }
                .font(.body)
            }

            Section("ローカルモデル (Gemma 2B)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Googleが開発した軽量で高性能な言語モデルです。OCRで抽出したテキストを解析します。")
                    Text("• iOS 17以降で動作")
                    Text("• オフラインで動作")
                    Text("• 約\(LlamaService.ModelInfo.displayFileSize)のダウンロードが必要")
                    Text("• 日本語・英語に対応")
                }
                .font(.body)
            }

            Section("Vision Language Model (MiniCPM-V 4.0)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("画像を直接認識できるマルチモーダルAIモデルです。")
                    Text("• 画像から直接テキスト認識")
                    Text("• 本の表紙デザインも理解")
                    Text("• OCRを経由せず、より高精度な抽出が可能")
                    Text("• オフラインで動作")
                    Text("• 約\(VLMModelManager.ModelInfo.displayFileSize)のダウンロードが必要")
                }
                .font(.body)
            }

            Section("プライバシー") {
                Text("すべてのAI処理は端末内で完結します。画像やテキストがインターネットに送信されることはありません。")
                    .font(.body)
            }
        }
        .navigationTitle("LLMについて")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        LLMSettingsView()
    }
}
