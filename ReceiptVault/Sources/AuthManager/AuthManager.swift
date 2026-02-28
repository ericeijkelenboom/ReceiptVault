import Foundation
import GoogleSignIn

@MainActor
final class AuthManager: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var currentUserEmail: String?

    func signIn() async throws {
        throw ReceiptVaultError.notImplemented
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
        currentUserEmail = nil
    }
}
