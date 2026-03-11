import SwiftUI

struct SearchView: View {
    @EnvironmentObject var store: AppStore
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            resultsList
        }
        .navigationTitle("Search")
    }

    // ── Search Bar ────────────────────────────────────────────────────────────
    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Describe what you're looking for…", text: $store.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($searchFocused)
                    .onSubmit { Task { await store.search() } }

                if !store.searchQuery.isEmpty {
                    Button {
                        store.searchQuery = ""
                        store.hasSearched = false
                        store.results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            Button {
                Task { await store.search() }
            } label: {
                if store.isSearching {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Search")
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty || store.isSearching)
            .frame(width: 72)
        }
        .padding(16)
    }

    // ── Results ───────────────────────────────────────────────────────────────
    @ViewBuilder
    private var resultsList: some View {
        if store.library.isEmpty && !store.hasSearched {
            emptyLibraryState
        } else if !store.hasSearched {
            readyState
        } else if store.results.isEmpty {
            noResultsState
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Text("\(store.results.count) result\(store.results.count == 1 ? "" : "s")")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    LazyVStack(spacing: 4) {
                        ForEach(store.results) { result in
                            ResultCard(result: result)
                                .padding(.horizontal, 12)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private var emptyLibraryState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("Add files to get started")
                .font(.title3).fontWeight(.medium)
                .foregroundStyle(.secondary)
            Text("Add videos, audio, images, PDFs, or text files\nto your library, then search them with natural language.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add Files") { store.triggerAddFiles() }
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var readyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
            Text("Search your library")
                .font(.title3).fontWeight(.medium)
                .foregroundStyle(.secondary)
            Text("Describe a concept, vibe, or content in plain language.\nVektra will find matching files using semantic AI search.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.diamond")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
            Text("No matches found")
                .font(.title3).fontWeight(.medium)
                .foregroundStyle(.secondary)
            Text("Try different keywords or add more files to your library.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Result Card

struct ResultCard: View {
    let result: SearchResult
    @EnvironmentObject var store: AppStore

    private var isSelected: Bool { store.selectedEntry?.id == result.id }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: result.entry.fileKind.icon)
                .font(.system(size: 20))
                .foregroundStyle(result.entry.fileKind.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.entry.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(result.entry.sizeFormatted)
                    Text("·")
                    Text(result.entry.embeddedAgo)
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)

                if let seg = result.bestSegment {
                    Text(String(format: "Best match: %02d:%02d–%02d:%02d", seg.startOffsetSec / 60, seg.startOffsetSec % 60, seg.endOffsetSec / 60, seg.endOffsetSec % 60))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(result.scorePercent)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.25))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor)
                                .frame(width: geo.size.width * result.scoreFraction)
                        }
                }
                .frame(width: 56, height: 3)
            }

            Button {
                let url = result.entry.resolvedFileURL
                let ok = url.startAccessingSecurityScopedResource()
                NSWorkspace.shared.open(url)
                if ok { url.stopAccessingSecurityScopedResource() }
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open in default app")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.windowBackgroundColor).opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : Color(.separatorColor), lineWidth: isSelected ? 1 : 0.5)
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectedEntry = result.entry
            store.videoJumpStartSec = result.bestSegment?.startOffsetSec
        }
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }
}
