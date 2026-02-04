//
//  ImportView.swift
//  iOSPhotoBrowser
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ImportView: View {
    @StateObject private var viewModel: ImportViewModel
    @State private var selectedItems: [PhotosPickerItem] = []

    init() {
        _viewModel = StateObject(wrappedValue: DependencyContainer.shared.makeImportViewModel())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if viewModel.isImporting {
                    importingView
                } else {
                    importOptionsView
                }

                if viewModel.importedCount > 0 || viewModel.failedCount > 0 {
                    resultView
                }
            }
            .padding()
            .navigationTitle("取り込み")
            .fileImporter(
                isPresented: $viewModel.showingFilePicker,
                allowedContentTypes: FileImportService.supportedTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task {
                        await viewModel.importFromFiles(urls: urls)
                    }
                case .failure(let error):
                    viewModel.error = error
                    viewModel.showingError = true
                }
            }
            .alert("エラー", isPresented: $viewModel.showingError) {
                Button("OK") {}
            } message: {
                Text(viewModel.error?.localizedDescription ?? "不明なエラー")
            }
            .onChange(of: selectedItems) { _, newItems in
                Task {
                    let results = newItems.compactMap { item -> PHPickerResult? in
                        // Convert PhotosPickerItem to PHPickerResult workaround
                        nil
                    }
                    // Use the new PhotosPicker API instead
                    await importPhotosPickerItems(newItems)
                }
            }
        }
    }

    private var importOptionsView: some View {
        VStack(spacing: 20) {
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 100,
                matching: .images
            ) {
                HStack {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title2)
                    Text("写真から選択")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            Button {
                viewModel.showingFilePicker = true
            } label: {
                HStack {
                    Image(systemName: "folder")
                        .font(.title2)
                    Text("ファイルから選択")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            Spacer()

            Text("写真やファイルアプリから画像を取り込めます")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var importingView: some View {
        VStack(spacing: 16) {
            ProgressView(value: viewModel.importProgress) {
                Text("取り込み中...")
            }
            .progressViewStyle(.linear)

            Text("\(Int(viewModel.importProgress * 100))%")
                .font(.headline)
        }
        .padding()
    }

    private var resultView: some View {
        VStack(spacing: 8) {
            if viewModel.importedCount > 0 {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("\(viewModel.importedCount)件の画像を取り込みました")
                }
            }

            if viewModel.failedCount > 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("\(viewModel.failedCount)件の取り込みに失敗しました")
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    private func importPhotosPickerItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        var importedData: [(Data, String)] = []

        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let fileName = "image_\(UUID().uuidString).jpg"
                importedData.append((data, fileName))
            }
        }

        // Import all items
        for (data, fileName) in importedData {
            do {
                _ = try await DependencyContainer.shared.importImageUseCase.execute(
                    imageData: data,
                    originalFileName: fileName
                )
            } catch {
                print("Import error: \(error)")
            }
        }

        selectedItems = []
    }
}
