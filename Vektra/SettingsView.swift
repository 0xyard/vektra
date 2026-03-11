import SwiftUI
internal import UniformTypeIdentifiers

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var showKey = false
    @Environment(\.dismiss) private var dismiss
    
    private var appVersionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let short, let build { return "v\(short) (\(build))" }
        if let short { return "v\(short)" }
        if let build { return "Build \(build)" }
        return "Unknown"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    apiSection
                    Divider()
                    howToSection
                    Divider()
                    pricingSection
                    Divider()
                    creditsSection
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 520, height: 640)
        .onAppear {
            store.ensureApiKeyLoaded()
        }
    }

    // ── Header ────────────────────────────────────────────────────────────────
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.title2).fontWeight(.bold)
                Text("API key and embedding configuration")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    // ── API ───────────────────────────────────────────────────────────────────
    private var apiSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Google API Key", systemImage: "key")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("API KEY")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Group {
                        if showKey {
                            TextField("AIza…", text: $store.settings.apiKey)
                        } else {
                            SecureField("AIza…", text: $store.settings.apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))

                    Button(showKey ? "Hide" : "Show") {
                        if showKey {
                            showKey = false
                        } else {
                            store.ensureApiKeyLoaded(operationPrompt: "Vektra needs access to your Google API key to show it.")
                            showKey = true
                        }
                    }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Text("API key is stored in the Keychain. Never sent anywhere except Google's API.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("EMBEDDING MODEL")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                TextField("gemini-embedding-2-preview", text: $store.settings.model)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))

                Link("Verify current model name at ai.google.dev",
                     destination: URL(string: "https://ai.google.dev/gemini-api/docs/models")!)
                    .font(.caption)
            }
        }
    }

    // ── How To ────────────────────────────────────────────────────────────────
    private var howToSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("How to get your API key", systemImage: "questionmark.circle")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                StepRow(num: "1") {
                    HStack(spacing: 4) {
                        Text("Visit")
                        Link("Google AI Studio → API Keys",
                             destination: URL(string: "https://aistudio.google.com/app/apikey")!)
                    }
                }
                StepRow(num: "2") {
                    Text("Sign in with your Google account and click **Create API key**")
                }
                StepRow(num: "3") {
                    HStack(spacing: 4) {
                        Text("Enable billing at")
                        Link("Google Cloud Console",
                             destination: URL(string: "https://console.cloud.google.com/billing")!)
                        Text("(required; free tier available)")
                    }
                }
                StepRow(num: "4") {
                    Text("Copy and paste your key above. It never leaves this machine.")
                }
            }
        }
    }

    // ── Pricing ───────────────────────────────────────────────────────────────
    private var pricingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Estimated Pricing", systemImage: "dollarsign.circle")
                    .font(.headline)
                Spacer()
                Link("Verify at ai.google.dev/pricing",
                     destination: URL(string: "https://ai.google.dev/pricing")!)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                PricingHeaderRow()
                PricingRow(type: "🎬 Video",  rate: "258 tokens/sec",  cost: "~$0.14 / hour")
                PricingRow(type: "🎵 Audio",  rate: "32 tokens/sec",   cost: "~$0.02 / hour")
                PricingRow(type: "🖼️ Image",  rate: "258 tokens/file", cost: "~$0.0001 / file")
                PricingRow(type: "📄 PDF",    rate: "~800 tokens/page", cost: "~$0.0001 / page")
                PricingRow(type: "📝 Text",   rate: "~250 tokens/KB",  cost: "< $0.01 / file", isLast: true)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(.separatorColor), lineWidth: 0.5)
            }

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                Text("Base rate: **$0.15 per 1 million tokens**. Files uploaded to Google for embedding expire after 48 hours. Embeddings are stored locally only.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
    
    // ── Credits ───────────────────────────────────────────────────────────────
    private var creditsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Credits", systemImage: "person.crop.circle")
                .font(.headline)
            
            HStack(spacing: 6) {
                Text("Version:")
                    .foregroundStyle(.secondary)
                Text(appVersionString)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            
            Link("GitHub repo", destination: URL(string: "https://github.com/0xyard/vektra")!)
                .font(.callout)
        }
    }

    // ── Footer ────────────────────────────────────────────────────────────────
    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
            Button("Save Settings") {
                store.saveSettings()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }
}

// MARK: - Helper components

struct StepRow<Content: View>: View {
    let num: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(num)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.12), in: Circle())
                .padding(.top, 1)
            content
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PricingHeaderRow: View {
    var body: some View {
        HStack {
            Text("FILE TYPE").frame(maxWidth: .infinity, alignment: .leading)
            Text("TOKEN RATE").frame(width: 120, alignment: .center)
            Text("EST. COST").frame(width: 110, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.6))
    }
}

struct PricingRow: View {
    let type: String
    let rate: String
    let cost: String
    var isLast: Bool = false

    var body: some View {
        HStack {
            Text(type).frame(maxWidth: .infinity, alignment: .leading)
            Text(rate)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .center)
            Text(cost)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.orange)
                .frame(width: 110, alignment: .trailing)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            if !isLast { Divider() }
        }
    }
}

// MARK: - Confirm Embed Sheet

struct ConfirmEmbedView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var showAddMorePicker = false

    private var totalCost: Double {
        store.pendingFiles.reduce(0) { $0 + $1.estimatedCostUSD }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Embed \(store.pendingFiles.count) File\(store.pendingFiles.count == 1 ? "" : "s")")
                    .font(.title2).fontWeight(.bold)
                Text("Files will be uploaded to Google's API for embedding, then stored locally")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            // File list
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.pendingFiles, id: \.url) { estimate in
                        ConfirmFileRow(estimate: estimate) {
                            store.removePendingFile(url: estimate.url)
                        }
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 320)

            Divider()

            // Total
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ESTIMATED TOTAL API COST")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("Charged to your Google account")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(totalCost < 0.01 ? "< $0.01" : String(format: "$%.4f", totalCost))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
            }
            .padding(16)
            .background(Color.orange.opacity(0.06))

            Divider()

            // Actions
            HStack {
                Button("Add more files…") {
                    showAddMorePicker = true
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Cancel") {
                    store.pendingFiles = []
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Embed All Files") {
                    store.confirmEmbed()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 480)
        .fileImporter(
            isPresented: $showAddMorePicker,
            allowedContentTypes: [.movie, .audio, .image, .pdf, .text, .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { store.appendFiles(urls: urls) }
        }
    }
}

struct ConfirmFileRow: View {
    let estimate: CostEstimate
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: estimate.fileKind.icon)
                .font(.system(size: 18))
                .foregroundStyle(estimate.fileKind.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(estimate.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(estimate.sizeFormatted)
                    Text("·")
                    Text(estimate.note)
                    Text("·")
                    Text("\(estimate.estimatedTokens.formatted()) tokens")
                }
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                
                if let warn = estimate.tokenLimitWarning {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text(warn.message)
                            .lineLimit(1)
                    }
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(warn.severity == .severe ? .red : .orange)
                }
            }

            Spacer()

            Text(estimate.costFormatted)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.orange)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.tertiary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}
