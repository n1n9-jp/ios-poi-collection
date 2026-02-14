//
//  POIListViewModel.swift
//  iOSPhotoBrowser
//

import Foundation
import Combine

// MARK: - Filter Options

enum VisitStatusFilter: CaseIterable {
    case all
    case wantToVisit
    case visited
    case favorite

    var displayName: String {
        switch self {
        case .all: return "すべて"
        case .wantToVisit: return "行きたい"
        case .visited: return "訪問済み"
        case .favorite: return "お気に入り"
        }
    }

    func matches(_ status: VisitStatus) -> Bool {
        switch self {
        case .all: return true
        case .wantToVisit: return status == .wantToVisit
        case .visited: return status == .visited
        case .favorite: return status == .favorite
        }
    }
}

// MARK: - ViewModel

@MainActor
final class POIListViewModel: ObservableObject {
    @Published private(set) var items: [ExtractedTextItem] = []
    @Published private(set) var groupedItems: [CategoryGroup] = []
    @Published private(set) var isLoading = false
    @Published var error: Error?
    @Published var showingError = false

    // Filter states
    @Published var visitStatusFilter: VisitStatusFilter = .all {
        didSet { applyFilters() }
    }

    // 一括生成関連
    @Published private(set) var isGeneratingBatch = false
    @Published private(set) var batchProgress: (current: Int, total: Int) = (0, 0)
    @Published var batchResultMessage: String?

    private var allItems: [ExtractedTextItem] = []
    private let imageRepository: ImageRepositoryProtocol
    private let poiInfoRepository: POIInfoRepositoryProtocol

    init(imageRepository: ImageRepositoryProtocol, poiInfoRepository: POIInfoRepositoryProtocol) {
        self.imageRepository = imageRepository
        self.poiInfoRepository = poiInfoRepository
    }

    var hasActiveFilters: Bool {
        visitStatusFilter != .all
    }

    func clearFilters() {
        visitStatusFilter = .all
    }

    func loadItems() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let photos = try await imageRepository.fetchAll(sortedBy: .importedAtDescending)
            // Filter photos that have extracted text or POI info
            allItems = photos.compactMap { photo -> ExtractedTextItem? in
                let hasContent = (photo.extractedText != nil && !photo.extractedText!.isEmpty) || photo.hasPOIInfo
                guard hasContent else { return nil }

                return ExtractedTextItem(
                    id: photo.id,
                    thumbnailPath: photo.thumbnailPath,
                    extractedText: photo.extractedText,
                    poiName: photo.poiInfo?.name,
                    poiAddress: photo.poiInfo?.address,
                    poiPhone: photo.poiInfo?.phoneNumber,
                    poiHours: photo.poiInfo?.businessHours,
                    poiCategory: photo.poiInfo?.category,
                    poiPriceRange: photo.poiInfo?.priceRange,
                    visitStatus: photo.poiInfo?.visitStatus ?? .wantToVisit,
                    ocrProcessedAt: photo.ocrProcessedAt
                )
            }

