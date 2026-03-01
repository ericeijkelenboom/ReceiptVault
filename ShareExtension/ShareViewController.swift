import UIKit
import UniformTypeIdentifiers
import Social

final class ShareViewController: UIViewController {

    private let appGroupIdentifier = "group.com.ericeijkelenboom.receiptvault"
    private let pendingJobsKey = "pendingReceiptJobs"

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBackground
        showSavingUI()
        processSharedItems()
    }

    // MARK: - UI

    private func showSavingUI() {
        let label = UILabel()
        label.text = "Saving receipt…"
        label.font = .preferredFont(forTextStyle: .headline)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func showConfirmationUI() {
        view.subviews.forEach { $0.removeFromSuperview() }

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        let imageView = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        imageView.tintColor = .systemGreen
        imageView.preferredSymbolConfiguration = .init(pointSize: 48)

        let label = UILabel()
        label.text = "Receipt queued"
        label.font = .preferredFont(forTextStyle: .headline)
        label.textAlignment = .center

        stack.addArrangedSubview(imageView)
        stack.addArrangedSubview(label)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - Processing

    private func processSharedItems() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments, !attachments.isEmpty else {
            completeRequest()
            return
        }

        let group = DispatchGroup()
        var savedFilenames: [String] = []

        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, _ in
                    defer { group.leave() }
                    guard let self else { return }
                    if let url = item as? URL, let data = try? Data(contentsOf: url) {
                        if let filename = self.saveData(data, extension: "jpg") {
                            savedFilenames.append(filename)
                        }
                    } else if let image = item as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                        if let filename = self.saveData(data, extension: "jpg") {
                            savedFilenames.append(filename)
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { [weak self] item, _ in
                    defer { group.leave() }
                    guard let self else { return }
                    if let url = item as? URL, let data = try? Data(contentsOf: url) {
                        if let filename = self.saveData(data, extension: "pdf") {
                            savedFilenames.append(filename)
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.enqueueJobs(filenames: savedFilenames)
            self.triggerMainApp()
            self.showConfirmationUI()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.completeRequest()
            }
        }
    }

    // MARK: - App Group I/O

    private func saveData(_ data: Data, extension ext: String) -> String? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return nil }

        let pendingDir = containerURL.appendingPathComponent("PendingReceipts", isDirectory: true)
        try? FileManager.default.createDirectory(at: pendingDir, withIntermediateDirectories: true)

        let filename = "\(UUID().uuidString).\(ext)"
        let fileURL = pendingDir.appendingPathComponent(filename)
        try? data.write(to: fileURL)
        return filename
    }

    private func enqueueJobs(filenames: [String]) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        var existing = defaults.stringArray(forKey: pendingJobsKey) ?? []
        existing.append(contentsOf: filenames)
        defaults.set(existing, forKey: pendingJobsKey)
    }

    // MARK: - Trigger Main App

    private func triggerMainApp() {
        // Walk the UIResponder chain to reach UIApplication and open the host app.
        // This is the only viable pattern for launching the host app from a Share Extension.
        guard let url = URL(string: "receiptvault://process-queue") else { return }
        var responder: UIResponder? = self
        while let r = responder {
            if let application = r as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = r.next
        }
    }

    // MARK: - Extension Lifecycle

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
