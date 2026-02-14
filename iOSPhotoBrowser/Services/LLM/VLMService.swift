//
//  VLMService.swift
//  iOSPhotoBrowser
//
//  Vision Language Model を使用した画像からのスポット情報抽出
//  MiniCPM-V 4.0 + llama.cpp による実装
//

import Combine
import Foundation
import UIKit

/// Vision Language Model サービス
/// 画像から直接スポット情報を抽出（OCR不要）
actor VLMService: VLMServiceProtocol {
    nonisolated let serviceName = "Vision LLM (MiniCPM-V)"

    private var wrapper: MTMDWrapper?
    private var isModelLoaded = false

    init() {}

    /// VLMが利用可能かどうか（モデルがダウンロード済みか）
    nonisolated var isAvailable: Bool {
        get async {
            await MainActor.run {
                VLMModelManager.shared.isModelDownloaded
            }
        }
    }

    /// モデルをメモリに読み込む
    func loadModel() async throws {
        let isDownloaded = await MainActor.run {
            VLMModelManager.shared.isModelDownloaded
        }
        guard isDownloaded else {
            throw LLMError.modelNotLoaded
        }

        guard !isModelLoaded else { return }

        let modelPath = await MainActor.run {
            VLMModelManager.shared.modelPath
        }
        let mmprojPath = await MainActor.run {
            VLMModelManager.shared.mmprojPath
        }

        guard let modelPath = modelPath, let mmprojPath = mmprojPath else {
            throw LLMError.modelNotLoaded
        }

        // MTMDWrapper を初期化
        let newWrapper = await MTMDWrapper()

        let params = MTMDParams(
            modelPath: modelPath,
            mmprojPath: mmprojPath,
            nPredict: 512,  // スポット情報抽出には十分
            nCtx: 4096,
            nThreads: 4,
            temperature: 0.3,  // 低めの温度で安定した出力
            useGPU: true,
            mmprojUseGPU: true,
            warmup: true
        )

        do {
            try await newWrapper.initialize(with: params)
            wrapper = newWrapper
            isModelLoaded = true
            print("[VLMService] Model loaded successfully")
        } catch {
            print("[VLMService] Failed to load model: \(error)")
            throw LLMError.modelNotLoaded
        }
    }

    /// モデルをメモリから解放
    func unloadModel() async {
        if let wrapper = wrapper {
            await wrapper.cleanup()
        }
        wrapper = nil
        isModelLoaded = false
        print("[VLMService] Model unloaded")
    }

    /// 画像からスポット情報を抽出
    func extractPOIInfo(from image: UIImage) async throws -> ExtractedPOIData {
        if !isModelLoaded {
            try await loadModel()
        }

        guard let wrapper = wrapper else {
            throw LLMError.modelNotLoaded
        }

        // 画像を一時ファイルに保存（MTMDWrapperはファイルパスを必要とする）
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")

        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw LLMError.extractionFailed("画像データの変換に失敗しました")
        }

        do {
            try imageData.write(to: tempURL)
        } catch {
            throw LLMError.extractionFailed("一時ファイルの作成に失敗しました: \(error.localizedDescription)")
        }

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        print("[VLMService] Starting extraction...")

        do {
            // 画像を追加
            try await wrapper.addImageInBackground(tempURL.path)

            // プロンプトを追加
            let prompt = makeVLMPOIExtractionPrompt()
            try await wrapper.addTextInBackground(prompt, role: "user")

            // 生成を開始
            try await wrapper.startGeneration()

            // 生成完了を待つ
            var response = ""
            let maxWaitTime: TimeInterval = 60  // 最大60秒待機
            let startTime = Date()

            while Date().timeIntervalSince(startTime) < maxWaitTime {
                let state = await wrapper.generationState
                let output = await wrapper.fullOutput

                if state == .completed {
                    response = output
                    break
                } else if case .failed(let error) = state {
                    throw LLMError.extractionFailed(error.localizedDescription)
                }

                try await Task.sleep(nanoseconds: 100_000_000)  // 0.1秒待機
            }

            if response.isEmpty {
                throw LLMError.extractionFailed("タイムアウト：応答がありませんでした")
            }

            print("[VLMService] Response: \(response.prefix(500))")

            // コンテキストをリセット
            await wrapper.reset()

            return parseJSONResponse(response)
        } catch let error as MTMDError {
            await wrapper.reset()
            throw LLMError.extractionFailed(error.localizedDescription)
        } catch let error as LLMError {
            await wrapper.reset()
            throw error
        } catch {
            await wrapper.reset()
            throw LLMError.extractionFailed(error.localizedDescription)
        }
    }

    // MARK: - Private Helpers

    private func parseJSONResponse(_ response: String) -> ExtractedPOIData {
        var jsonString = response

        // マークダウンコードブロックを除去
        if let startRange = response.range(of: "```json"),
           let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            jsonString = String(response[startRange.upperBound..<endRange.lowerBound])
        } else if let startRange = response.range(of: "```"),
                  let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            jsonString = String(response[startRange.upperBound..<endRange.lowerBound])
        }

        // 最初の { から最後の } までを抽出
        if let startIndex = jsonString.firstIndex(of: "{"),
           let endIndex = jsonString.lastIndex(of: "}") {
            jsonString = String(jsonString[startIndex...endIndex])
        }

        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        // JSONをパース
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[VLMService] Failed to parse JSON: \(jsonString.prefix(100))")
            return ExtractedPOIData(confidence: 0.1)
        }

        let name = json["name"] as? String
        let address = json["address"] as? String
        let phone = json["phone"] as? String
        let hours = json["hours"] as? String
        let category = json["category"] as? String
        let priceRange = json["priceRange"] as? String

        // 信頼度スコアを計算
        var confidence = 0.0
        var fields = 0
        if name != nil && !name!.isEmpty { fields += 1 }
        if address != nil && !address!.isEmpty { fields += 1 }
        if phone != nil && !phone!.isEmpty { fields += 1 }
        if hours != nil && !hours!.isEmpty { fields += 1 }
        if category != nil && !category!.isEmpty { fields += 1 }
        if priceRange != nil && !priceRange!.isEmpty { fields += 1 }
        confidence = Double(fields) / 6.0

        // VLMは画像から直接認識するため、信頼度にボーナス
        confidence = min(1.0, confidence + 0.2)

        return ExtractedPOIData(
            name: name,
            address: address,
            phoneNumber: phone,
            businessHours: hours,
            category: category,
            priceRange: priceRange,
            confidence: confidence
        )
    }
}

