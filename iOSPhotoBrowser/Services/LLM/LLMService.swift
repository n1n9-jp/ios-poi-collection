//
//  LLMService.swift
//  iOSPhotoBrowser
//

import Foundation
import UIKit

/// LLMサービスのファサード
/// ユーザー設定と利用可能性に基づいて適切なLLMサービスにルーティング
actor LLMService {
    static let shared = LLMService()

    private var appleService: (any LLMServiceProtocol)?
    private var llamaService: LlamaService?
    private var vlmService: VLMService?

    private init() {
        // Apple Foundation Models サービスの初期化（iOS 26以降）
        if #available(iOS 26.0, *) {
            appleService = AppleFoundationModelsService()
        }

        // Llama サービスの初期化
        llamaService = LlamaService()

        // VLM サービスの初期化
        vlmService = VLMService()
    }

    // MARK: - Public Interface

    /// 利用可能なLLMを使用して書籍情報を抽出
    func extractBookInfo(from ocrText: String) async throws -> ExtractedBookData {
        let preference = await MainActor.run { LLMModelManager.shared.enginePreference }

        switch preference {
        case .none:
            // LLMを使用しない
            throw LLMError.notAvailable

        case .appleIntelligence:
            // Apple Intelligence のみを試行
            return try await extractWithApple(from: ocrText)

        case .localModel:
            // ローカルモデルのみを試行
            return try await extractWithLlama(from: ocrText)

        case .auto:
            // 自動選択：Apple Intelligence → ローカルモデルの順で試行
            return try await extractWithAuto(from: ocrText)
        }
    }

    /// 現在利用可能なサービスの名前を取得
    func availableServiceName() async -> String? {
        let preference = await MainActor.run { LLMModelManager.shared.enginePreference }

        switch preference {
        case .none:
            return nil
        case .appleIntelligence:
            if #available(iOS 26.0, *), let service = appleService, await service.isAvailable {
                return service.serviceName
            }
            return nil
        case .localModel:
            if let service = llamaService, await service.isAvailable {
                return service.serviceName
            }
            return nil
        case .auto:
            if #available(iOS 26.0, *), let service = appleService, await service.isAvailable {
                return service.serviceName
            }
            if let service = llamaService, await service.isAvailable {
                return service.serviceName
            }
            return nil
        }
    }

    /// いずれかのLLMサービスが利用可能かどうか
    func isAnyServiceAvailable() async -> Bool {
        let preference = await MainActor.run { LLMModelManager.shared.enginePreference }
        print("[LLMService] Checking availability, preference: \(preference)")

        switch preference {
        case .none:
            print("[LLMService] LLM disabled by user")
            return false
        case .appleIntelligence:
            if #available(iOS 26.0, *), let service = appleService {
                let available = await service.isAvailable
                print("[LLMService] Apple Intelligence available: \(available)")
                return available
            }
            print("[LLMService] Apple Intelligence not available (iOS < 26)")
            return false
        case .localModel:
            if let service = llamaService {
                let available = await service.isAvailable
                print("[LLMService] Local model available: \(available)")
                return available
            }
            print("[LLMService] Local model service not initialized")
            return false
        case .auto:
            if #available(iOS 26.0, *), let service = appleService {
                let appleAvailable = await service.isAvailable
                print("[LLMService] Auto mode - Apple Intelligence available: \(appleAvailable)")
                if appleAvailable { return true }
            }
            if let service = llamaService {
                let llamaAvailable = await service.isAvailable
                print("[LLMService] Auto mode - Local model available: \(llamaAvailable)")
                if llamaAvailable { return true }
            }
            print("[LLMService] No LLM service available")
            return false
        }
    }

    // MARK: - Private Methods

    private func extractWithApple(from ocrText: String) async throws -> ExtractedBookData {
        guard #available(iOS 26.0, *), let service = appleService else {
            throw LLMError.notAvailable
        }
        guard await service.isAvailable else {
            throw LLMError.notAvailable
        }
        return try await service.extractBookInfo(from: ocrText)
    }

    private func extractWithLlama(from ocrText: String) async throws -> ExtractedBookData {
        guard let service = llamaService else {
            throw LLMError.notAvailable
        }
        guard await service.isAvailable else {
            throw LLMError.modelNotLoaded
        }
        return try await service.extractBookInfo(from: ocrText)
    }

    private func extractWithAuto(from ocrText: String) async throws -> ExtractedBookData {
        // 1. Apple Intelligence を試行
        if #available(iOS 26.0, *), let service = appleService, await service.isAvailable {
            do {
                let result = try await service.extractBookInfo(from: ocrText)
                print("[LLMService] Extracted using \(service.serviceName)")
                return result
            } catch {
                print("[LLMService] Apple Intelligence failed: \(error.localizedDescription)")
                // フォールスルーしてローカルモデルを試行
            }
        }

        // 2. ローカルモデル（llama.cpp）を試行
        if let service = llamaService, await service.isAvailable {
            do {
                let result = try await service.extractBookInfo(from: ocrText)
                print("[LLMService] Extracted using \(service.serviceName)")
                return result
            } catch {
                print("[LLMService] Local model failed: \(error.localizedDescription)")
            }
        }

        // 3. どちらも利用不可
        throw LLMError.notAvailable
    }

    // MARK: - Model Management

    /// ローカルモデルをメモリに読み込む
    func loadLocalModel() async throws {
        guard let service = llamaService else {
            throw LLMError.notAvailable
        }
        try await service.loadModel()
    }

    /// ローカルモデルをメモリから解放
    func unloadLocalModel() async {
        await llamaService?.unloadModel()
    }

    // MARK: - VLM (Vision Language Model) Methods

    /// 画像から直接書籍情報を抽出（VLM使用、OCR不要）
    func extractBookInfoFromImage(_ image: UIImage) async throws -> ExtractedBookData {
        guard let service = vlmService else {
            throw LLMError.notAvailable
        }
        guard await service.isAvailable else {
            throw LLMError.modelNotLoaded
        }
        return try await service.extractBookInfo(from: image)
    }

    /// VLMが利用可能かどうか
    func isVLMAvailable() async -> Bool {
        guard let service = vlmService else { return false }
        return await service.isAvailable
    }

    /// VLMモデルをメモリに読み込む
    func loadVLMModel() async throws {
        guard let service = vlmService else {
            throw LLMError.notAvailable
        }
        try await service.loadModel()
    }

    /// VLMモデルをメモリから解放
    func unloadVLMModel() async {
        await vlmService?.unloadModel()
    }
}

