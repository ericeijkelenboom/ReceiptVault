// ReceiptVault/Views/AddReceiptSheet.swift
import SwiftUI

struct AddReceiptSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCamera: () -> Void
    let onPhotoLibrary: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Receipt")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Options
            VStack(spacing: 12) {
                AddReceiptOption(
                    icon: "camera",
                    title: "Take Photo",
                    subtitle: "Use camera to scan receipt"
                ) {
                    // Dismiss first, then present next sheet after a brief delay
                    // so SwiftUI has time to tear down this sheet before presenting the next.
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onCamera()
                    }
                }

                AddReceiptOption(
                    icon: "photo.on.rectangle",
                    title: "Photo Library",
                    subtitle: "Choose from existing photos"
                ) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onPhotoLibrary()
                    }
                }
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 32)
        }
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
    }
}

private struct AddReceiptOption: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.brandPrimary.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(Color.brandPrimary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AddReceiptSheet(onCamera: {}, onPhotoLibrary: {})
}
