import SwiftUI
import PhotosUI

struct ReceiptsView: View {
    @EnvironmentObject private var processingController: ProcessingController
    @EnvironmentObject private var receiptStore: ReceiptStore
    @EnvironmentObject private var authManager: AuthManager
    @State private var selectedItem: PhotosPickerItem?
    @State private var isSyncing = false
    @State private var syncError: String?

    var body: some View {
        NavigationStack {
            Group {
                if receiptStore.receipts.isEmpty {
                    emptyState
                } else {
                    receiptList
                }
            }
            .navigationTitle("Receipts")
            .toolbarBackground(Color.brandPrimary.opacity(0.08), for: .navigationBar)
            .navigationDestination(for: CachedReceipt.self) { receipt in
                ReceiptDetailView(receipt: receipt)
                    .environmentObject(authManager)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Image(systemName: "plus")
                            .foregroundStyle(Color.brandPrimary)
                    }
                    .disabled(processingController.isProcessing)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await sync() }
                    } label: {
                        Image(systemName: isSyncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                            .foregroundStyle(Color.brandPrimary)
                    }
                    .disabled(isSyncing)
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
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                defer { Task { @MainActor in selectedItem = nil } }
                do {
                    if let data = try await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await processingController.process(image: image)
                    }
                } catch {
                    await MainActor.run { processingController.lastErrorMessage = error.localizedDescription }
                }
            }
        }
    }

    // MARK: - Sync

    private func sync() async {
        guard authManager.isSignedIn else { return }
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }
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
                    ProgressView("Processing receipt…")
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
                        Text("Processing receipt…")
                            .foregroundStyle(.secondary)
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
            ForEach(receiptStore.groupedByMonth, id: \.title) { group in
                Section {
                    ForEach(group.receipts) { receipt in
                        NavigationLink(value: receipt) {
                            ReceiptRow(receipt: receipt)
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

#Preview {
    ReceiptsView()
        .environmentObject(ProcessingController())
        .environmentObject(ReceiptStore())
        .environmentObject(AuthManager())
}
