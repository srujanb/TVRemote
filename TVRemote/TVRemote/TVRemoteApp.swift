import SwiftUI

@main
struct TVRemoteApp: App {
    @StateObject private var coordinator = RemoteCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView(coordinator: coordinator)
        }
    }
}

struct ContentView: View {
    @ObservedObject var coordinator: RemoteCoordinator
    @State private var pairingCode = ""

    var body: some View {
        NavigationStack {
            Group {
                if coordinator.isConnected, let device = coordinator.selectedDevice {
                    RemoteView(coordinator: coordinator, device: device)
                } else {
                    DeviceListView(coordinator: coordinator)
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { coordinator.pairingPrompt != nil },
                set: { if !$0 { coordinator.pairingPrompt = nil } }
            )
        ) {
            if let prompt = coordinator.pairingPrompt {
                PairingView(
                    prompt: prompt,
                    code: $pairingCode,
                    errorMessage: coordinator.errorMessage
                ) {
                    let code = pairingCode
                    Task {
                        await coordinator.submitPIN(code)
                        if coordinator.isConnected { pairingCode = "" }
                    }
                }
            }
        }
    }
}
