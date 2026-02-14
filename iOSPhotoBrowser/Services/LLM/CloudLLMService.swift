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

    // MARK: - System Prompt

    private let systemPrompt = """
    あなたは日本のレストラン・店舗・施設の情報を正確に抽出するスペシャリストです。

    ユーザーから画像またはOCRテキストが提供されます。そこから以下のスポット情報を抽出してJSONで返してください。

    ## 抽出ルール

    **name（施設名）**: 最も重要なフィールドです。
    - 看板やロゴに書かれている正式な店名を抽出
    - ブランド名＋支店名がある場合は必ず結合（例:「アパ社長カレー」+「横浜ベイタワー店」→「アパ社長カレー 横浜ベイタワー店」）
    - チェーン店の場合は「ブランド名 支店名」の形式
    - 装飾的な文字（★、♪等）は除去

    **address（住所）**: 都道府県から番地・建物名まで結合してフルの住所にする。断片が散らばっている場合も1つにまとめる。

    **phone（電話番号）**: ハイフン区切り（例: 045-123-4567）

    **hours（営業時間）**: 開店〜閉店時間。曜日による違いがあれば含める。

    **category（カテゴリ）**: 施設の種類を日本語で（例: カレー店、ラーメン店、カフェ、居酒屋、イタリアン、中華料理、焼肉店、寿司店、パン屋、バー、定食屋、レストラン、美容院、ホテル等）

    **priceRange（価格帯）**: 例: ¥800〜¥1,500

    ## 出力形式
    必ず以下のJSON形式のみを出力してください。説明文は不要です。
    ```json
    {"name": "...", "address": "...", "phone": "...", "hours": "...", "category": "...", "priceRange": "..."}
    ```
    情報が読み取れないフィールドはnullにしてください。ただし、nameは画像/テキストに何らかの店舗・施設名が含まれている限り必ず抽出してください。
    """

    // MARK: - Text-based POI Extraction (LLMServiceProtocol)

    func extractPOIInfo(from ocrText: String) async throws -> ExtractedPOIData {
        let apiKey = try await getAPIKey()

        let prompt = """
        以下はOCRで読み取ったテキストです。スポット情報を抽出してJSONで出力してください。

        OCRテキスト:
        \(ocrText)
        """

        let response = try await callClaudeAPI(
            apiKey: apiKey,
            system: systemPrompt,
            messages: [
                ClaudeMessage(role: "user", content: [
                    .text(prompt)
                ])
            ]
        )

        return parseJSONResponse(response)
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

        let prompt = "この画像に写っている店舗・施設のスポット情報をJSONで抽出してください。"

        let response = try await callClaudeAPI(
            apiKey: apiKey,
            system: systemPrompt,
            messages: [
                ClaudeMessage(role: "user", content: [
                    .image(ClaudeImageSource(
                        type: "base64",
                        mediaType: "image/jpeg",
                        data: base64String
                    )),
                    .text(prompt)
                ])
            ]
        )

        return parseJSONResponse(response)
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

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[CloudLLM] Failed to parse JSON: \(jsonString.prefix(200))")
            return ExtractedPOIData()
        }

        let name = json["name"] as? String
        let address = json["address"] as? String
        let phone = json["phone"] as? String
        let hours = json["hours"] as? String
        let category = json["category"] as? String
        let priceRange = json["priceRange"] as? String

        var fields = 0
        if name != nil && !name!.isEmpty { fields += 1 }
        if address != nil && !address!.isEmpty { fields += 1 }
        if phone != nil && !phone!.isEmpty { fields += 1 }
        if hours != nil && !hours!.isEmpty { fields += 1 }
        if category != nil && !category!.isEmpty { fields += 1 }
        if priceRange != nil && !priceRange!.isEmpty { fields += 1 }
        let confidence = Double(fields) / 6.0

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
