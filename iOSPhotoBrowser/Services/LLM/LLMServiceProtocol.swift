//
//  LLMServiceProtocol.swift
//  iOSPhotoBrowser
//

import Foundation

// MARK: - Extracted Data Model

/// LLMが抽出したスポット情報
struct ExtractedPOIData: Sendable {
    var name: String?
    var address: String?
    var phoneNumber: String?
    var businessHours: String?
    var category: String?
    var priceRange: String?
    var confidence: Double  // 0.0-1.0 の信頼度スコア

    init(
        name: String? = nil,
        address: String? = nil,
        phoneNumber: String? = nil,
        businessHours: String? = nil,
        category: String? = nil,
        priceRange: String? = nil,
        confidence: Double = 0.0
    ) {
        self.name = name
        self.address = address
        self.phoneNumber = phoneNumber
        self.businessHours = businessHours
        self.category = category
        self.priceRange = priceRange
        self.confidence = confidence
    }

    /// 有効なデータが含まれているかどうか
    var hasValidData: Bool {
        name != nil || address != nil
    }
}

// MARK: - LLM Service Protocol

/// LLMサービスのプロトコル
/// 各LLM実装（Apple Foundation Models、llama.cpp）はこのプロトコルに準拠する
protocol LLMServiceProtocol {
    /// OCRテキストからスポット情報を抽出
    func extractPOIInfo(from ocrText: String) async throws -> ExtractedPOIData

    /// サービスが利用可能かどうか
    var isAvailable: Bool { get async }

    /// サービス名（デバッグ・表示用）
    var serviceName: String { get }
}

// MARK: - VLM Service Protocol

import UIKit

/// Vision Language Model サービスのプロトコル
/// 画像から直接スポット情報を抽出（OCR不要）
protocol VLMServiceProtocol {
    /// 画像からスポット情報を抽出
    func extractPOIInfo(from image: UIImage) async throws -> ExtractedPOIData

    /// サービスが利用可能かどうか
    var isAvailable: Bool { get async }

    /// サービス名（デバッグ・表示用）
    var serviceName: String { get }

    /// モデルをメモリに読み込む
    func loadModel() async throws

    /// モデルをメモリから解放
    func unloadModel() async
}

// MARK: - LLM Errors

enum LLMError: Error, LocalizedError {
    case notAvailable
    case modelNotLoaded
    case extractionFailed(String)
    case invalidResponse
    case downloadFailed(String)
    case insufficientStorage

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "LLMサービスが利用できません"
        case .modelNotLoaded:
            return "モデルが読み込まれていません"
        case .extractionFailed(let reason):
            return "スポット情報の抽出に失敗しました: \(reason)"
        case .invalidResponse:
            return "無効なレスポンスです"
        case .downloadFailed(let reason):
            return "モデルのダウンロードに失敗しました: \(reason)"
        case .insufficientStorage:
            return "ストレージ容量が不足しています"
        }
    }
}

// MARK: - LLM Configuration

/// LLMサービスの設定
enum LLMEnginePreference: String, CaseIterable {
    case auto = "auto"
    case cloudAPI = "cloud"
    case appleIntelligence = "apple"
    case localModel = "local"
    case none = "none"

    var displayName: String {
        switch self {
        case .auto: return "自動（推奨）"
        case .cloudAPI: return "クラウドAPI"
        case .appleIntelligence: return "Apple Intelligence"
        case .localModel: return "ローカルモデル"
        case .none: return "使用しない"
        }
    }

    var description: String {
        switch self {
        case .auto: return "クラウドAPI → Apple Intelligence → ローカルの順で自動選択"
        case .cloudAPI: return "Claude APIで高精度な抽出（要APIキー・通信）"
        case .appleIntelligence: return "iOS 26以降で利用可能"
        case .localModel: return "オフライン対応、約2GBのダウンロードが必要"
        case .none: return "LLMを使用せず、OCRテキストのみを使用"
        }
    }
}

// MARK: - Unified Prompt Templates

/// 全LLMサービス共通のプロンプト定義
/// モデルを跨いでも同一スキーマ・同一出力制約で統一する
enum POIPrompts {