// MARK: - VLM Prompt

/// VLM用のスポット情報抽出プロンプト
private func makeVLMPOIExtractionPrompt() -> String {
    """
    この画像はレストランや店舗などの看板・メニュー・チラシ等の写真です。スポット情報を抽出してJSON形式で出力してください。

    出力形式（JSONのみ、説明不要）:
    {"name": "施設名", "address": "住所", "phone": "電話番号", "hours": "営業時間", "category": "カテゴリ", "priceRange": "価格帯"}

    注意:
    - 見つからない項目はnull
    - 施設名は店名とブランド名・支店名を結合して完全な名前にしてください
    - 住所は都道府県から番地まで結合してください
    - 日本語の場合は日本語で出力
    - テキストの断片から施設の種類を推論してcategoryを設定
    """
}

// MARK: - VLM Model Manager

/// VLMモデルのダウンロード・管理を行うマネージャー
@MainActor
final class VLMModelManager: ObservableObject {
    static let shared = VLMModelManager()

    @Published private(set) var downloadProgress: Double = 0.0
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadError: Error?

    private init() {}

    // MARK: - Model Information

    struct ModelInfo {
        // MiniCPM-V 4.0
        static let name = "MiniCPM-V 4.0"
        static let modelFileName = "ggml-model-Q4_0.gguf"
        static let mmprojFileName = "mmproj-model-f16.gguf"
        static let modelFileSize: Int64 = 2_080_000_000  // 約2.08GB
        static let mmprojFileSize: Int64 = 959_000_000   // 約959MB

        // ダウンロードURL（HuggingFace LFS）
        static let modelDownloadURL = "https://huggingface.co/openbmb/MiniCPM-V-4-gguf/resolve/main/ggml-model-Q4_0.gguf?download=true"
        static let mmprojDownloadURL = "https://huggingface.co/openbmb/MiniCPM-V-4-gguf/resolve/main/mmproj-model-f16.gguf?download=true"

        static var totalFileSize: Int64 {
            modelFileSize + mmprojFileSize
        }

