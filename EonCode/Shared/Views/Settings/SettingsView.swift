import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var keychain = KeychainManagerObservable.shared

    @State private var anthropicKey = ""
    @State private var elevenLabsKey = ""
    @State private var macServerURL = ""
    @State private var showAnthropicKey = false
    @State private var saveMessage = ""

    var body: some View {
        #if os(macOS)
        macSettings
        #else
        NavigationView { iOSSettings }
        #endif
    }

    var macSettings: some View {
        TabView {
            apiKeysSection
                .tabItem { Label("API-nycklar", systemImage: "key") }
                .padding()

            modelSection
                .tabItem { Label("Modell", systemImage: "cpu") }
                .padding()

            syncSection
                .tabItem { Label("Synk", systemImage: "arrow.triangle.2.circlepath") }
                .padding()

            costSection
                .tabItem { Label("Kostnad", systemImage: "chart.bar") }
                .padding()
        }
        .frame(width: 560, height: 640)
        .background(Color.chatBackground)
        .preferredColorScheme(.dark)
    }

    var iOSSettings: some View {
        Form {
            Section("API-nycklar") { apiKeysSection }
            Section("Claude-modell") { modelSection }
            Section("Synk") { syncSection }
            Section("Röst (ElevenLabs)") {
                Toggle("Aktivera text-till-tal", isOn: $settings.ttsEnabled)
            }
        }
        .navigationTitle("Inställningar")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.chatBackground)
        .scrollContentBackground(.hidden)
        .preferredColorScheme(.dark)
    }

    var apiKeysSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("API-nycklar")
                .font(.system(size: 16, weight: .bold))

            VStack(alignment: .leading, spacing: 8) {
                Label("Anthropic API-nyckel", systemImage: "key.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                HStack {
                    GlassTextField(
                        placeholder: "sk-ant-…",
                        text: $anthropicKey,
                        isSecure: !showAnthropicKey
                    )
                    Button {
                        showAnthropicKey.toggle()
                    } label: {
                        Image(systemName: showAnthropicKey ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Text("Lagras krypterat i Apple Keychain. Betalas per token direkt till Anthropic.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("ElevenLabs API-nyckel (valfri)", systemImage: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                GlassTextField(placeholder: "Nyckel för text-till-tal", text: $elevenLabsKey, isSecure: true)
            }

            if !saveMessage.isEmpty {
                Text(saveMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.green)
            }

            HStack {
                GlassButton("Spara nycklar", icon: "checkmark", isPrimary: true) {
                    saveKeys()
                }
                Spacer()
            }
        }
        .onAppear {
            anthropicKey = KeychainManager.shared.anthropicAPIKey ?? ""
            elevenLabsKey = KeychainManager.shared.elevenLabsAPIKey ?? ""
            macServerURL = settings.macServerURL
        }
    }

    var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Standard Claude-modell")
                .font(.system(size: 16, weight: .bold))

            ModelPickerView(currentModel: settings.defaultModel) { model in
                settings.defaultModel = model
            }

            Divider().opacity(0.2)

            Toggle("Bekräfta destruktiva agentkommandon", isOn: $settings.agentConfirmDestructive)
        }
    }

    var syncSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Synkronisering")
                .font(.system(size: 16, weight: .bold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Sync-prioritet:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    SyncMethodRow(n: 1, title: "iCloud Drive", icon: "icloud", description: "Primär — alltid aktiv")
                    SyncMethodRow(n: 2, title: "Bonjour/P2P", icon: "wifi", description: "Sekundär — lokal WiFi")
                    SyncMethodRow(n: 3, title: "Lokal HTTP", icon: "network", description: "Reserv — port 52731")
                }
            }

            Divider().opacity(0.2)

            VStack(alignment: .leading, spacing: 8) {
                Text("Mac-server URL (iOS → Mac)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                GlassTextField(placeholder: "http://192.168.1.x:52731", text: $macServerURL)
                Text("Används när Bonjour inte hittar din Mac automatiskt.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
                GlassButton("Spara URL", icon: "checkmark") {
                    settings.macServerURL = macServerURL
                    if let url = URL(string: macServerURL) {
                        LocalNetworkClient.shared.setMacAddress(url)
                    }
                }
            }

            Divider().opacity(0.2)

            Toggle("Automatiska versionssnapshotar", isOn: $settings.autoSnapshot)
                .font(.system(size: 13))
        }
    }

    var costSection: some View {
        CostDashboardView()
    }

    private func saveKeys() {
        var saved = false

        if !anthropicKey.isBlank {
            try? KeychainManager.shared.saveAnthropicKey(anthropicKey)
            saved = true
        }
        if !elevenLabsKey.isBlank {
            try? KeychainManager.shared.saveElevenLabsKey(elevenLabsKey)
            saved = true
            ElevenLabsClient.shared.isEnabled = true
        }

        saveMessage = saved ? "✓ Sparade" : "Ange en nyckel"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            saveMessage = ""
        }
    }
}

struct SyncMethodRow: View {
    let n: Int
    let title: String
    let icon: String
    let description: String

    var body: some View {
        HStack(spacing: 10) {
            Text("\(n)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 16)
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.accentEon)
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Text("·")
                .foregroundColor(.secondary.opacity(0.4))
            Text(description)
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.6))
        }
    }
}

// MARK: - API Keychain observable wrapper

final class KeychainManagerObservable: ObservableObject {
    static let shared = KeychainManagerObservable()
    private init() {}

    var hasAnthropicKey: Bool {
        KeychainManager.shared.anthropicAPIKey?.isEmpty == false
    }
}

// MARK: - Model Picker View

struct ModelPickerView: View {
    let currentModel: ClaudeModel
    let onSelect: (ClaudeModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ClaudeModel.allCases) { model in
                Button {
                    onSelect(model)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(model.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                if model == .haiku {
                                    Text("DEFAULT")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.accentEon.opacity(0.2))
                                        .cornerRadius(4)
                                        .foregroundColor(.accentEon)
                                }
                            }
                            Text(model.description)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        Spacer()
                        if model == currentModel {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentEon)
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(model == currentModel ? Color.accentEon.opacity(0.1) : Color.white.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Cost Dashboard

struct CostDashboardView: View {
    @StateObject private var exchange = ExchangeRateService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Kostnadsspårning")
                .font(.system(size: 16, weight: .bold))

            HStack {
                VStack(alignment: .leading) {
                    Text("Växelkurs")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("1 USD = \(String(format: "%.2f", exchange.usdToSEK)) SEK")
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                }
                Spacer()
                GlassButton("Uppdatera", icon: "arrow.clockwise") {
                    Task { await exchange.refresh() }
                }
            }

            Divider().opacity(0.2)

            VStack(alignment: .leading, spacing: 8) {
                Text("Pris per miljon tokens (USD)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                ForEach(ClaudeModel.allCases) { model in
                    HStack {
                        Text(model.displayName)
                            .font(.system(size: 12))
                        Spacer()
                        Text("In: $\(String(format: "%.0f", model.inputPricePerMTok))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.green)
                        Text("Ut: $\(String(format: "%.0f", model.outputPricePerMTok))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    .padding(.vertical, 2)
                }
            }

            Text("Notera: Cache-läsning kostar 10% av normalpris. Prompt-caching aktiveras automatiskt.")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))
        }
    }
}
