import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ReceiptsView()
                .tabItem {
                    Label("Receipts", systemImage: "receipt")
                }

SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(.brandPrimary)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
        .environmentObject(ProcessingController())
        .environmentObject(ReceiptStore())
}
