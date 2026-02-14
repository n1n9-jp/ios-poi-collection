# AI プロンプト一覧

本プロジェクトでは、店舗・施設情報（POI）の抽出を目的として、複数のAIモデルを利用しています。

## プロンプト設計方針

全モデルで **同一スキーマ・同一出力制約** の統一プロンプトを使用しています（`POIPrompts` enum in `LLMServiceProtocol.swift`）。

### 基本ルール
1. **事実のみ抽出。推測はしない。**
2. **不明な項目は null**
3. **出力は valid JSON のみ。説明文は禁止。**
4. 複数行にわたる情報は結合（ブランド名＋支店名、住所の断片など）
5. OCR誤認識（0↔O、1↔I/l）は修正

### 出力スキーマ（全モデル共通）
```json
{"name": "施設名", "address": "住所", "phone": "電話番号", "hours": "営業時間", "category": "カテゴリ", "priceRange": "価格帯"}
```

## 統一プロンプト構成

| プロンプト | 用途 | 定義場所 |
|---|---|---|
| `POIPrompts.system` | システムプロンプト（詳細な抽出ルール） | `LLMServiceProtocol.swift` |
| `POIPrompts.userPromptForOCR()` | OCRテキストからの抽出 | `LLMServiceProtocol.swift` |
| `POIPrompts.userPromptForImage` | 画像からの直接抽出 | `LLMServiceProtocol.swift` |
| `POIPrompts.parseJSONResponse()` | JSON応答の共通パース処理 | `LLMServiceProtocol.swift` |

## サービス対応表

| サービス | モデル | 入力 | 使用プロンプト |
|---|---|---|---|
| CloudLLMService | Claude API | OCRテキスト / 画像 | system + userPromptForOCR / userPromptForImage |
| AppleFoundationModelsService | Apple Intelligence | OCRテキスト | userPromptForOCR |
| LlamaService | Gemma 2B (ローカル) | OCRテキスト | userPromptForOCR（Gemma Instruct形式でラップ） |
| VLMService | MiniCPM-V (ローカル) | 画像 | userPromptForImage |
| OCRService | Apple Intelligence | OCRテキスト | OCR補正専用プロンプト（別途定義） |

## OCR補正プロンプト（OCRService.swift）

OCR誤認識の修正に特化した専用プロンプト:
- 電話番号の数字の誤り修正
- 店名・住所の誤字修正
- 営業時間・価格表記の正規化
