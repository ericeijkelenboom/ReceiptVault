import SwiftUI

struct ContentView: View {
    var body: some View {
        ReceiptsView()
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
        .environmentObject(ProcessingController())
        .environmentObject(ReceiptStore())
}
