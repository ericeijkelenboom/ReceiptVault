import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var apiKey: String = ""
    @State private var keySaved: Bool = false

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
                        try? KeychainHelper.write(key: "anthropic_api_key", value: apiKey)
                        keySaved = true
                    }
                    if keySaved || KeychainHelper.read(key: "anthropic_api_key") != nil {
                        Label("Key stored in Keychain", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(Color.brandAccent)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Settings")
            .tint(.brandPrimary)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthManager())
}
