//
//  DetailViewModel.swift
//  iOSPhotoBrowser
//

import Foundation
import Combine
import UIKit

@MainActor
final class DetailViewModel: ObservableObject {
    @Published private(set) var photo: PhotoItem?
    @Published private(set) var allAlbums: [Album] = []
    @Published private(set) var isLoading = false
    @Published var newTagName = ""
    @Published var showingTagEditor = false
    @Published var showingAlbumSelector = false
    @Published var showingDeleteConfirmation = false
    @Published var error: Error?
    @Published var showingError = false

    // OCR関連
    @Published private(set) var isProcessingOCR = false
    @Published private(set) var ocrMessage: String?
    @Published var showingPOIInfoEditor = false
    @Published var editingPOIInfo: POIInfo?
    @Published var isCreatingNewPOI = false

    let photoId: UUID
    private let imageRepository: ImageRepositoryProtocol
    private let tagRepository: TagRepositoryProtocol
    private let albumRepository: AlbumRepositoryProtocol
    private let poiInfoRepository: POIInfoRepositoryProtocol
    private let deleteImageUseCase: DeleteImageUseCase
    private let ocrService: OCRService

    init(
        photoId: UUID,
        imageRepository: ImageRepositoryProtocol,
        tagRepository: TagRepositoryProtocol,
        albumRepository: AlbumRepositoryProtocol,
        poiInfoRepository: POIInfoRepositoryProtocol,
        deleteImageUseCase: DeleteImageUseCase,
        ocrService: OCRService
    ) {
        self.photoId = photoId
        self.imageRepository = imageRepository
        self.tagRepository = tagRepository
        self.albumRepository = albumRepository
        self.poiInfoRepository = poiInfoRepository
        self.deleteImageUseCase = deleteImageUseCase
        self.ocrService = ocrService
    }

    func loadPhoto() async {
        isLoading = true
        defer { isLoading = false }

        do {
            photo = try await imageRepository.fetch(byId: photoId)
        } catch {
            self.error = error
            showingError = true
        }
    }

    func addTag() async {
        guard !newTagName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let tagName = newTagName.trimmingCharacters(in: .whitespaces)
        let tag = Tag(name: tagName)

        do {
            try await tagRepository.addTag(tag, to: photoId)
            await loadPhoto()
            newTagName = ""
        } catch {
            self.error = error
            showingError = true
        }
    }

    func removeTag(_ tag: Tag) async {
        do {
            try await tagRepository.removeTag(tag, from: photoId)
            await loadPhoto()
        } catch {
            self.error = error
            showingError = true
        }
    }

    func deletePhoto() async -> Bool {
        guard let photo = photo else { return false }

        do {
            try await deleteImageUseCase.execute(photo)
            return true
        } catch {
            self.error = error
            showingError = true
            return false
        }
    }

    func loadImage() -> UIImage? {
        guard let photo = photo else { return nil }
        return FileStorageManager.shared.loadImage(fileName: photo.filePath)
    }

    func loadAlbums() async {
        do {
            allAlbums = try await albumRepository.fetchAll()
        } catch {
            self.error = error
            showingError = true
        }
    }

    func addToAlbum(_ album: Album) async {
        do {
            try await albumRepository.addImage(photoId, to: album.id)
            await loadPhoto()
        } catch {
            self.error = error
            showingError = true
        }
    }

    func removeFromAlbum(_ album: Album) async {
        do {
            try await albumRepository.removeImage(photoId, from: album.id)
            await loadPhoto()
        } catch {
            self.error = error
            showingError = true
        }
    }

    func isInAlbum(_ album: Album) -> Bool {
        photo?.albums.contains { $0.id == album.id } ?? false
    }

    // MARK: - OCR & POI Info

