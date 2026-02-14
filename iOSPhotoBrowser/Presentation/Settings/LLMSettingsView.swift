//
//  LLMSettingsView.swift
//  iOSPhotoBrowser
//

import SwiftUI
import UniformTypeIdentifiers

struct LLMSettingsView: View {
    @StateObject private var modelManager = LLMModelManager.shared
    @StateObject private var vlmModelManager = VLMModelManager.shared
    @StateObject private var cloudAPIManager = CloudAPIKeyManager.shared
    @State private var enginePreference: LLMEnginePreference = .auto
    @State private var showingDeleteConfirmation = false
    @State private var showingDownloadConfirmation = false
    @State private var showingVLMDeleteConfirmation = false
    @State private var showingVLMImportPicker = false
    @State private var downloadError: String?
    @State private var showingError = false
    @State private var importSuccessMessage: String?
    @State private var showingImportSuccess = false
    @State private var apiKeyInput = ""
    @State private var isTestingAPI = false
    @State private var apiTestResult: String?
    @State private var showingAPITestResult = false

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

            // MARK: - クラウドAPI
            Section {
                HStack {
                    Label("Claude API", systemImage: "cloud")
                    Spacer()
                    if cloudAPIManager.isConfigured {
                        Text("設定済み")
                            .foregroundStyle(.green)
                    } else {
                        Text("未設定")
                            .foregroundStyle(.secondary)
                    }
                }

                SecureField("APIキー (sk-ant-...)", text: $apiKeyInput)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { saveAPIKey() }

                if !apiKeyInput.isEmpty || cloudAPIManager.isConfigured {
                    HStack {
                        Button {
                            saveAPIKey()
                        } label: {
                            Text("保存")
                        }
                        .disabled(apiKeyInput.isEmpty)

                        if cloudAPIManager.isConfigured {
                            Spacer()
                            Button(role: .destructive) {
                                apiKeyInput = ""
                                cloudAPIManager.apiKey = nil
                            } label: {
                                Text("削除")
                            }
                        }
                    }
                }

                if cloudAPIManager.isConfigured {
                    Picker("モデル", selection: Binding(
                        get: { cloudAPIManager.selectedModel },
                        set: { cloudAPIManager.saveModel($0) }
                    )) {
                        ForEach(CloudLLMModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model)
                        }
                    }

                    Button {
                        testAPIKey()
                    } label: {
                        HStack {
                            Label("接続テスト", systemImage: "checkmark.circle")
                            if isTestingAPI {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isTestingAPI)
                }
            } header: {
                Text("クラウドAPI（高精度・推奨）")
            } footer: {
                Text("Claude APIを使用して高精度なスポット情報抽出を行います。画像から直接認識するため、OCRの誤りに影響されません。APIキーはconsole.anthropic.comで取得できます。")
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
            // APIキーの先頭と末尾だけ表示
            if let key = cloudAPIManager.apiKey, !key.isEmpty {
                let prefix = String(key.prefix(10))
                let suffix = String(key.suffix(4))
                apiKeyInput = "\(prefix)...\(suffix)"
            }
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
        .alert("接続テスト", isPresented: $showingAPITestResult) {
            Button("OK") {}
        } message: {
            Text(apiTestResult ?? "")
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

    private func saveAPIKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        // マスクされた表示値の場合は保存しない
        guard !key.isEmpty, !key.contains("...") else { return }
        cloudAPIManager.apiKey = key
        // 保存後はマスク表示に切り替え
        let prefix = String(key.prefix(10))
        let suffix = String(key.suffix(4))
        apiKeyInput = "\(prefix)...\(suffix)"
    }

    private func testAPIKey() {
        isTestingAPI = true
        Task {
            do {
                let result = try await LLMService.shared.extractPOIInfo(from: "テスト: 東京カフェ\n東京都渋谷区1-2-3\nTEL: 03-1234-5678")
                if result.hasValidData {
                    apiTestResult = "接続成功！ 抽出結果: \(result.name ?? "名前なし")"
                } else {
                    apiTestResult = "接続成功（データ抽出なし）"
                }
            } catch {
                apiTestResult = "接続失敗: \(error.localizedDescription)"
            }
            isTestingAPI = false
            showingAPITestResult = true
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

            Section("クラウドAPI (Claude)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Anthropic社のClaude APIを使用した高精度な情報抽出です。")
                    Text("• 画像から直接スポット情報を認識（最高精度）")
                    Text("• 日本語の看板・メニューに強い")
                    Text("• APIキーと通信が必要")
                    Text("• 従量課金（1回あたり約0.5〜3円）")
                }
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("ローカルモデル・VLM・Apple Intelligenceは端末内で処理が完結します。")
                    Text("クラウドAPIを使用する場合、画像やテキストがAnthropicのサーバーに送信されます。Anthropicはユーザーデータをモデルのトレーニングに使用しません。")
                }
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
