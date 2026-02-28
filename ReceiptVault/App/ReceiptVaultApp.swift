import SwiftUI
import GoogleSignIn

@main
struct ReceiptVaultApp: App {
    @StateObject private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .onOpenURL { url in
                    // Handle Google Sign-In OAuth redirect
                    if GIDSignIn.sharedInstance.handle(url) {
                        return
                    }
                    // TODO: drain pending receipt queue when opened via receiptvault://process-queue
                }
        }
    }
}
