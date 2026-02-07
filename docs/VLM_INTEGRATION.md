# VLM (Vision Language Model) 統合ドキュメント

## 概要

本の表紙画像から直接書籍情報（タイトル、著者、ISBN等）を抽出するVision Language Model (VLM) の統合。

**ステータス: ✅ 統合完了（2024-02-06）**

## 現在の状況

### 試行した方法

#### 1. LocalLLMClient (Swift Package Manager)
- **リポジトリ**: https://github.com/tattn/LocalLLMClient
- **結果**: 失敗
- **原因**: Xcode SPMがgitサブモジュール（llama.cpp）を解決できない
- **エラー**: `Couldn't update repository submodules`

#### 2. StanfordBDHG/llama.cpp (Swift Package Manager)
- **リポジトリ**: https://github.com/StanfordBDHG/llama.cpp
- **結果**: ビルド成功（テキストLLM用）
- **制限**: VLM（マルチモーダル）機能は含まれていない

### 現在の実装状態 ✅ 統合完了

- `VLMService.swift` - MTMDWrapperを使用した実装完了
- `VLMServiceProtocol` - 定義済み
- `LLMService` - VLM統合済み（VLM優先、OCR+LLMにフォールバック）
- `OCRService` - VLM対応済み
- `LLMSettingsView` - VLMセクション有効化（モデルダウンロード案内付き）
- `llama.xcframework` - MiniCPM-o-demo-iOSからコピー済み
- `MTMDWrapper` - Swift-Cブリッジコピー済み

## 解決策: MiniCPM-o-demo-iOS からの直接統合

### アプローチ

MiniCPM-o-demo-iOS プロジェクトから以下をコピーして統合:

1. **llama.xcframework** (VLM対応版)
   - 場所: `~/Desktop/MiniCPM-o-demo-iOS/MiniCPM-V-demo/thirdparty/llama.xcframework`
   - サイズ: 約50MB
   - 対応プラットフォーム: iOS, iOS Simulator, macOS, tvOS, visionOS

2. **MTMDWrapper** (Swift-C ブリッジ)
   - 場所: `~/Desktop/MiniCPM-o-demo-iOS/MiniCPM-V-demo/MTMDWrapper/`
   - 機能: llama.cpp の C API を Swift から呼び出すラッパー

### 統合手順 ✅ 完了

1. ✅ `thirdparty/` フォルダを作成し、`llama.xcframework` をコピー
2. ✅ Xcode プロジェクトに xcframework を追加
3. ✅ `MTMDWrapper` コードをコピー・修正
4. ✅ `VLMService` を実際の実装に更新
5. ✅ 設定画面の「準備中」表示を解除

### 必要なモデルファイル

VLMを使用するには以下のモデルファイルが必要（ユーザーがダウンロード）:

- **言語モデル**: `ggml-model-Q4_0.gguf` (~2.08GB)
- **ビジョンエンコーダ**: `mmproj-model-f16.gguf` (~960MB)
- **ダウンロード元**: https://huggingface.co/openbmb/MiniCPM-V-4-gguf

### メリット

- Swift Package Manager の問題を回避
- MiniCPM-o-demo-iOS で動作実績あり
- 完全にオンデバイスで動作

### デメリット

- アプリサイズ増加（xcframework: ~50MB）
- モデルファイルは別途ダウンロード必要（~3GB）
- フレームワークの更新は手動

## 参考リンク