// MARK: - Convenience Extension for OCRService

extension LLMService {
    /// OCRテキストから書籍情報を抽出（失敗時は空のデータを返す）
    func extractBookInfoOrEmpty(from ocrText: String) async -> ExtractedBookData {
        do {
            return try await extractBookInfo(from: ocrText)
        } catch {
            print("[LLMService] Extraction failed: \(error.localizedDescription)")
            return ExtractedBookData()
        }
    }

    /// 画像から書籍情報を抽出（失敗時は空のデータを返す）
    func extractBookInfoFromImageOrEmpty(_ image: UIImage) async -> ExtractedBookData {
        do {
            return try await extractBookInfoFromImage(image)
        } catch {
            print("[LLMService] VLM extraction failed: \(error.localizedDescription)")
            return ExtractedBookData()
        }
    }

    /// 最適な方法で書籍情報を抽出（VLM優先、フォールバックとしてOCR+LLM）
    func extractBookInfoBestMethod(image: UIImage, ocrText: String?) async -> ExtractedBookData {
        // 1. VLMが利用可能なら画像から直接抽出
        if await isVLMAvailable() {
            let result = await extractBookInfoFromImageOrEmpty(image)
            if result.hasValidData {
                print("[LLMService] Extracted using VLM")
                return result
            }
        }

        // 2. OCRテキストがあればLLMで処理
        if let ocrText = ocrText, !ocrText.isEmpty {
            let result = await extractBookInfoOrEmpty(from: ocrText)
            if result.hasValidData {
                print("[LLMService] Extracted using OCR+LLM")
                return result
            }
        }

        // 3. 抽出失敗
        print("[LLMService] No valid extraction result")
        return ExtractedBookData()
    }
}
