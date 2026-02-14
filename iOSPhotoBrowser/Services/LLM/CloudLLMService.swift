//
//  CloudLLMService.swift
//  iOSPhotoBrowser
//
//  Claude API を使用したクラウドLLMサービス
//  画像から直接POI情報を高精度に抽出
//

import Combine
import Foundation
import UIKit

/// Claude API を使用したクラウドLLMサービス
actor CloudLLMService: LLMServiceProtocol {
    nonisolated let serviceName = "Claude API (Cloud)"

    nonisolated var isAvailable: Bool {
        get async {
            let key = await MainActor.run { CloudAPIKeyManager.shared.apiKey }
            return key != nil && !key!.isEmpty
        }
    }

    // MARK: - Text-based POI Extraction (LLMServiceProtocol)

    func extractPOIInfo(from ocrText: String) async throws -> ExtractedPOIData {
        let apiKey = try await getAPIKey()

        let response = try await callClaudeAPI(
            apiKey: apiKey,
            system: POIPrompts.system,
            messages: [
                ClaudeMessage(role: "user", content: [
                    .text(POIPrompts.userPromptForOCR(ocrText))
                ])
            ]
        )

        return POIPrompts.parseJSONResponse(response)
    }

    // MARK: - Image-based POI Extraction

    func extractPOIInfoFromImage(_ image: UIImage) async throws -> ExtractedPOIData {
        let apiKey = try await getAPIKey()

        // 画像をbase64エンコード（高解像度でテキストを保持）
        guard let resized = resizeImage(image, maxDimension: 1568),
              let imageData = resized.jpegData(compressionQuality: 0.92) else {
            throw LLMError.extractionFailed("画像のエンコードに失敗しました")
        }
        let base64String = imageData.base64EncodedString()

        let response = try await callClaudeAPI(
            apiKey: apiKey,
            system: POIPrompts.system,
            messages: [
                ClaudeMessage(role: "user", content: [
                    .image(ClaudeImageSource(
                        type: "base64",
                        mediaType: "image/jpeg",
                        data: base64String
                    )),
                    .text(POIPrompts.userPromptForImage)
                ])
            ]
        )

        return POIPrompts.parseJSONResponse(response)
    }

    // MARK: - Claude API Call

    private func callClaudeAPI(apiKey: String, system: String? = nil, messages: [ClaudeMessage]) async throws -> String {
        let model = await MainActor.run { CloudAPIKeyManager.shared.selectedModel }

        let requestBody = ClaudeRequest(
            model: model.apiModelId,
            max_tokens: 1024,
            system: system,
            messages: messages
        )

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)

        print("[CloudLLM] Sending request to Claude API (model: \(model.apiModelId))...")

        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        guard let response = httpResponse as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        if response.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            print("[CloudLLM] API error \(response.statusCode): \(errorBody)")

            if response.statusCode == 401 {
                throw LLMError.extractionFailed("APIキーが無効です")
            } else if response.statusCode == 429 {
                throw LLMError.extractionFailed("APIレート制限に達しました。しばらく待ってから再試行してください")
            } else {
                throw LLMError.extractionFailed("API error: \(response.statusCode)")
            }
        }

        // レスポンスをパース
        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)

        guard let textContent = claudeResponse.content.first(where: { $0.type == "text" }),
              let text = textContent.text else {
            throw LLMError.invalidResponse
        }

        print("[CloudLLM] Response: \(text.prefix(300))")
        return text
    }

    // MARK: - Private Helpers

    private func getAPIKey() async throws -> String {
        let key = await MainActor.run { CloudAPIKeyManager.shared.apiKey }
        guard let apiKey = key, !apiKey.isEmpty else {
            throw LLMError.extractionFailed("APIキーが設定されていません。設定画面でClaude APIキーを入力してください")
        }
        return apiKey
    }

    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage? {
        let size = image.size
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resized
    }

}

// MARK: - Claude API Models

private struct ClaudeRequest: Encodable {
    let model: String
    let max_tokens: Int
    let system: String?
    let messages: [ClaudeMessage]

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(max_tokens, forKey: .max_tokens)
        if let system = system {
            try container.encode(system, forKey: .system)
        }
        try container.encode(messages, forKey: .messages)
    }

    private enum CodingKeys: String, CodingKey {
        case model, max_tokens, system, messages
    }
}

private struct ClaudeMessage: Encodable {
    let role: String
    let content: [ClaudeContent]
}

private enum ClaudeContent: Encodable {
    case text(String)
    case image(ClaudeImageSource)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(ClaudeTextContent(type: "text", text: text))
        case .image(let source):
            try container.encode(ClaudeImageContent(type: "image", source: source))
        }
    }
}

private struct ClaudeTextContent: Encodable {
    let type: String
    let text: String
}

private struct ClaudeImageContent: Encodable {
    let type: String
    let source: ClaudeImageSource
}

private struct ClaudeImageSource: Encodable {
    let type: String
    let mediaType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

private struct ClaudeResponse: Decodable {
    let content: [ClaudeResponseContent]
}

private struct ClaudeResponseContent: Decodable {
    let type: String
    let text: String?
}

// MARK: - Cloud API Key Manager

@MainActor
final class CloudAPIKeyManager: ObservableObject {
    static let shared = CloudAPIKeyManager()

    @Published var selectedModel: CloudLLMModel = {
        if let raw = UserDefaults.standard.string(forKey: "cloud_llm_model"),
           let model = CloudLLMModel(rawValue: raw) {
            return model
        }
        return .sonnet
    }()

    private static let apiKeyKey = "cloud_api_key"

    private init() {}

    /// APIキーを取得（UserDefaultsから）
    var apiKey: String? {
        get { UserDefaults.standard.string(forKey: Self.apiKeyKey) }
        set {
            if let value = newValue, !value.isEmpty {
                UserDefaults.standard.set(value, forKey: Self.apiKeyKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.apiKeyKey)
            }
            objectWillChange.send()
        }
    }

    var isConfigured: Bool {
        guard let key = apiKey else { return false }
        return !key.isEmpty
    }

    func saveModel(_ model: CloudLLMModel) {
        selectedModel = model
        UserDefaults.standard.set(model.rawValue, forKey: "cloud_llm_model")
    }
}

// MARK: - Cloud LLM Model Selection

enum CloudLLMModel: String, CaseIterable {
    case haiku = "haiku"
    case sonnet = "sonnet"

    var displayName: String {
        switch self {
        case .haiku: return "Claude Haiku（高速・低コスト）"
        case .sonnet: return "Claude Sonnet（高精度・推奨）"
        }
    }

    var apiModelId: String {
        switch self {
        case .haiku: return "claude-haiku-4-5-20251001"
        case .sonnet: return "claude-sonnet-4-5-20250929"
        }
    }

    var description: String {
        switch self {
        case .haiku: return "応答が速く、コストが低い。簡単な看板に最適"
        case .sonnet: return "高精度。複雑な看板や手書き文字にも対応"
        }
    }
}
