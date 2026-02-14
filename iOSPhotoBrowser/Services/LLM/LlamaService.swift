//
//  LlamaService.swift
//  iOSPhotoBrowser
//
//  llama.cpp Swift統合
//
//  セットアップ手順:
//  1. Xcode > File > Add Package Dependencies...
//  2. URL: https://github.com/ggerganov/llama.cpp
//  3. Branch: master
//  4. Add "llama" target to your app
//

import Foundation

// llama.cpp のSwift binding
// パッケージが追加されたら ENABLE_LLAMA を定義
// Build Settings > Swift Compiler - Custom Flags > Other Swift Flags に -DENABLE_LLAMA を追加
#if ENABLE_LLAMA
import llama
#endif

/// llama.cpp を使用したローカルLLMサービス
/// Phi-3 Mini などの小型LLMをオンデバイスで実行
actor LlamaService: LLMServiceProtocol {
    nonisolated let serviceName = "Local LLM (Gemma 2B)"

    private var isModelLoaded = false

    #if ENABLE_LLAMA
    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    #endif

    init() {}

    nonisolated var isAvailable: Bool {
        get async {
            await MainActor.run {
                LLMModelManager.shared.isModelDownloaded
            }
        }
    }

    /// モデルをメモリに読み込む
    func loadModel() async throws {
        let isDownloaded = await MainActor.run {
            LLMModelManager.shared.isModelDownloaded
        }
        guard isDownloaded else {
            throw LLMError.modelNotLoaded
        }

        guard !isModelLoaded else { return }

        let modelPath = await MainActor.run {
            LLMModelManager.shared.modelPath
        }
        guard let path = modelPath else {
            throw LLMError.modelNotLoaded
        }

        #if ENABLE_LLAMA
        // llama_backend を初期化
        llama_backend_init()

        // モデルパラメータ
        var model_params = llama_model_default_params()
        model_params.n_gpu_layers = 0 // iOSではCPUのみ

        // モデルを読み込み
        model = llama_model_load_from_file(path, model_params)
        guard model != nil else {
            print("[\(serviceName)] Failed to load model from \(path)")
            throw LLMError.modelNotLoaded
        }

        // コンテキストパラメータ
        var ctx_params = llama_context_default_params()
        ctx_params.n_ctx = 2048
        ctx_params.n_threads = 4
        ctx_params.n_threads_batch = 4

        // コンテキストを作成
        ctx = llama_init_from_model(model, ctx_params)
        guard ctx != nil else {
            llama_model_free(model)
            model = nil
            print("[\(serviceName)] Failed to create context")
            throw LLMError.modelNotLoaded
        }

        isModelLoaded = true
        print("[\(serviceName)] Model loaded successfully from \(path)")
        #else
        // llama パッケージが未インストールの場合
        print("[\(serviceName)] llama package not enabled. Add -DENABLE_LLAMA to Swift flags.")
        throw LLMError.notAvailable
        #endif
    }

    /// モデルをメモリから解放
    func unloadModel() {
        #if ENABLE_LLAMA
        if ctx != nil {
            llama_free(ctx)
            ctx = nil
        }
        if model != nil {
            llama_model_free(model)
            model = nil
        }
        llama_backend_free()
        #endif
        isModelLoaded = false
        print("[\(serviceName)] Model unloaded")
    }

    func extractPOIInfo(from ocrText: String) async throws -> ExtractedPOIData {
        if !isModelLoaded {
            try await loadModel()
        }

        #if ENABLE_LLAMA
        guard let ctx = ctx, let model = model else {
            throw LLMError.modelNotLoaded
        }

        // Gemma 2B Instruct用のプロンプト形式
        let userPrompt = """
        以下はOCRで読み取ったレストランや店舗の看板テキストです。スポット情報を推論してJSON形式で出力してください。
        重要: OCRは行ごとにテキストを分割します。店名+支店名、住所の断片など、複数行にわたる情報は結合してください。
        例: 「アパ社長カレー」「横浜ベイタワー店」→ name: "アパ社長カレー 横浜ベイタワー店"

        OCRテキスト:
        \(ocrText)

        以下のJSON形式のみを出力してください（他の説明は不要）:
        {"name": "施設名（店名+支店名を結合）", "address": "住所", "phone": "電話番号", "hours": "営業時間", "category": "カテゴリ", "priceRange": "価格帯"}
        見つからない項目はnullにしてください。
        """

        // Gemma Instruct形式でラップ
        let prompt = "<start_of_turn>user\n\(userPrompt)<end_of_turn>\n<start_of_turn>model\n"

        print("[\(serviceName)] Prompt: \(prompt.prefix(200))...")

        // 推論を実行
        let response = try await generateText(prompt: prompt, ctx: ctx, model: model)
        print("[\(serviceName)] Generated response: \(response.prefix(300))...")
        return parseJSONResponse(response)
        #else
        print("[\(serviceName)] llama package not enabled")
        throw LLMError.notAvailable
        #endif
    }

    #if ENABLE_LLAMA
    private func generateText(prompt: String, ctx: OpaquePointer, model: OpaquePointer) async throws -> String {
        // vocabを取得
        let vocab = llama_model_get_vocab(model)

        // トークン化
        let n_ctx = llama_n_ctx(ctx)
        var tokens = [llama_token](repeating: 0, count: Int(n_ctx))
        let n_tokens = llama_tokenize(vocab, prompt, Int32(prompt.utf8.count), &tokens, Int32(n_ctx), true, false)

        guard n_tokens > 0 else {
            throw LLMError.extractionFailed("トークン化に失敗しました")
        }

        // バッチを作成
        var batch = llama_batch_init(512, 0, 1)
        defer { llama_batch_free(batch) }

        // プロンプトトークンをバッチに追加（新API: 直接構造体を操作）
        batch.n_tokens = n_tokens
        for i in 0..<Int(n_tokens) {
            batch.token[i] = tokens[i]
            batch.pos[i] = Int32(i)
            batch.n_seq_id[i] = 1
            batch.seq_id[i]![0] = 0
            batch.logits[i] = 0
        }
        batch.logits[Int(batch.n_tokens) - 1] = 1

        // 初期評価
        if llama_decode(ctx, batch) != 0 {
            throw LLMError.extractionFailed("デコードに失敗しました")
        }

        // 生成ループ
        var result = ""
        let maxTokens = 512
        var n_cur = Int(n_tokens)

        for _ in 0..<maxTokens {
            let n_vocab = llama_vocab_n_tokens(vocab)
            let logits = llama_get_logits_ith(ctx, Int32(batch.n_tokens) - 1)

            // グリーディサンプリング
            var max_logit: Float = -Float.infinity
            var max_id: llama_token = 0
            for i in 0..<Int(n_vocab) {
                if logits![i] > max_logit {
                    max_logit = logits![i]
                    max_id = llama_token(i)
                }
            }

            // EOSチェック
            if llama_vocab_is_eog(vocab, max_id) {
                break
            }

            // トークンを文字列に変換（新API: 6引数）
            var buf = [CChar](repeating: 0, count: 256)
            let len = llama_token_to_piece(vocab, max_id, &buf, Int32(buf.count), 0, false)
            if len > 0 {
                let piece = String(cString: buf)
                result += piece

                // } が出たら終了（JSON完了）
                if piece.contains("}") && result.contains("{") {
                    // JSONの終わりを探す
                    if let lastBrace = result.lastIndex(of: "}") {
                        result = String(result[...lastBrace])
                        break
                    }
                }
            }

            // 次のトークンを準備（新API: 直接構造体をリセット）
            batch.n_tokens = 1
            batch.token[0] = max_id
            batch.pos[0] = Int32(n_cur)
            batch.n_seq_id[0] = 1
            batch.seq_id[0]![0] = 0
            batch.logits[0] = 1
            n_cur += 1

            if llama_decode(ctx, batch) != 0 {
                break
            }
        }

        return result
    }
    #endif

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
            print("[\(serviceName)] Failed to parse JSON: \(jsonString.prefix(100))")
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
        if name != nil && !name!.isEmpty { fields += 1 }
        if address != nil && !address!.isEmpty { fields += 1 }
        if phone != nil && !phone!.isEmpty { fields += 1 }
        if hours != nil && !hours!.isEmpty { fields += 1 }
        if category != nil && !category!.isEmpty { fields += 1 }
        if priceRange != nil && !priceRange!.isEmpty { fields += 1 }
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

        // 施設名パターン
        let namePatterns = ["施設名[：:]\\s*(.+)", "店名[：:]\\s*(.+)", "\"name\"\\s*:\\s*\"([^\"]+)\""]
        for pattern in namePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                name = String(text[range]).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // 住所パターン
        let addressPatterns = ["住所[：:]\\s*(.+)", "\"address\"\\s*:\\s*\"([^\"]+)\""]
        for pattern in addressPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                address = String(text[range]).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // 電話番号パターン
        let phonePatterns = ["電話[：:]\\s*(.+)", "TEL[：:]\\s*(.+)", "\"phone\"\\s*:\\s*\"([^\"]+)\""]
        for pattern in phonePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                phone = String(text[range]).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        return ExtractedPOIData(
            name: name,
            address: address,
            phoneNumber: phone,
            confidence: 0.3
        )
    }
}

// MARK: - Model Information

extension LlamaService {
    /// 使用するモデル情報
    struct ModelInfo {
        static let name = "Gemma 2B Instruct"
        static let fileName = "gemma-2b-it-q4_k_m.gguf"
        static let fileSize: Int64 = 1_500_000_000  // 約1.5GB
        // Google Gemma 2B - 軽量で日本語対応
        static let downloadURL = "https://huggingface.co/lmstudio-ai/gemma-2b-it-GGUF/resolve/main/gemma-2b-it-q4_k_m.gguf"

        /// 表示用のファイルサイズ
        static var displayFileSize: String {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useGB, .useMB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: fileSize)
        }
    }
}
