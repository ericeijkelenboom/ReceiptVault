import SwiftUI
import PhotosUI

struct ReceiptsView: View {
    @EnvironmentObject private var processingController: ProcessingController
    @EnvironmentObject private var receiptStore: ReceiptStoreCore
    @StateObject private var quotaManager = QuotaManager()
    @StateObject private var storeKitManager = StoreKitManager.shared
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var searchText = ""
    @State private var receiptToDelete: CachedReceipt?
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if receiptStore.receipts.isEmpty && !processingController.isProcessing {
                    emptyState
                } else {
                    receiptList
                }
            }
            .searchable(text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Shop, item, or date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(.systemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(for: CachedReceipt.self) { receipt in
                ReceiptDetailView(receipt: receipt)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.viewfinder")
                            .foregroundStyle(Color.brandPrimary)
                            .font(.system(size: 18, weight: .semibold))
                        Text("Receipt Vault")
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.brandPrimary)
                                .frame(width: 32, height: 32)
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if !quotaManager.canAddReceipt() && !storeKitManager.isPremiumUser {
                    VStack {
                        Text("📦 You've used \(3 - quotaManager.getRemainingReceipts()) of 3 free receipts this month")
                            .font(.headline)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 12) {
                            if !storeKitManager.products.isEmpty {
                                Button("Subscribe $0.99/mo") {
                                    if let product = storeKitManager.products.first(where: { $0.id == "com.receiptvault.subscription.monthly" }) {
                                        Task {
                                            await storeKitManager.purchase(product)
                                        }
                                    }
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Unlock $4.99") {
                                    if let product = storeKitManager.products.first(where: { $0.id == "com.receiptvault.unlimited" }) {
                                        Task {
                                            await storeKitManager.purchase(product)
                                        }
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedItems, maxSelectionCount: 20, matching: .images)
        .sheet(isPresented: $showAddSheet) {
            AddReceiptSheet(
                onCamera: {
                    guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
                    showCamera = true
                },
                onPhotoLibrary: {
                    showPhotoPicker = true
                }
            )
        }
        .sheet(isPresented: $showCamera) {
            CameraPickerView { image in
                processingController.process(image: image)
            }
            .ignoresSafeArea()
        }
        .onChange(of: selectedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            let items = newItems
            selectedItems = []
            Task {
                for item in items {
                    do {
                        if let data = try await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            processingController.process(image: image)
                        }
                    } catch {
                        await MainActor.run {
                            if let vaultError = error as? ReceiptVaultError {
                                processingController.lastError = vaultError
                            } else {
                                processingController.lastError = .parseFailure("An unexpected error occurred: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sync

    private func sync() async {
        // iCloud CloudKit handles sync automatically. This is a manual refresh.
        do {
            _ = try await receiptStore.fetchAllReceipts()
        } catch {
            print("Sync error: \(error.localizedDescription)")
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "doc.text.image")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.brandPrimary)
                Text("No receipts yet.")
                    .font(.headline)
                    .foregroundStyle(Color.brandPrimary)
                Text("Tap + to add a receipt from your photo library.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                if processingController.isProcessing {
                    VStack(spacing: 6) {
                        ProgressView()
                        if processingController.totalInBatch > 1 {
                            Text("Receipt \(processingController.totalInBatch - processingController.pendingCount) of \(processingController.totalInBatch)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        Text(processingController.processingStep ?? "Processing receipt…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top)
                }
                if let error = processingController.lastError {
                    Text(error.errorDescription ?? "Unknown error")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height * 0.7)
        }
        .refreshable { await sync() }
    }

    private var receiptList: some View {
        List {
            if processingController.isProcessing {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 2) {
                            if processingController.totalInBatch > 1 {
                                Text("Receipt \(processingController.totalInBatch - processingController.pendingCount) of \(processingController.totalInBatch)")
                                    .fontWeight(.medium)
                            }
                            Text(processingController.processingStep ?? "Processing receipt…")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }

            if let error = processingController.lastError {
                Section {
                    Text(error.errorDescription ?? "Unknown error")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .listRowBackground(Color.clear)
                }
            }

            let groups = receiptStore.grouped(searchText: searchText)
            if groups.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
            ForEach(groups, id: \.title) { group in
                Section {
                    ForEach(group.receipts) { receipt in
                        NavigationLink(value: receipt) {
                            ReceiptRow(receipt: receipt)
                        }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                                .padding(.vertical, 2)
                        )
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                receiptToDelete = receipt
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text(group.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
            }
        }
        .listStyle(.plain)
        .background(Color(.systemGroupedBackground))
        .scrollContentBackground(.hidden)
        .refreshable { await sync() }
        .alert("Delete Receipt?", isPresented: Binding(
            get: { receiptToDelete != nil },
            set: { if !$0 { receiptToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                guard let receipt = receiptToDelete else { return }
                receiptToDelete = nil
                Task {
                    do {
                        try await receiptStore.deleteReceipt(id: receipt.id)
                    } catch {
                        print("Delete error: \(error.localizedDescription)")
                    }
                }
            }
            Button("Cancel", role: .cancel) { receiptToDelete = nil }
        } message: {
            if let receipt = receiptToDelete {
                Text(receipt.deleteConfirmationMessage)
            }
        }
    }
}

// MARK: - Receipt Row

private struct ReceiptRow: View {
    let receipt: CachedReceipt

    var body: some View {
        HStack(spacing: 12) {
            StoreAvatar(name: receipt.shopName)
            VStack(alignment: .leading, spacing: 3) {
                Text(receipt.shopName)
                    .font(.headline)
                let count = receipt.lineItems.count
                Text(count == 1 ? "1 item" : "\(count) items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let total = receipt.total, let currency = receipt.currency {
                Text(total as NSDecimalNumber as Decimal, format: .currency(code: currency))
                    .font(.headline)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Store Avatar

private struct StoreAvatar: View {
    let name: String

    private static let palette: [Color] = [
        .teal, .cyan, .indigo, .blue, .purple, .mint, .orange, .pink
    ]

    private var color: Color {
        let hash = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Self.palette[abs(hash) % Self.palette.count]
    }

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(color)
            .clipShape(Circle())
    }
}

// MARK: - Camera Picker

private struct CameraPickerView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        init(_ parent: CameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    ReceiptsView()
        .environmentObject(ProcessingController())
        .environmentObject(ReceiptStoreCore())
}
