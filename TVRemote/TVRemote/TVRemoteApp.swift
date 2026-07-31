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
    @State private var presentedSheet: RemoteSheet?

    var body: some View {
        ZStack(alignment: .top) {
            NavigationStack {
                Group {
                    if coordinator.isConnected, let device = coordinator.selectedDevice {
                        RemoteView(
                            coordinator: coordinator,
                            device: device,
                            onShowSettings: { presentedSheet = .settings },
                            onShowDevices: { presentedSheet = .devices }
                        )
                    } else {
                        DeviceListView(coordinator: coordinator)
                    }
                }
            }
            .blur(radius: coordinator.textInputSession == nil ? 0 : 6)
            .allowsHitTesting(coordinator.textInputSession == nil)

            if let session = coordinator.textInputSession {
                Color.black.opacity(0.14)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        coordinator.dismissTextInput()
                    }

                TVKeyboardBar(
                    deviceName: coordinator.selectedDevice?.name ?? "TV",
                    text: Binding(
                        get: { coordinator.liveText },
                        set: { coordinator.updateLiveText($0) }
                    ),
                    fieldLabel: session.fieldLabel,
                    showsTVKeyboardHint: coordinator.selectedDevice?.platform == .googleTV
                )
                .padding(.top, 8)
                .zIndex(1)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if coordinator.textInputSession != nil {
                TVKeyboardCloseButton {
                    Task { await coordinator.closeTVKeyboard() }
                }
                .padding(.bottom, 12)
            }
        }
        .onChange(of: coordinator.textInputSession?.id) { _, sessionID in
            if sessionID != nil {
                presentedSheet = nil
            }
        }
        .onChange(of: coordinator.pairingPrompt) { _, prompt in
            if prompt != nil {
                presentedSheet = .pairing
            } else if presentedSheet == .pairing {
                presentedSheet = nil
            }
        }
        .onChange(of: coordinator.state) { _, state in
            if state == .connected, presentedSheet == .devices {
                presentedSheet = nil
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .devices:
                NavigationStack {
                    DeviceListView(coordinator: coordinator)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { presentedSheet = nil }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)

            case .settings:
                NavigationStack {
                    SettingsView(coordinator: coordinator)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { presentedSheet = nil }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)

            case .pairing:
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
}

private enum RemoteSheet: String, Identifiable {
    case devices
    case settings
    case pairing

    var id: String { rawValue }
}

private struct SettingsView: View {
    @ObservedObject var coordinator: RemoteCoordinator

    var body: some View {
        Form {
            if let device = coordinator.selectedDevice {
                Section("Connected TV") {
                    LabeledContent("Device", value: device.name)
                    LabeledContent("Type", value: device.platform.displayName)
                }

                Section {
                    if device.platform == .googleTV {
                        Picker("Send color buttons", selection: relaySelection) {
                            Text("Directly to \(device.name)").tag("")
                            ForEach(coordinator.availableColorRelayDevices) { relayDevice in
                                Text("Through \(relayDevice.name)").tag(relayDevice.id)
                            }
                        }

                        if coordinator.colorRelayState == .connecting {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Connecting color-button relay…")
                                    .foregroundStyle(.secondary)
                            }
                        } else if let message = coordinator.colorRelayMessage {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(colorRelayFailed ? Color.red : Color.secondary)
                        } else if coordinator.availableColorRelayDevices.isEmpty {
                            Text("No other Google TVs are available. Discover or connect to the relay TV once first.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("\(device.platform.displayName) does not support Wi-Fi color-button commands.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Color Buttons")
                } footer: {
                    if device.platform == .googleTV {
                        Text("Use a relay when a box filters color keys. Only red, green, yellow, and blue are rerouted; every other command stays connected directly to \(device.name).")
                    }
                }
            } else {
                ContentUnavailableView(
                    "No TV Connected",
                    systemImage: "tv.slash",
                    description: Text("Connect to a TV from the Remote tab to configure its settings.")
                )
            }
        }
        .navigationTitle("Settings")
    }

    private var relaySelection: Binding<String> {
        Binding(
            get: { coordinator.colorRelayDevice?.id ?? "" },
            set: { relayID in
                if relayID.isEmpty {
                    Task { await coordinator.disableColorRelay() }
                } else if let device = coordinator.availableColorRelayDevices.first(
                    where: { $0.id == relayID }
                ) {
                    Task { await coordinator.connectColorRelay(to: device) }
                }
            }
        )
    }

    private var colorRelayFailed: Bool {
        if case .failed = coordinator.colorRelayState { return true }
        return false
    }
}
