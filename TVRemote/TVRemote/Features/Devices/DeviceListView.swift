import SwiftUI

struct DeviceListView: View {
    @ObservedObject var coordinator: RemoteCoordinator
    @State private var showsManualEntry = false

    var body: some View {
        List {
            Section {
                statusRow
            }

            if coordinator.devices.isEmpty, coordinator.state != .discovering {
                ContentUnavailableView(
                    "No TVs Found",
                    systemImage: "tv.slash",
                    description: Text("Check Wi-Fi, refresh, or add a Roku or Google TV by IP address.")
                )
            } else {
                Section("TVs") {
                    ForEach(coordinator.devices) { device in
                        Button {
                            Task { await coordinator.connect(to: device) }
                        } label: {
                            DeviceRow(device: device)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Forget", role: .destructive) {
                                coordinator.forget(device)
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    showsManualEntry = true
                } label: {
                    Label("Add by IP Address", systemImage: "plus.circle")
                }
            } footer: {
                Text("Manual entry supports Roku and Google/Android TV. Apple TV requires Bonjour discovery.")
            }

            if let error = coordinator.errorMessage {
                Section("Connection issue") {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("TV Remote")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await coordinator.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(coordinator.state == .discovering)
                .accessibilityLabel("Refresh TVs")
            }
        }
        .task {
            await coordinator.refresh()
        }
        .sheet(isPresented: $showsManualEntry) {
            ManualDeviceView { name, host, platform in
                showsManualEntry = false
                Task { await coordinator.addManualDevice(name: name, host: host, platform: platform) }
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 12) {
            if coordinator.state == .discovering || coordinator.state == .connecting {
                ProgressView()
            } else {
                Image(systemName: "wifi")
                    .foregroundStyle(.secondary)
            }
            Text(coordinator.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DeviceRow: View {
    let device: RemoteDevice

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: device.platform.symbolName)
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.headline)
                Text("\(device.platform.displayName) · \(device.host)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private struct ManualDeviceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var host = ""
    @State private var platform = TVPlatform.roku

    let onAdd: (String, String, TVPlatform) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Picker("TV type", selection: $platform) {
                    Text("Roku").tag(TVPlatform.roku)
                    Text("Google / Android TV").tag(TVPlatform.googleTV)
                }
                TextField("Name (optional)", text: $name)
                TextField("IP address", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
            }
            .navigationTitle("Add TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") { onAdd(name, host, platform) }
                        .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
