import SwiftUI
import GoogleSignIn
import UserNotifications

@main
struct ReceiptVaultApp: App {
    @StateObject private var authManager = AuthManager()
    @StateObject private var processingController = ProcessingController()
    @StateObject private var receiptStore = ReceiptStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(processingController)
                .environmentObject(receiptStore)
                .task {
                    guard processingController.pipeline == nil else { return }
                    // Request notification permission once on first launch
                    try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound])
                    processingController.pipeline = ProcessingPipeline(authManager: authManager, receiptStore: receiptStore)
                }
                .onOpenURL { url in
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    if url.scheme == "receiptvault" {
                        Task { await processingController.drainQueue() }
                    }
                }
        }
    }
}
