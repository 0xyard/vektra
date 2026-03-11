import SwiftUI

struct EmbedProgressView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedTab: Tab = .active

    private var embeds: [ActiveEmbed] {
        store.activeEmbeds.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private var history: [EmbedHistoryItem] {
        store.embedHistory
    }

    enum Tab: String, CaseIterable, Identifiable {
        case active = "Active"
        case history = "History"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Embedding")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("Close") { store.showEmbedProgress = false }
                    .keyboardShortcut(.cancelAction)
            }

            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            if selectedTab == .active {
                if embeds.isEmpty {
                    Text("No active embeds.")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(embeds) { embed in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(embed.fileName)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                    Text(embed.status)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(embed.isError ? .red : .secondary)
                                        .textSelection(.enabled)
                                    ProgressView(value: embed.fraction)
                                        .tint(embed.isDone ? .green : embed.isError ? .red : .accentColor)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(minHeight: 220)
                }
            } else {
                if history.isEmpty {
                    Text("No embed history yet.")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(history) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Text(item.fileName)
                                            .font(.system(size: 13, weight: .medium))
                                            .lineLimit(1)
                                        Spacer()
                                        Text(item.outcome == .succeeded ? "Success" : item.outcome == .failed ? "Error" : "In progress")
                                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                                            .foregroundStyle(item.outcome == .failed ? .red : item.outcome == .succeeded ? .green : .secondary)
                                    }
                                    Text(item.status)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(item.outcome == .failed ? .red : .secondary)
                                        .textSelection(.enabled)
                                    ProgressView(value: item.fraction)
                                        .tint(item.outcome == .succeeded ? .green : item.outcome == .failed ? .red : .accentColor)
                                    Text(item.updatedAt, style: .time)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(minHeight: 220)
                }
            }

            Text("You can close this window. Embedding continues in the background and successful files will still appear in your library.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 520, height: 420)
    }
}

