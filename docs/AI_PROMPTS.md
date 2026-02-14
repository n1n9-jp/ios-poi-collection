# AI プロンプト一覧

本プロジェクトでは、店舗・施設情報（POI）の抽出を目的として、複数のAIモデルに以下のプロンプトを送っています。

## 1. Claude API（クラウド） — `CloudLLMService.swift`

**システムプロンプト:**
- 「日本のレストラン・店舗・施設の情報を正確に抽出するスペシャリスト」として振る舞うよう指示
- 抽出ルール: name（施設名）、address（住所）、phone（電話番号）、hours（営業時間）、category（カテゴリ）、priceRange（価格帯）
- 看板やロゴから正式店名を抽出し、ブランド名＋支店名の結合を指示
- JSON形式のみの出力を要求

**ユーザープロンプト:**
- OCRテキスト用: `「以下はOCRで読み取ったテキストです。スポット情報を抽出してJSONで出力してください。」`
- 画像用: `「この画像に写っている店舗・施設のスポット情報をJSONで抽出してください。」`

## 2. Llama.cpp（ローカルモデル Gemma 2B） — `LlamaService.swift`

**ユーザープロンプト:**
- OCRテキストからスポット情報を推論してJSON出力するよう指示
- 複数行にわたる情報の結合を強調（例: 店名＋支店名）
- `<start_of_turn>user ... <end_of_turn>` のGemma Instructフォーマットでラップ

## 3. MiniCPM-V（VLM: Vision Language Model） — `VLMService.swift`

**画像解析プロンプト:**
- 画像から直接スポット情報を抽出するよう指示
- 施設名のブランド名・支店名結合、住所結合、日本語出力を要求
- テキストの断片からカテゴリを推論するよう指示

## 4. Apple Intelligence（OCR補正） — `OCRService.swift`

**OCR修正プロンプト:**
- OCR誤認識の修正に特化（`0↔O`、`1↔I/l` など）
- 店名・住所の誤字修正、営業時間・価格表記の正規化
- 修正後テキストのみ出力するよう指示

## 5. 共通プロンプト（Apple Intelligence等で利用） — `LLMServiceProtocol.swift`

**`makePOIExtractionPrompt()`:**
- 各LLMサービスで共通利用されるPOI抽出用プロンプト
- OCRの行分割された情報の結合を重点的に指示
- OCR誤認識の推測・修正を考慮するよう指示

## サービス対応表

| サービス | モデル | 入力 | 用途 |
|---|---|---|---|
| CloudLLMService | Claude API | OCRテキスト / 画像 | POI抽出（最も詳細なプロンプト） |
| LlamaService | Gemma 2B (ローカル) | OCRテキスト | POI抽出 |
| VLMService | MiniCPM-V (ローカル) | 画像 | 画像から直接POI抽出 |
| OCRService | Apple Intelligence | OCRテキスト | OCR誤認識の補正 |
| LLMServiceProtocol | 共通 | OCRテキスト | 汎用POI抽出プロンプト |

## 設計思想

全プロンプトに共通する設計思想は、**看板・メニュー等の写真/OCRテキストから店舗情報をJSON形式で構造化抽出する**ことです。特に以下の点が重視されています:

- **複数行に分割された情報の結合**（ブランド名＋支店名、住所の断片など）
- **OCR誤認識の修正**（数字と文字の混同など）
- **統一されたJSON出力形式**（全サービスで同じフィールド構造）