            applyFilters()
        } catch {
            self.error = error
            showingError = true
        }
    }

    private func applyFilters() {
        let filtered = allItems.filter { item in
            visitStatusFilter.matches(item.visitStatus)
        }
        items = filtered
        groupedItems = groupByCategory(filtered)
    }

    private func groupByCategory(_ items: [ExtractedTextItem]) -> [CategoryGroup] {
        var grouped: [String: [ExtractedTextItem]] = [:]
        let uncategorizedKey = "未分類"

        for item in items {
            let category = item.poiCategory ?? uncategorizedKey
            grouped[category, default: []].append(item)
        }

        // Sort categories: defined categories first (alphabetically), then uncategorized at the end
        let sortedKeys = grouped.keys.sorted { key1, key2 in
            if key1 == uncategorizedKey { return false }
            if key2 == uncategorizedKey { return true }
            return key1 < key2
        }

        return sortedKeys.map { CategoryGroup(category: $0, items: grouped[$0]!) }
    }

    /// 未リンクアイテム（抽出テキストあり・POI情報なし）の数
    var unlinkedItemCount: Int {
        allItems.filter { !$0.hasPOIInfo && $0.extractedText != nil && !$0.extractedText!.isEmpty }.count
    }

    // MARK: - POI Info Generation

    /// 個別アイテムの抽出テキストからスポット情報を生成（ルールベース+LLMハイブリッド）
    func generatePOIInfo(for itemId: UUID) async {
        guard let item = allItems.first(where: { $0.id == itemId }),
              let text = item.extractedText, !text.isEmpty else {
            return
        }

        // ルールベースで基本抽出
        let ruleResult = OCRService.extractPOIInfoByRules(from: text)

        // LLMが利用可能ならマージ
        var finalResult = ruleResult
        let llmAvailable = await LLMService.shared.isAnyServiceAvailable()
        if llmAvailable {
            let llmResult = await LLMService.shared.extractPOIInfoOrEmpty(from: text)
            finalResult = OCRService.mergeExtractedData(rule: ruleResult, llm: llmResult)
        }

        guard finalResult.hasValidData else {
            batchResultMessage = "スポット情報を抽出できませんでした"
            return
        }

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
            try await poiInfoRepository.save(poiInfo, for: itemId)
            await loadItems()
        } catch {
            self.error = error
            showingError = true
        }
    }

    /// 未リンクアイテムを一括でスポット情報に変換（ルールベース+LLMハイブリッド）
    func generatePOIInfoForUnlinkedItems() async {
        let unlinkedItems = allItems.filter { !$0.hasPOIInfo && $0.extractedText != nil && !$0.extractedText!.isEmpty }
        guard !unlinkedItems.isEmpty else {
            batchResultMessage = "処理対象のアイテムがありません"
            return
        }

        let llmAvailable = await LLMService.shared.isAnyServiceAvailable()

        isGeneratingBatch = true
        batchProgress = (0, unlinkedItems.count)
        batchResultMessage = nil
        var successCount = 0

        for (index, item) in unlinkedItems.enumerated() {
            batchProgress = (index + 1, unlinkedItems.count)

            guard let text = item.extractedText else { continue }

            // ルールベース抽出
            let ruleResult = OCRService.extractPOIInfoByRules(from: text)

            // LLMが利用可能ならマージ
            var finalResult = ruleResult
            if llmAvailable {
                let llmResult = await LLMService.shared.extractPOIInfoOrEmpty(from: text)
                finalResult = OCRService.mergeExtractedData(rule: ruleResult, llm: llmResult)
            }

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
                    try await poiInfoRepository.save(poiInfo, for: item.id)
                    successCount += 1
                } catch {
                    print("[POIListViewModel] Failed to save POI for \(item.id): \(error)")
                }
            }
        }

        isGeneratingBatch = false
        batchResultMessage = "\(unlinkedItems.count)件中\(successCount)件のスポット情報を生成しました"
        await loadItems()
    }

    // MARK: - Status Update

    func updateStatus(
        for itemId: UUID,
        visitStatus: VisitStatus
    ) async {
        do {
            // Fetch current POI info
            guard var poiInfo = try await poiInfoRepository.fetch(for: itemId) else {
                return
            }

            // Update status
            poiInfo.visitStatus = visitStatus

            // Save to repository
            try await poiInfoRepository.update(poiInfo)

            // Update local items
            if let index = allItems.firstIndex(where: { $0.id == itemId }) {
                let oldItem = allItems[index]
                allItems[index] = ExtractedTextItem(
                    id: oldItem.id,
                    thumbnailPath: oldItem.thumbnailPath,
                    extractedText: oldItem.extractedText,
                    poiName: oldItem.poiName,
                    poiAddress: oldItem.poiAddress,
                    poiPhone: oldItem.poiPhone,
                    poiHours: oldItem.poiHours,
                    poiCategory: oldItem.poiCategory,
                    poiPriceRange: oldItem.poiPriceRange,
                    visitStatus: visitStatus,
                    ocrProcessedAt: oldItem.ocrProcessedAt
                )
                applyFilters()
            }
        } catch {
            self.error = error
            showingError = true
        }
    }
}

struct CategoryGroup: Identifiable {
    let id = UUID()
    let category: String
    let items: [ExtractedTextItem]
}

struct ExtractedTextItem: Identifiable {
    let id: UUID
    let thumbnailPath: String?
    let extractedText: String?
    let poiName: String?
    let poiAddress: String?
    let poiPhone: String?
    let poiHours: String?
    let poiCategory: String?
    let poiPriceRange: String?
    let visitStatus: VisitStatus
    let ocrProcessedAt: Date?

    var hasPOIInfo: Bool {
        poiName != nil || poiAddress != nil
    }

    var displayTitle: String {
        if let name = poiName {
            return name
        } else if let text = extractedText {
            // Return first line or first 50 characters
            let firstLine = text.components(separatedBy: .newlines).first ?? text
            if firstLine.count > 50 {
                return String(firstLine.prefix(50)) + "..."
            }
            return firstLine
        }
        return "（テキストなし）"
    }
}