- [MiniCPM-o-demo-iOS](https://github.com/tc-mb/MiniCPM-o-demo-iOS)
- [MiniCPM-V-4-gguf (HuggingFace)](https://huggingface.co/openbmb/MiniCPM-V-4-gguf)
- [LocalLLMClient](https://github.com/tattn/LocalLLMClient)

## 使用方法

### モデルファイルのインストール

1. [HuggingFace](https://huggingface.co/openbmb/MiniCPM-V-4-gguf) からモデルをダウンロード:
   - `ggml-model-Q4_0.gguf` (~2.08GB)
   - `mmproj-model-f16-iOS.gguf` (~960MB)

2. ファイルをiOSデバイスの Documents/VLMModels/ ディレクトリに配置

3. アプリの「設定 > AI処理」でモデルの認識を確認

### 動作確認

VLMが有効な場合、詳細画面の「書誌情報を抽出」ボタンをタップすると:
1. まずVLMで画像から直接書籍情報を抽出
2. VLMが失敗した場合、OCR+テキストLLMにフォールバック

## 完了した作業の詳細

### 1. llama.xcframework のコピー

```
コピー元: ~/Desktop/MiniCPM-o-demo-iOS/MiniCPM-V-demo/thirdparty/llama.xcframework
コピー先: iOSPhotoBrowser/iOSPhotoBrowser/thirdparty/llama.xcframework
```

含まれるプラットフォーム:
- ios-arm64
- ios-arm64_x86_64-simulator
- macos-arm64_x86_64
- tvos-arm64
- tvos-arm64_x86_64-simulator
- xros-arm64
- xros-arm64_x86_64-simulator

### 2. MTMDWrapper のコピー・統合

```
コピー先: iOSPhotoBrowser/iOSPhotoBrowser/Services/VLM/MTMDWrapper/
```

ファイル構成:
- `MTMDWrapper.swift` - メインのラッパークラス（@MainActor）
- `MTMDParams.swift` - 初期化パラメータ構造体
- `MTMDToken.swift` - トークン・生成状態の定義
- `MTMDError.swift` - エラー型の定義

### 3. Xcodeプロジェクトの変更

`project.pbxproj` への変更:
- StanfordBDHG/llama.cpp Swift Package を削除
- llama.xcframework をFrameworksグループに追加
- "Embed Frameworks" ビルドフェーズを追加
- フレームワークをリンク・埋め込み設定

### 4. VLMService の実装

`iOSPhotoBrowser/Services/LLM/VLMService.swift`:
- MTMDWrapperを使用した画像からの書籍情報抽出
- 画像を一時ファイルに保存してMTMDWrapperに渡す
- JSON形式のレスポンスをパースしてExtractedBookDataを返す
- VLMModelManagerでモデルファイルの状態を管理

### 5. LlamaService の更新

新しいllama.cpp APIへの対応:
- `llama_batch_add` / `llama_batch_clear` → 直接構造体操作に変更
- `llama_n_vocab` → `llama_vocab_n_tokens` に変更
- `llama_token_is_eog` → `llama_vocab_is_eog` に変更
- `llama_tokenize` → vocab引数を使用するように変更
- `llama_token_to_piece` → 6引数のシグネチャに対応

### 6. 設定画面の更新

`iOSPhotoBrowser/Presentation/Settings/LLMSettingsView.swift`:
- VLMモデルの状態表示（ダウンロード済み/未ダウンロード）
- HuggingFaceへのダウンロードリンク
- VLMモデル削除機能
- LLMInfoViewのVLM説明を更新

## ファイル構成

```
iOSPhotoBrowser/
├── iOSPhotoBrowser/
│   ├── thirdparty/
│   │   └── llama.xcframework/          # VLM対応フレームワーク
│   └── Services/
│       ├── LLM/
│       │   ├── LLMService.swift        # LLMファサード
│       │   ├── LLMServiceProtocol.swift
│       │   ├── LlamaService.swift      # テキストLLM
│       │   ├── VLMService.swift        # 画像→書籍情報抽出
│       │   ├── LLMModelManager.swift
│       │   └── AppleFoundationModelsService.swift
│       └── VLM/
│           └── MTMDWrapper/
│               ├── MTMDWrapper.swift
│               ├── MTMDParams.swift
│               ├── MTMDToken.swift
│               └── MTMDError.swift
└── docs/
    └── VLM_INTEGRATION.md              # このドキュメント
```

## 更新履歴

- 2024-02-06: LocalLLMClient 統合試行 → 失敗
- 2024-02-06: 直接統合アプローチに切り替え決定
- 2024-02-06: VLM統合完了 ✅
  - llama.xcframework をMiniCPM-o-demo-iOSからコピー
  - MTMDWrapper をコピー・統合
  - VLMService を実装
  - LLMSettingsView でVLMセクション有効化
  - LlamaService を新しいllama.cpp APIに対応
  - ビルド成功確認済み
