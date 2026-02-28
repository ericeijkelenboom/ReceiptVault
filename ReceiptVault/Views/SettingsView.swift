import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var apiKey: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Google Account") {
                    if authManager.isSignedIn, let email = authManager.currentUserEmail {
                        Text(email)
                            .foregroundStyle(.secondary)
                        Button("Sign Out", role: .destructive) {
                            authManager.signOut()
                        }
                    } else {
                        Button("Sign in with Google") {
                            Task {
                                try? await authManager.signIn()
                            }
                        }
                    }
                }

                Section("Claude API Key") {
                    SecureField("API Key", text: $apiKey)
                        .textContentType(.password)
                    Button("Save to Keychain") {
                        // TODO: write apiKey to Keychain under key "anthropic_api_key"
                        _ = apiKey
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthManager())
}