        static var displayFileSize: String {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useGB, .useMB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: totalFileSize)
        }
    }

    // MARK: - Model Status

    var isModelDownloaded: Bool {
        guard let modelPath = modelPath, let mmprojPath = mmprojPath else { return false }
        return FileManager.default.fileExists(atPath: modelPath) &&
               FileManager.default.fileExists(atPath: mmprojPath)
    }

    var modelPath: String? {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsDir.appendingPathComponent("VLMModels/\(ModelInfo.modelFileName)").path
    }

    var mmprojPath: String? {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsDir.appendingPathComponent("VLMModels/\(ModelInfo.mmprojFileName)").path
    }

    // MARK: - Download

    @Published private(set) var currentDownloadFile: String = ""
    private var downloadTask: Task<Void, Error>?

    func startDownload() async throws {
        guard !isDownloading else { return }
        guard !isModelDownloaded else { return }

        // モデルディレクトリを作成
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw LLMError.downloadFailed("ドキュメントディレクトリにアクセスできません")
        }

        let modelsDir = documentsDir.appendingPathComponent("VLMModels")
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        isDownloading = true
        downloadProgress = 0.0
        downloadError = nil

        do {
            // 1. まずビジョンモデル（小さい方）をダウンロード
            if !hasVisionProjector {
                currentDownloadFile = "mmproj-model-f16.gguf"
                let mmprojDestURL = modelsDir.appendingPathComponent(ModelInfo.mmprojFileName)
                try await downloadFile(
                    from: URL(string: ModelInfo.mmprojDownloadURL)!,
                    to: mmprojDestURL,
                    expectedSize: ModelInfo.mmprojFileSize,
                    progressOffset: 0.0,
                    progressScale: 0.3  // 全体の30%
                )
            }

            // 2. 次に言語モデル（大きい方）をダウンロード
            if !hasLanguageModel {
                currentDownloadFile = "ggml-model-Q4_0.gguf"
                let modelDestURL = modelsDir.appendingPathComponent(ModelInfo.modelFileName)
                try await downloadFile(
                    from: URL(string: ModelInfo.modelDownloadURL)!,
                    to: modelDestURL,
                    expectedSize: ModelInfo.modelFileSize,
                    progressOffset: 0.3,
                    progressScale: 0.7  // 全体の70%
                )
            }

            isDownloading = false
            downloadProgress = 1.0
            currentDownloadFile = ""
            print("[VLMModelManager] All models downloaded successfully")
        } catch {
            isDownloading = false
            currentDownloadFile = ""
            downloadError = error
            throw error
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        currentDownloadFile = ""
        print("[VLMModelManager] Download cancelled")
    }

    private func downloadFile(
        from url: URL,
        to destination: URL,
        expectedSize: Int64,
        progressOffset: Double,
        progressScale: Double
    ) async throws {
        print("[VLMModelManager] Downloading: \(url)")

        // 既存ファイルを削除
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        // URLSessionDownloadTask + Delegate を使用（高速・効率的）
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForResource = 7200  // 2時間

            let delegate = VLMDownloadDelegate(
                expectedSize: expectedSize,
                progressOffset: progressOffset,
                progressScale: progressScale,
                destination: destination,
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress
                    }
                },
                onComplete: { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )

            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

            let task = session.downloadTask(with: request)
            task.resume()
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
        print("[VLMModelManager] Downloaded: \(destination.lastPathComponent) (\(fileSize) bytes)")
    }

    func deleteModel() throws {
        if let path = modelPath, FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
        if let path = mmprojPath, FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
        print("[VLMModelManager] Models deleted")
    }

    // MARK: - Import from File

    /// ファイルURLからモデルをインポート
    func importModel(from sourceURL: URL) throws -> ImportResult {
        let fileName = sourceURL.lastPathComponent

        // モデルディレクトリを作成
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw LLMError.downloadFailed("ドキュメントディレクトリにアクセスできません")
        }

        let modelsDir = documentsDir.appendingPathComponent("VLMModels")
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        // ファイル名に基づいてコピー先を決定
        var importType: ImportResult.ImportType = .unknown

        if fileName.contains("ggml-model") || fileName.contains("Q4") || fileName.contains("Q8") {
            // 言語モデル
            let destURL = modelsDir.appendingPathComponent(ModelInfo.modelFileName)
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            importType = .languageModel
            print("[VLMModelManager] Language model imported: \(destURL.path)")
        } else if fileName.contains("mmproj") {
            // Vision projector
            let destURL = modelsDir.appendingPathComponent(ModelInfo.mmprojFileName)
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            importType = .visionProjector
            print("[VLMModelManager] MMProj imported: \(destURL.path)")
        } else {
            throw LLMError.downloadFailed("不明なファイル形式です。ファイル名に 'ggml-model' または 'mmproj' が含まれている必要があります。")
        }

        return ImportResult(type: importType, isComplete: isModelDownloaded)
    }

    struct ImportResult {
        enum ImportType {
            case languageModel
            case visionProjector
            case unknown
        }
        let type: ImportType
        let isComplete: Bool

        var message: String {
            switch type {
            case .languageModel:
                if isComplete {
                    return "言語モデルをインポートしました。VLMの準備が完了しました。"
                } else {
                    return "言語モデルをインポートしました。ビジョンモデル (mmproj) もインポートしてください。"
                }
            case .visionProjector:
                if isComplete {
                    return "ビジョンモデルをインポートしました。VLMの準備が完了しました。"
                } else {
                    return "ビジョンモデルをインポートしました。言語モデル (ggml-model) もインポートしてください。"
                }
            case .unknown:
                return "ファイルをインポートしました。"
            }
        }
    }

    /// 個別のモデルファイルの存在確認
    var hasLanguageModel: Bool {
        guard let path = modelPath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    var hasVisionProjector: Bool {
        guard let path = mmprojPath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }
}

// MARK: - VLM Download Delegate

private class VLMDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let expectedSize: Int64
    let progressOffset: Double
    let progressScale: Double
    let destination: URL
    let onProgress: (Double) -> Void
    let onComplete: (Error?) -> Void

    init(
        expectedSize: Int64,
        progressOffset: Double,
        progressScale: Double,
        destination: URL,
        onProgress: @escaping (Double) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        self.expectedSize = expectedSize
        self.progressOffset = progressOffset
        self.progressScale = progressScale
        self.destination = destination
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
        let fileProgress = Double(totalBytesWritten) / Double(total)
        let overallProgress = progressOffset + (fileProgress * progressScale)
        onProgress(overallProgress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            // 既存ファイルを削除
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            // 一時ファイルを目的地に移動
            try FileManager.default.moveItem(at: location, to: destination)
            onComplete(nil)
        } catch {
            onComplete(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            onComplete(error)
        }
    }
}
