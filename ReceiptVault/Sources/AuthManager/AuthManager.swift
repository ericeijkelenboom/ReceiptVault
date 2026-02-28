import UIKit
import GoogleSignIn

@MainActor
final class AuthManager: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var currentUserEmail: String?

    private let driveScope = "https://www.googleapis.com/auth/drive"
    private let sheetsScope = "https://www.googleapis.com/auth/spreadsheets"

    init() {
        Task { await restorePreviousSignIn() }
    }

    // MARK: - Public

    func signIn() async throws {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.isEmpty,
              clientID != "REPLACE_WITH_GOOGLE_CLIENT_ID" else {
            throw ReceiptVaultError.parseFailure("Google client ID not configured. Add GIDClientID to project.yml Info.plist properties.")
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController else {
            throw ReceiptVaultError.authRequired
        }

        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: rootVC,
            hint: nil,
            additionalScopes: [driveScope, sheetsScope]
        )

        isSignedIn = true
        currentUserEmail = result.user.profile?.email
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
        currentUserEmail = nil
    }

    /// Returns a fresh OAuth access token, refreshing if expired.
    func freshAccessToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw ReceiptVaultError.authRequired
        }
        let refreshed = try await user.refreshTokensIfNeeded()
        return refreshed.accessToken.tokenString
    }

    // MARK: - Private

    private func restorePreviousSignIn() async {
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            isSignedIn = true
            currentUserEmail = user.profile?.email
        } catch {
            isSignedIn = false
            currentUserEmail = nil
        }
    }
}
