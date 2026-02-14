//
//  AppleFoundationModelsService.swift
//  iOSPhotoBrowser
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Foundation Models (iOS 26+) を使用したLLMサービス
/// システムに組み込まれたLLMを使用するため、追加のダウンロードは不要
@available(iOS 26.0, *)
actor AppleFoundationModelsService: LLMServiceProtocol {
    nonisolated let serviceName = "Apple Intelligence"

    #if canImport(FoundationModels)
    private var session: LanguageModelSession?
    #endif

    init() {}

    nonisolated var isAvailable: Bool {
        get async {
            #if canImport(FoundationModels)
            // FoundationModelsが利用可能かチェック
            // 実際のデバイスではA17 Pro以上のチップが必要
            return true
            #else
            return false
            #endif
        }
    }

    func extractPOIInfo(from ocrText: String) async throws -> ExtractedPOIData {
        #if canImport(FoundationModels)
        print("[AppleIntelligence] Starting extraction...")
        print("[AppleIntelligence] OCR Text length: \(ocrText.count) characters")

        let prompt = makePOIExtractionPrompt(ocrText: ocrText)

        do {
            // セッションを作成または再利用
            if session == nil {
                print("[AppleIntelligence] Creating new LanguageModelSession...")
                session = LanguageModelSession()
            }

            guard let session = session else {
                print("[AppleIntelligence] Failed to create session")
                throw LLMError.notAvailable
            }

            print("[AppleIntelligence] Sending prompt to model...")
            let response = try await session.respond(to: prompt)
            let responseText = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            print("[AppleIntelligence] Response received:")
            print("[AppleIntelligence] \(responseText.prefix(500))")

            let result = parseJSONResponse(responseText)
            print("[AppleIntelligence] Parsed result - Name: \(result.name ?? "nil"), Address: \(result.address ?? "nil"), Phone: \(result.phoneNumber ?? "nil")")
            return result
        } catch let error as LLMError {
            print("[AppleIntelligence] LLMError: \(error.localizedDescription)")
            throw error
        } catch {
            print("[AppleIntelligence] Error: \(error)")
            throw LLMError.extractionFailed(error.localizedDescription)
        }
        #else
        print("[AppleIntelligence] FoundationModels not available")
        throw LLMError.notAvailable
        #endif
    }

    // MARK: - Private Helpers

    private func parseJSONResponse(_ response: String) -> ExtractedPOIData {
        // JSONブロックを抽出（```json ... ``` や直接JSONの両方に対応）
        var jsonString = response

        // マークダウンのコードブロックを除去
        if let startRange = response.range(of: "```json"),
           let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            jsonString = String(response[startRange.upperBound..<endRange.lowerBound])
        } else if let startRange = response.range(of: "```"),
                  let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            jsonString = String(response[startRange.upperBound..<endRange.lowerBound])
        }

        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        // JSONをパース
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // パース失敗時は正規表現で施設名と住所を抽出
            return extractFromPlainText(response)
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
        if name != nil { fields += 1 }
        if address != nil { fields += 1 }
        if phone != nil { fields += 1 }
        if hours != nil { fields += 1 }
        if category != nil { fields += 1 }
        if priceRange != nil { fields += 1 }
        confidence = Double(fields) / 6.0

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

    /// JSONパース失敗時のフォールバック
    private func extractFromPlainText(_ text: String) -> ExtractedPOIData {
        var name: String?
        var address: String?
        var phone: String?

        // 施設名パターン: 「施設名: xxx」や「name: xxx」
        let namePatterns = ["施設名[：:]\\s*(.+)", "店名[：:]\\s*(.+)", "name[：:]\\s*(.+)"]
        for pattern in namePatterns {
            if let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let line = String(text[match])
                if let colonIndex = line.firstIndex(of: ":") ?? line.firstIndex(of: "：") {
                    name = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }

        // 住所パターン
        let addressPatterns = ["住所[：:]\\s*(.+)", "address[：:]\\s*(.+)"]
        for pattern in addressPatterns {
            if let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let line = String(text[match])
                if let colonIndex = line.firstIndex(of: ":") ?? line.firstIndex(of: "：") {
                    address = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }

        // 電話番号パターン
        let phonePatterns = ["電話[：:]\\s*(.+)", "TEL[：:]\\s*(.+)", "phone[：:]\\s*(.+)"]
        for pattern in phonePatterns {
            if let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let line = String(text[match])
                if let colonIndex = line.firstIndex(of: ":") ?? line.firstIndex(of: "：") {
                    phone = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }

        return ExtractedPOIData(
            name: name,
            address: address,
            phoneNumber: phone,
            confidence: 0.3  // プレーンテキスト抽出は低信頼度
        )
    }
}
