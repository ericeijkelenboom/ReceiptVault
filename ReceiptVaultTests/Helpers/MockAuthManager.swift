import Foundation
@testable import ReceiptVault

class MockAuthManager: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var currentUserEmail: String? = nil

    var signInThrows: Error?
    var freshAccessTokenThrows: Error?

    func signIn() async throws {
        if let error = signInThrows {
            throw error
        }
        isSignedIn = true
        currentUserEmail = "test@example.com"
    }

    func signOut() {
        isSignedIn = false
        currentUserEmail = nil
    }

    func freshAccessToken() async throws -> String {
        if let error = freshAccessTokenThrows {
            throw error
        }
        return "mock_token_\(UUID().uuidString)"
    }
}
