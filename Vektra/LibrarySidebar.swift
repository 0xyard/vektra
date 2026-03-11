import SwiftUI

struct LibrarySidebar: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        List(selection: Binding(
            get: { store.selectedEntry },
            set: { newValue in
                // Defer publish to next runloop to avoid "Publishing changes from within view updates".
                DispatchQueue.main.async {
                    store.selectedEntry = newValue
                }
            }
        )) {
            if store.library.isEmpty {
                emptyState
            } else {
                ForEach(store.library) { entry in
                    LibraryRow(entry: entry)
                        .tag(entry)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.delete(entry)
                            } label: { Label("Remove", systemImage: "trash") }
                        }
                        .contextMenu {
                            Button("Open in Default App") {
                                NSWorkspace.shared.open(entry.resolvedFileURL)
                            }
                            Button("Re-embed") {
                                Task { await store.embedOne(url: entry.resolvedFileURL) }
                            }
                            Divider()
                            Button("Remove from Library", role: .destructive) {
                                store.delete(entry)
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Vektra")
        .navigationSubtitle("\(store.library.count) file\(store.library.count == 1 ? "" : "s")")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.triggerAddFiles()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Files (⌘O)")
            }
            ToolbarItem {
                Button {
                    store.showEmbedProgress = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "arrow.up.doc")
                        if store.activeEmbeds.count > 0 {
                            Text("\(store.activeEmbeds.count)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.red, in: Capsule())
                                .offset(x: 10, y: -8)
                        }
                    }
                }
                .help(store.activeEmbeds.isEmpty ? "Embed History" : "Embedding (\(store.activeEmbeds.count))")
            }
            ToolbarItem {
                Button {
                    store.showSettings = true
                } label: {
                    Image(systemName: "gear")
                }
                .help("Settings")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No files yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Click + or drag files\nonto the window")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
            Button("Add Files") { store.triggerAddFiles() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

struct LibraryRow: View {
    let entry: LibraryEntry
    @EnvironmentObject var store: AppStore

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: entry.fileKind.icon)
                .foregroundStyle(entry.fileKind.accentColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.fileName)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text(entry.sizeFormatted)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text(entry.fileKind.rawValue)
                .font(.system(size: 9, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
