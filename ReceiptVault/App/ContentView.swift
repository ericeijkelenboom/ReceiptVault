import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ReceiptsView()
                .tabItem {
                    Label("Receipts", systemImage: "receipt")
                }

            ProcessingQueueView()
                .tabItem {
                    Label("Queue", systemImage: "tray.and.arrow.down")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
        .environmentObject(ProcessingController())
        .environmentObject(ReceiptStore())
}
