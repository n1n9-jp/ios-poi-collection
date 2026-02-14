//
//  OCRService.swift
//  iOSPhotoBrowser
//

import Foundation
import Vision
import UIKit

#if canImport(FoundationModels)
import FoundationModels
#endif

actor OCRService {
    static let shared = OCRService()

    // POIドメインのカスタム語彙（OCR精度向上用）
    private let poiDomainWords: [String] = [
        // 施設種別
        "レストラン", "カフェ", "居酒屋", "バー", "ラーメン",
        "焼肉", "寿司", "蕎麦", "うどん", "定食",
        "ビストロ", "トラットリア", "ブラッスリー",
        "ベーカリー", "パティスリー", "ブーランジェリー",
        // 営業情報
        "営業時間", "定休日", "年中無休", "不定休",
        "ランチ", "ディナー", "モーニング", "ラストオーダー",
        "L.O.", "OPEN", "CLOSE", "LUNCH", "DINNER",
        // 連絡先・場所
        "住所", "電話", "TEL", "FAX", "予約",
        "席数", "駐車場", "アクセス",
        // 価格
        "円", "税込", "税別", "税抜",
        "コース", "飲み放題", "食べ放題",
        // 一般
        "店名", "店舗", "支店", "本店", "〒"
    ]

    private init() {}

    func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                let recognizedText = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")

                continuation.resume(returning: recognizedText)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = true
            request.customWords = self.poiDomainWords

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Apple Intelligence OCR補正

    /// Apple Intelligence を使用してOCRテキストを補正・正規化
    @available(iOS 26.0, *)
    private func correctOCRTextWithAI(_ rawText: String) async -> String {
        #if canImport(FoundationModels)
        do {
            let session = LanguageModelSession()

            let prompt = """
            以下はレストランや店舗の看板・メニュー等からOCRで読み取ったテキストです。
            OCRの誤認識を修正し、スポット情報として整形してください。

            特に注意する点：
            - 電話番号の数字の誤り（0とO、1とI/lなど）を修正
            - 店名、住所の誤字を修正
            - 営業時間の表記を正規化
            - 価格表記の正規化

            入力テキスト:
            \(rawText)

            修正後のテキストのみを出力してください（説明不要）:
            """

            let response = try await session.respond(to: prompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            // Apple Intelligence が利用不可または失敗した場合は元のテキストを返す
            print("Apple Intelligence correction failed: \(error)")
            return rawText
        }
        #else
        return rawText
        #endif
    }

    /// OCR実行後に自動でApple Intelligence補正を適用
    func recognizeTextWithCorrection(from image: UIImage) async throws -> String {
        let rawText = try await recognizeText(from: image)

        // Apple Intelligence が利用可能なら補正を適用
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await correctOCRTextWithAI(rawText)
        }
        #endif

        return rawText
    }

    // MARK: - LLM統合によるスポット情報抽出

    /// OCR + LLMで画像からスポット情報を抽出
    /// - Parameter image: レストランや店舗の画像
    /// - Returns: 抽出されたスポット情報（施設名、住所、電話番号等）と生のOCRテキスト
    func extractPOIInfoWithLLM(from image: UIImage) async throws -> (poiData: ExtractedPOIData, rawText: String) {
        // Step 1: OCRでテキスト抽出（補正付き）
        let ocrText = try await recognizeTextWithCorrection(from: image)

        // Step 2: LLMサービスが利用可能か確認
        let llmAvailable = await LLMService.shared.isAnyServiceAvailable()

        if llmAvailable {
            // Step 3a: LLMで構造化データ抽出
            let poiData = await LLMService.shared.extractPOIInfoOrEmpty(from: ocrText)
            return (poiData, ocrText)
        } else {
            // Step 3b: LLMなしの場合、空のデータを返す
            let poiData = ExtractedPOIData(confidence: 0.0)
            return (poiData, ocrText)
        }
    }

    /// LLMの利用可否に関わらず、最善の方法でスポット情報を抽出
    /// VLM（Vision Language Model）が利用可能な場合は画像から直接抽出を試み、
    /// そうでない場合はOCR + LLMのフローにフォールバック
    func extractPOIInfoBestEffort(from image: UIImage) async throws -> (poiData: ExtractedPOIData, rawText: String, usedLLM: Bool) {
        print("[OCRService] Starting extractPOIInfoBestEffort...")

        // Step 1: クラウドAPI（Claude Vision）で画像から直接抽出（最高精度）
        let cloudAvailable = await LLMService.shared.isCloudAPIAvailable()
        print("[OCRService] Cloud API available: \(cloudAvailable)")

        if cloudAvailable {
            print("[OCRService] Trying Cloud API image extraction...")
            do {
                let cloudResult = try await LLMService.shared.extractPOIInfoFromImageWithCloud(image)
                if cloudResult.hasValidData {
                    print("[OCRService] Cloud API result - Name: \(cloudResult.name ?? "nil"), Address: \(cloudResult.address ?? "nil"), Confidence: \(cloudResult.confidence)")
                    return (cloudResult, "[Cloud API抽出]", true)
                }
            } catch {
                print("[OCRService] Cloud API extraction failed: \(error.localizedDescription)")
            }
        }

        // Step 2: VLM（Vision Language Model）で直接抽出を試みる
        let vlmAvailable = await LLMService.shared.isVLMAvailable()
        print("[OCRService] VLM available: \(vlmAvailable)")

        if vlmAvailable {
            print("[OCRService] Trying VLM extraction...")
            let vlmResult = await LLMService.shared.extractPOIInfoFromImageOrEmpty(image)

            if vlmResult.hasValidData {
                print("[OCRService] VLM result - Name: \(vlmResult.name ?? "nil"), Address: \(vlmResult.address ?? "nil"), Confidence: \(vlmResult.confidence)")
                return (vlmResult, "[VLM抽出]", true)
            } else {
                print("[OCRService] VLM extraction failed or returned empty data, falling back to OCR+LLM")
            }
        }

        // Step 3: OCR + ルールベース + LLMのハイブリッドフロー
        let ocrText = try await recognizeTextWithCorrection(from: image)
        print("[OCRService] OCR completed. Text length: \(ocrText.count)")
        print("[OCRService] OCR Text: \(ocrText.prefix(200))...")

        // Step 3a: ルールベースで基本抽出（常に実行）
        let ruleResult = OCRService.extractPOIInfoByRules(from: ocrText)
        print("[OCRService] Rule-based result - Name: \(ruleResult.name ?? "nil"), Address: \(ruleResult.address ?? "nil"), Phone: \(ruleResult.phoneNumber ?? "nil")")

        // Step 3b: LLMが利用可能なら追加で抽出して結果をマージ
        let llmAvailable = await LLMService.shared.isAnyServiceAvailable()
        print("[OCRService] LLM available: \(llmAvailable)")

        if llmAvailable {
            print("[OCRService] Calling LLM for extraction...")
            let llmResult = await LLMService.shared.extractPOIInfoOrEmpty(from: ocrText)
            print("[OCRService] LLM result - Name: \(llmResult.name ?? "nil"), Address: \(llmResult.address ?? "nil"), Phone: \(llmResult.phoneNumber ?? "nil")")

            let merged = OCRService.mergeExtractedData(rule: ruleResult, llm: llmResult)
            print("[OCRService] Merged result - Name: \(merged.name ?? "nil"), Address: \(merged.address ?? "nil"), Phone: \(merged.phoneNumber ?? "nil")")
            return (merged, ocrText, merged.hasValidData)
        } else {
            print("[OCRService] LLM not available, using rule-based result")
            return (ruleResult, ocrText, ruleResult.hasValidData)
        }
    }

    // MARK: - ルールベース抽出（LLM不要）

    /// OCRテキストから正規表現・ヒューリスティクスでスポット情報を抽出
    /// LLMが利用できない場合や、LLMの精度が低い場合のフォールバック
    static func extractPOIInfoByRules(from ocrText: String) -> ExtractedPOIData {
        let lines = ocrText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var phone: String?
        var address: String?
        var hours: String?
        var category: String?
        var priceRange: String?
        var nameLines: [String] = []
        var usedLineIndices: Set<Int> = []

        // Pass 1: 電話番号を抽出
        let phonePatterns = [
            "(?:TEL|Tel|tel|電話|☎)[：:\\s]*([\\d\\-()（）]+)",
            "(0\\d{1,4}[\\-ー]\\d{1,4}[\\-ー]\\d{2,4})",
            "(\\d{2,4}-\\d{2,4}-\\d{3,4})"
        ]
        for (i, line) in lines.enumerated() {
            if usedLineIndices.contains(i) { continue }
            for pattern in phonePatterns {
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                   let range = Range(match.range(at: 1), in: line) {
                    phone = String(line[range])
                        .replacingOccurrences(of: "（", with: "(")
                        .replacingOccurrences(of: "）", with: ")")
                    usedLineIndices.insert(i)
                    break
                }
            }
            if phone != nil { break }
        }

        // Pass 2: 住所を抽出
        let addressPatterns = [
            "(?:住所|所在地)[：:\\s]*(.*)",
            "(〒?\\d{3}[\\-ー]\\d{4}.*)",
            "((?:東京都|北海道|(?:大阪|京都)府|.{2,3}県).+)"
        ]
        for (i, line) in lines.enumerated() {
            if usedLineIndices.contains(i) { continue }
            for pattern in addressPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                    let captureRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
                    if let range = Range(captureRange, in: line) {
                        var addr = String(line[range])
                        usedLineIndices.insert(i)
                        // 次の行が番地の続きの可能性
                        if i + 1 < lines.count && !usedLineIndices.contains(i + 1) {
                            let nextLine = lines[i + 1]
                            if nextLine.range(of: "^[\\d\\-ー０-９]+", options: .regularExpression) != nil
                                || nextLine.hasPrefix("F ") || nextLine.contains("階") {
                                addr += nextLine
                                usedLineIndices.insert(i + 1)
                            }
                        }
                        address = addr
                        break
                    }
                }
            }
            if address != nil { break }
        }

        // Pass 3: 営業時間を抽出
        let hoursPatterns = [
            "(?:営業時間|OPEN|open|営業)[：:\\s]*(.*)",
            "(\\d{1,2}[：:]\\d{2}\\s*[〜~\\-ー]\\s*\\d{1,2}[：:]\\d{2}.*)"
        ]
        for (i, line) in lines.enumerated() {
            if usedLineIndices.contains(i) { continue }
            for pattern in hoursPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                    let captureRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
                    if let range = Range(captureRange, in: line) {
                        hours = String(line[range])
                        usedLineIndices.insert(i)
                        break
                    }
                }
            }
            if hours != nil { break }
        }

        // Pass 4: 価格帯を抽出
        let pricePatterns = [
            "(¥?[\\d,]+\\s*円?\\s*[〜~\\-ー]\\s*¥?[\\d,]+\\s*円?)",
            "([\\d,]+円[〜~\\-ー][\\d,]+円)"
        ]
        for (i, line) in lines.enumerated() {
            if usedLineIndices.contains(i) { continue }
            for pattern in pricePatterns {
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                   let range = Range(match.range(at: 1), in: line) {
                    priceRange = String(line[range])
                    usedLineIndices.insert(i)
                    break
                }
            }
            if priceRange != nil { break }
        }

        // Pass 5: カテゴリを推論
        let categoryKeywords: [(String, [String])] = [
            ("カレー店", ["カレー", "curry", "CURRY"]),
            ("ラーメン店", ["ラーメン", "らーめん", "拉麺"]),
            ("カフェ", ["カフェ", "cafe", "CAFE", "Cafe", "珈琲", "コーヒー"]),
            ("居酒屋", ["居酒屋", "酒場", "酒処"]),
            ("焼肉店", ["焼肉", "焼き肉", "YAKINIKU"]),
            ("寿司店", ["寿司", "鮨", "すし", "SUSHI"]),
            ("蕎麦店", ["蕎麦", "そば"]),
            ("うどん店", ["うどん"]),
            ("パン屋", ["ベーカリー", "パン", "Bakery", "BAKERY"]),
            ("レストラン", ["レストラン", "restaurant", "RESTAURANT", "ダイニング"]),
            ("バー", ["バー", "BAR", "Bar"]),
            ("定食屋", ["定食"]),
        ]
        let fullText = ocrText.lowercased()
        for (cat, keywords) in categoryKeywords {
            if keywords.contains(where: { fullText.contains($0.lowercased()) }) {
                category = cat
                break
            }
        }

        // Pass 6: 残りの行から施設名を推論
        // 「定休日」「席数」「駐車場」等の情報行を除外
        let infoKeywords = ["定休日", "席数", "駐車場", "アクセス", "予約", "FAX", "fax",
                            "税込", "税別", "税抜", "飲み放題", "食べ放題", "コース",
                            "ランチ", "ディナー", "モーニング", "www.", "http", "@",
                            "instagram", "twitter", "facebook"]
        for (i, line) in lines.enumerated() {
            if usedLineIndices.contains(i) { continue }
            let lower = line.lowercased()
            if infoKeywords.contains(where: { lower.contains($0) }) {
                usedLineIndices.insert(i)
                continue
            }
            // 数字だけの行、1文字の行はスキップ
            if line.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "ー" }) { continue }
            if line.count <= 1 { continue }
            nameLines.append(line)
        }

        // 施設名: 最初の数行（最大3行）を結合
        let name: String? = if !nameLines.isEmpty {
            nameLines.prefix(3).joined(separator: " ")
        } else {
            nil
        }

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

    /// ルールベース抽出とLLM抽出の結果をマージ（LLMの結果を優先、空欄はルールベースで補完）
    static func mergeExtractedData(rule: ExtractedPOIData, llm: ExtractedPOIData) -> ExtractedPOIData {
        ExtractedPOIData(
            name: llm.name ?? rule.name,
            address: llm.address ?? rule.address,
            phoneNumber: llm.phoneNumber ?? rule.phoneNumber,
            businessHours: llm.businessHours ?? rule.businessHours,
            category: llm.category ?? rule.category,
            priceRange: llm.priceRange ?? rule.priceRange,
            confidence: max(rule.confidence, llm.confidence)
        )
    }
}

enum OCRError: Error, LocalizedError {
    case invalidImage
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "画像の読み込みに失敗しました"
        case .recognitionFailed:
            return "テキストの認識に失敗しました"
        }
    }
}
