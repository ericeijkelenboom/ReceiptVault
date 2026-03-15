import SwiftUI
import GoogleSignIn
import UserNotifications
import CoreData

@main
struct ReceiptVaultApp: App {
    @StateObject private var authManager = AuthManager()
    @StateObject private var processingController = ProcessingController()
    @StateObject private var receiptStore = ReceiptStoreCore()
    @Environment(\.managedObjectContext) private var viewContext

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(processingController)
                .environmentObject(receiptStore)
                .environment(\.managedObjectContext, CoreDataStack.shared.viewContext)
                .task {
                    guard processingController.pipeline == nil else { return }
                    // Request notification permission once on first launch
                    _ = try? await UNUserNotificationCenter.current()
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