    func performOCRAndExtractPOIInfo() async {
        guard let image = loadImage() else {
            ocrMessage = "画像の読み込みに失敗しました"
            return
        }

        isProcessingOCR = true
        ocrMessage = nil
        defer { isProcessingOCR = false }

        do {
            // Step 1: OCR + LLM（利用可能な場合）でスポット情報を抽出
            let (poiData, extractedText, usedLLM) = try await ocrService.extractPOIInfoBestEffort(from: image)

            // Save extracted text
            try await imageRepository.updateExtractedText(
                imageId: photoId,
                text: extractedText,
                processedAt: Date()
            )

            await loadPhoto()

            // Step 2: 抽出データから POIInfo を作成して保存
            if usedLLM && poiData.hasValidData {
                let poiInfo = POIInfo(
                    id: UUID(),
                    name: poiData.name,
                    address: poiData.address,
                    phoneNumber: poiData.phoneNumber,
                    businessHours: poiData.businessHours,
                    category: poiData.category,
                    priceRange: poiData.priceRange,
                    visitStatus: .wantToVisit,
                    createdAt: Date(),
                    updatedAt: Date()
                )
                try await poiInfoRepository.save(poiInfo, for: photoId)
                ocrMessage = nil
                await loadPhoto()
                return
            }

            // 有効なデータが取得できなかった場合
            ocrMessage = "スポット情報を抽出できませんでした。"

        } catch {
            self.error = error
            showingError = true
        }
    }

    func startEditingPOIInfo() {
        guard let poiInfo = photo?.poiInfo else { return }
        editingPOIInfo = poiInfo
        isCreatingNewPOI = false
        showingPOIInfoEditor = true
    }

    /// 抽出テキストを参考にして手動でスポット情報を新規作成
    func startCreatingPOIInfo() {
        let name = photo?.extractedText?
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })

        editingPOIInfo = POIInfo(
            id: UUID(),
            name: name,
            visitStatus: .wantToVisit,
            createdAt: Date(),
            updatedAt: Date()
        )
        isCreatingNewPOI = true
        showingPOIInfoEditor = true
    }

    func savePOIInfo() async {
        guard let poiInfo = editingPOIInfo else { return }

        do {
            if isCreatingNewPOI {
                try await poiInfoRepository.save(poiInfo, for: photoId)
            } else {
                try await poiInfoRepository.update(poiInfo)
            }
            showingPOIInfoEditor = false
            editingPOIInfo = nil
            isCreatingNewPOI = false
            ocrMessage = nil
            await loadPhoto()
        } catch {
            self.error = error
            showingError = true
        }
    }

    func deletePOIInfo() async {
        do {
            try await poiInfoRepository.delete(for: photoId)
            await loadPhoto()
        } catch {
            self.error = error
            showingError = true
        }
    }

    /// 既存の抽出テキストからスポット情報を生成（OCRを再実行しない）
    /// ルールベース + LLMのハイブリッドで抽出し、失敗時は手動作成エディタを開く
    func generatePOIInfoFromExtractedText() async {
        guard let extractedText = photo?.extractedText, !extractedText.isEmpty else {
            ocrMessage = "抽出テキストがありません"
            return
        }

        isProcessingOCR = true
        ocrMessage = nil

        // Step 1: ルールベースで基本抽出（常に実行）
        let ruleResult = OCRService.extractPOIInfoByRules(from: extractedText)

        // Step 2: LLMが利用可能なら追加で抽出してマージ
        var finalResult = ruleResult
        let llmAvailable = await LLMService.shared.isAnyServiceAvailable()
        if llmAvailable {
            let llmResult = await LLMService.shared.extractPOIInfoOrEmpty(from: extractedText)
            finalResult = OCRService.mergeExtractedData(rule: ruleResult, llm: llmResult)
        }

        isProcessingOCR = false

        if finalResult.hasValidData {
            do {
                let poiInfo = POIInfo(
                    id: UUID(),
                    name: finalResult.name,
                    address: finalResult.address,
                    phoneNumber: finalResult.phoneNumber,
                    businessHours: finalResult.businessHours,
                    category: finalResult.category,
                    priceRange: finalResult.priceRange,
                    visitStatus: .wantToVisit,
                    createdAt: Date(),
                    updatedAt: Date()
                )
                try await poiInfoRepository.save(poiInfo, for: photoId)
                ocrMessage = nil
                await loadPhoto()
                return
            } catch {
                self.error = error
                showingError = true
                return
            }
        }

        // ルールベースもLLMも失敗 → 手動作成エディタを開く
        startCreatingPOIInfo()
    }
}
