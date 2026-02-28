import SwiftUI

@main
struct ReceiptVaultApp: App {
    @StateObject private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .onOpenURL { url in
                    // TODO: drain pending receipt queue when opened via receiptvault://process-queue
                    _ = url
                }
        }
    }
}