    /// システムプロンプト（Claude API等、system roleをサポートするモデル向け）
    static let system = """
    あなたは画像やテキストから店舗・施設情報を構造化データへ変換する情報抽出エンジンです。

    以下のルールを厳守してください：
    1. 事実のみ抽出してください。推測はしないでください。
    2. 不明な項目は null としてください。
    3. 出力は必ず valid JSON のみ。説明文は禁止。
    4. 電話番号はハイフン区切りで出力（例: 045-123-4567）
    5. 価格は表記通りに抽出（例: ¥800〜¥1,500）

    ## 抽出ルール

    ## 画像内の注目優先順位（重要）
    写真には複数のテキスト要素が写っています。以下の優先順位で情報を読み取ってください：
    1. **メインの店舗看板・エントランスサイン**（最も大きく目立つ文字）→ 施設名の最優先ソース
    2. **入口付近の営業情報パネル**（営業時間、電話番号、住所）
    3. **暖簾・のれん・ロゴマーク**
    4. メニューボード・販促ポスター等は施設名の判定には使わないでください（価格帯の参考にのみ使用可）

    **name（施設名）**: 最も重要なフィールドです。
    - メインの看板・エントランスサインに書かれている正式な店名を抽出
    - 小さなメニュー表示やポスターの文字ではなく、最も大きく表示されている店名を優先
    - ブランド名＋支店名がある場合は必ず結合（例:「アパ社長カレー」+「横浜ベイタワー店」→「アパ社長カレー 横浜ベイタワー店」）
    - チェーン店の場合は「ブランド名 支店名」の形式
    - 装飾的な文字（★、♪等）は除去

    **address（住所）**: 都道府県から番地・建物名まで結合してフルの住所にする。断片が散らばっている場合も1つにまとめる。

    **phone（電話番号）**: ハイフン区切り

    **hours（営業時間）**: 開店〜閉店時間。曜日による違いがあれば含める。

    **category（カテゴリ）**: 施設の種類を日本語で（例: カレー店、ラーメン店、カフェ、居酒屋、イタリアン、中華料理、焼肉店、寿司店、パン屋、バー、定食屋、レストラン、美容院、ホテル等）

    **priceRange（価格帯）**: 例: ¥800〜¥1,500

    ## 出力形式
    必ず以下のJSON形式のみを出力してください。説明文は不要です。
    ```json
    {"name": "...", "address": "...", "phone": "...", "hours": "...", "category": "...", "priceRange": "..."}
    ```
    情報が読み取れないフィールドはnullにしてください。
    """

    /// OCRテキストからの抽出用ユーザープロンプト
    static func userPromptForOCR(_ ocrText: String) -> String {
        """
        以下はレストランや店舗などの看板・メニュー・チラシ等の写真からOCRで読み取ったテキストです。
        このテキストから事実として読み取れるスポット情報を抽出してJSON形式で出力してください。

        重要な注意点:
        - 事実のみ抽出。推測はしない。不明な項目は null。
        - 施設名は、メニュー品目やキャンペーン文言ではなく、店舗の正式名称を選んでください
        - OCRテキストにはメニュー内容や宣伝文句も混在します。施設名と区別してください
        - OCRは看板のテキストを行ごとに分割します。複数行にわたる情報は結合してください
        - 例: 「アパ社長カレー」「横浜ベイタワー店」→ name: "アパ社長カレー 横浜ベイタワー店"
        - 例: 「東京都港区」「六本木1-2-3」→ address: "東京都港区六本木1-2-3"
        - OCRの誤認識（0とO、1とIやl）は修正してください
        - 電話番号はハイフン区切りで出力

        OCRテキスト:
        \(ocrText)

        出力形式（JSONのみ、説明不要）:
        {"name": "施設名", "address": "住所", "phone": "電話番号", "hours": "営業時間", "category": "カテゴリ", "priceRange": "価格帯"}
        """
    }

    /// 画像からの直接抽出用ユーザープロンプト
    static let userPromptForImage = """
    この画像に写っている店舗・施設のスポット情報を抽出してJSON形式で出力してください。

    注目すべき場所の優先順位:
    1. メインの店舗看板・エントランスサイン（最も大きく目立つ文字）→ 施設名の最優先ソース
    2. 入口付近の営業情報パネル（営業時間、電話番号、住所）
    3. 暖簾・のれん・ロゴマーク
    ※ 小さなメニューボードや販促ポスターの文字は施設名として使わないでください

    ルール:
    - 事実のみ抽出。推測はしない。不明な項目は null。
    - 施設名はメインの看板に書かれた最も大きく目立つ名前を採用してください
    - ブランド名＋支店名がある場合は結合して完全な名前にしてください
    - 住所は都道府県から番地まで結合してください
    - 日本語の場合は日本語で出力

    出力形式（JSONのみ、説明不要）:
    {"name": "施設名", "address": "住所", "phone": "電話番号", "hours": "営業時間", "category": "カテゴリ", "priceRange": "価格帯"}
    """

    /// JSON応答をパースしてExtractedPOIDataに変換する共通処理
    static func parseJSONResponse(_ response: String) -> ExtractedPOIData {
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
            print("[POIPrompts] Failed to parse JSON: \(jsonString.prefix(200))")
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
