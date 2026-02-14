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

// MARK: - Prompt Templates

/// スポット情報抽出用のプロンプトを生成
func makePOIExtractionPrompt(ocrText: String) -> String {
    """
    以下はレストランや店舗などの看板・メニュー・チラシ等の写真からOCRで読み取ったテキストです。
    このテキストからスポット情報を推論・抽出してJSON形式で出力してください。

    重要な注意点:
    - OCRは看板のテキストを行ごとに分割します。複数行にわたる情報は結合してください
    - 例: 「アパ社長カレー」「横浜ベイタワー店」→ 施設名は「アパ社長カレー 横浜ベイタワー店」
    - 例: 「東京都港区」「六本木1-2-3」→ 住所は「東京都港区六本木1-2-3」
    - 店名とブランド名・支店名が別の行にある場合は結合して1つの施設名にしてください
    - 住所の都道府県・市区町村・番地が別の行にある場合も結合してください

    OCRテキスト:
    \(ocrText)

    出力形式（JSONのみ、説明不要）:
    {
      "name": "施設名（店名+支店名を結合）",
      "address": "住所（複数行を結合）",
      "phone": "電話番号",
      "hours": "営業時間",
      "category": "カテゴリ（例：レストラン、カフェ、居酒屋、カレー店など）",
      "priceRange": "価格帯（例：¥1,000〜¥2,000）"
    }

    その他の注意:
    - 見つからない項目はnull
    - OCRの誤認識（0とO、1とIやl）を考慮して推測・修正
    - 施設名や住所の明らかな誤字は修正
    - 電話番号はハイフン区切りで出力
    - テキストの断片から施設の種類を推論してcategoryを設定
    """
}
