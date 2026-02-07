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

    // 書籍ドメインのカスタム語彙（OCR精度向上用）
    private let bookDomainWords: [String] = [
        // ISBN関連
        "ISBN", "ISBN-13", "ISBN-10",
        // 書籍用語
        "著者", "著", "編著", "監修", "訳", "翻訳",
        "出版社", "出版", "発行", "発行所", "発売",
        "初版", "第1版", "第2版", "改訂版", "増補版",
        "新書", "文庫", "単行本", "選書", "叢書",
        // 出版社名（主要なもの）
        "岩波書店", "講談社", "新潮社", "角川書店", "集英社",
        "文藝春秋", "中央公論新社", "筑摩書房", "河出書房新社",
        "早川書房", "東京創元社", "光文社", "PHP研究所",
        "ダイヤモンド社", "日経BP", "東洋経済新報社",
        "オライリー", "技術評論社", "翔泳社", "インプレス",
        // 価格・日付
        "定価", "本体", "円", "税別", "税込",
        "年", "月", "日", "発行日", "印刷"
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
            request.customWords = self.bookDomainWords

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func extractISBN(from text: String) -> String? {
        // ISBN-13: 978 or 979 followed by 10 digits (with optional hyphens/spaces)
        // Pattern matches: 978-4-12-345678-9, 9784123456789, 978 4 12 345678 9, etc.
        let patterns = [
            // ISBN-13 with various separators
            "97[89][-\\s]?\\d[-\\s]?\\d{2,5}[-\\s]?\\d{2,7}[-\\s]?\\d",
            // ISBN-13 without separators (13 consecutive digits starting with 978 or 979)
            "97[89]\\d{10}"
        ]

        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                let matched = String(text[range])
                // Remove all non-digit characters to get clean ISBN
                let cleanISBN = matched.filter { $0.isNumber }
                if cleanISBN.count == 13 {
                    return cleanISBN
                }
            }
        }

        // Also try to find ISBN-10 and convert to ISBN-13
        let isbn10Pattern = "\\d[-\\s]?\\d{2,5}[-\\s]?\\d{2,7}[-\\s]?[\\dX]"
        if let range = text.range(of: isbn10Pattern, options: .regularExpression) {
            let matched = String(text[range])
            let cleanISBN = matched.filter { $0.isNumber || $0 == "X" }
            if cleanISBN.count == 10 {
                if let isbn13 = convertISBN10to13(cleanISBN) {
                    return isbn13
                }
            }
        }

        return nil
    }

    private func convertISBN10to13(_ isbn10: String) -> String? {
        guard isbn10.count == 10 else { return nil }

        let prefix = "978"
        let isbn10Body = String(isbn10.prefix(9))
        let isbn13WithoutCheckDigit = prefix + isbn10Body

        // Calculate ISBN-13 check digit
        var sum = 0
        for (index, char) in isbn13WithoutCheckDigit.enumerated() {
            guard let digit = Int(String(char)) else { return nil }
            let multiplier = (index % 2 == 0) ? 1 : 3
            sum += digit * multiplier
        }

        let checkDigit = (10 - (sum % 10)) % 10
        return isbn13WithoutCheckDigit + String(checkDigit)
    }

    // MARK: - Apple Intelligence OCR補正

    /// Apple Intelligence を使用してOCRテキストを補正・正規化
    @available(iOS 26.0, *)
    private func correctOCRTextWithAI(_ rawText: String) async -> String {
        #if canImport(FoundationModels)
        do {
            let session = LanguageModelSession()

            let prompt = """
            以下は本の表紙や奥付からOCRで読み取ったテキストです。
            OCRの誤認識を修正し、書籍情報として整形してください。

            特に注意する点：
            - ISBNの数字の誤り（0とO、1とI/lなど）を修正
            - 著者名、出版社名の誤字を修正
            - 日付形式の正規化（YYYY年MM月DD日）
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

    // MARK: - LLM統合による書籍情報抽出

    /// OCR + LLMで画像から書籍情報を抽出
    /// - Parameter image: 書籍の表紙や奥付の画像
    /// - Returns: 抽出された書籍情報（タイトル、著者、ISBN等）と生のOCRテキスト
    func extractBookInfoWithLLM(from image: UIImage) async throws -> (bookData: ExtractedBookData, rawText: String) {
        // Step 1: OCRでテキスト抽出（補正付き）
        let ocrText = try await recognizeTextWithCorrection(from: image)

        // Step 2: LLMサービスが利用可能か確認
        let llmAvailable = await LLMService.shared.isAnyServiceAvailable()

        if llmAvailable {
            // Step 3a: LLMで構造化データ抽出
            let bookData = await LLMService.shared.extractBookInfoOrEmpty(from: ocrText)

            // LLMの結果にISBNがない場合、正規表現でも試みる
            var finalData = bookData
            if finalData.isbn == nil {
                finalData.isbn = extractISBN(from: ocrText)
            }

            return (finalData, ocrText)
        } else {
            // Step 3b: LLMなしの場合、ISBNのみ正規表現で抽出
            let isbn = extractISBN(from: ocrText)
            let bookData = ExtractedBookData(
                title: nil,
                author: nil,
                publisher: nil,
                isbn: isbn,
                confidence: isbn != nil ? 0.5 : 0.0
            )
            return (bookData, ocrText)
        }
    }

    /// LLMの利用可否に関わらず、最善の方法で書籍情報を抽出
    /// VLM（Vision Language Model）が利用可能な場合は画像から直接抽出を試み、
    /// そうでない場合はOCR + LLMのフローにフォールバック
    func extractBookInfoBestEffort(from image: UIImage) async throws -> (bookData: ExtractedBookData, rawText: String, usedLLM: Bool) {
        print("[OCRService] Starting extractBookInfoBestEffort...")

        // Step 1: VLM（Vision Language Model）で直接抽出を試みる
        let vlmAvailable = await LLMService.shared.isVLMAvailable()
        print("[OCRService] VLM available: \(vlmAvailable)")

        if vlmAvailable {
            print("[OCRService] Trying VLM extraction...")
            let vlmResult = await LLMService.shared.extractBookInfoFromImageOrEmpty(image)

            if vlmResult.hasValidData {
                print("[OCRService] VLM result - Title: \(vlmResult.title ?? "nil"), Author: \(vlmResult.author ?? "nil"), ISBN: \(vlmResult.isbn ?? "nil"), Confidence: \(vlmResult.confidence)")

                // VLMで有効なデータが取得できた場合、OCRはスキップ可能
                // ただし、ISBNが取得できなかった場合はOCRでISBNのみ抽出を試みる
                var finalData = vlmResult
                if finalData.isbn == nil {
                    let ocrText = try await recognizeText(from: image)
                    finalData.isbn = extractISBN(from: ocrText)
                    print("[OCRService] ISBN from OCR regex: \(finalData.isbn ?? "nil")")
                    return (finalData, ocrText, true)
                }

                // OCRテキストは空でも良いが、一応取得しておく（ログ用）
                return (finalData, "[VLM抽出]", true)
            } else {
                print("[OCRService] VLM extraction failed or returned empty data, falling back to OCR+LLM")
            }
        }

        // Step 2: VLMが利用できないか失敗した場合、従来のOCR + LLMフロー
        let ocrText = try await recognizeTextWithCorrection(from: image)
        print("[OCRService] OCR completed. Text length: \(ocrText.count)")
        print("[OCRService] OCR Text: \(ocrText.prefix(200))...")

        let llmAvailable = await LLMService.shared.isAnyServiceAvailable()
        print("[OCRService] LLM available: \(llmAvailable)")

        if llmAvailable {
            print("[OCRService] Calling LLM for extraction...")
            let bookData = await LLMService.shared.extractBookInfoOrEmpty(from: ocrText)
            var finalData = bookData

            print("[OCRService] LLM result - Title: \(bookData.title ?? "nil"), Author: \(bookData.author ?? "nil"), ISBN: \(bookData.isbn ?? "nil"), Confidence: \(bookData.confidence)")

            // ISBNがない場合は正規表現で補完
            if finalData.isbn == nil {
                finalData.isbn = extractISBN(from: ocrText)
                print("[OCRService] ISBN from regex: \(finalData.isbn ?? "nil")")
            }

            return (finalData, ocrText, bookData.hasValidData)
        } else {
            // LLMなしの場合
            print("[OCRService] LLM not available, using regex only")
            let isbn = extractISBN(from: ocrText)
            let bookData = ExtractedBookData(isbn: isbn, confidence: isbn != nil ? 0.3 : 0.0)
            return (bookData, ocrText, false)
        }
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
