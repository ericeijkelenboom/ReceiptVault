import SwiftUI
import PhotosUI

struct ReceiptsView: View {
    @EnvironmentObject private var processingController: ProcessingController
    @EnvironmentObject private var receiptStore: ReceiptStore
    @EnvironmentObject private var authManager: AuthManager
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showSettings = false
    @State private var syncError: String?
    @State private var searchText = ""

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
            .toolbarBackground(Color.brandPrimary.opacity(0.08), for: .navigationBar)
            .navigationDestination(for: CachedReceipt.self) { receipt in
                ReceiptDetailView(receipt: receipt)
                    .environmentObject(authManager)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Receipts")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Color.brandPrimary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                        }
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                        Button {
                            showPhotoPicker = true
                        } label: {
                            Label("Choose from Library", systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Color.brandPrimary)
                    }
                }
            }
            // Auto-sync when already signed in on first appear (cache empty after reinstall)
            .task {
                if authManager.isSignedIn && receiptStore.receipts.isEmpty {
                    await sync()
                }
            }
            // Auto-sync when auth restore completes after view has already appeared
            .onChange(of: authManager.isSignedIn) { _, isSignedIn in
                if isSignedIn && receiptStore.receipts.isEmpty {
                    Task { await sync() }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(authManager)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedItems, maxSelectionCount: 20, matching: .images)
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
                        await MainActor.run { processingController.lastErrorMessage = error.localizedDescription }
                    }
                }
            }
        }
    }

    // MARK: - Sync

    private func sync() async {
        guard authManager.isSignedIn else { return }
        syncError = nil
        do {
            try await receiptStore.syncFromDrive(authManager: authManager)
        } catch {
            syncError = error.localizedDescription
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
                if let message = processingController.lastErrorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                if let error = syncError {
                    Text(error)
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
                }
            }
            if let message = processingController.lastErrorMessage {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            if let error = syncError {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
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
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let receipt = group.receipts[index]
                            Task {
                                do {
                                    try await receiptStore.delete(receipt, authManager: authManager)
                                } catch {
                                    await MainActor.run { syncError = error.localizedDescription }
                                }
                            }
                        }
                    }
                } header: {
                    Text(group.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .textCase(nil)
                }
            }
        }
        .refreshable { await sync() }
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
                Text(receipt.date, format: .dateTime.day().month(.wide))
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
        .padding(.vertical, 2)
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
        .environmentObject(ReceiptStore())
        .environmentObject(AuthManager())
}
