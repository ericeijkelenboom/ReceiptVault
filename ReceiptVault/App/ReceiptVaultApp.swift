import SwiftUI
import GoogleSignIn
import UserNotifications

@main
struct ReceiptVaultApp: App {
    @StateObject private var authManager = AuthManager()
    @State private var pipeline: ProcessingPipeline?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .task {
                    guard pipeline == nil else { return }
                    // Request notification permission once on first launch
                    try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound])
                    pipeline = ProcessingPipeline(authManager: authManager)
                }
                .onOpenURL { url in
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    if url.scheme == "receiptvault" {
                        Task { await pipeline?.drainQueue() }
                    }
                }
        }
    }
}
