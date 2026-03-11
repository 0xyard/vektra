import SwiftUI
import AVKit
import PDFKit
import QuickLookUI

// MARK: - Preview Panel

struct PreviewPanel: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Group {
            if let entry = store.selectedEntry {
                EntryPreview(entry: entry)
            } else {
                placeholderView
            }
        }
        .navigationTitle(store.selectedEntry?.fileName ?? "Preview")
    }

    private var placeholderView: some View {
        VStack(spacing: 14) {
            Image(systemName: "eye.slash")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
            Text("Select a file to preview")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Entry Preview

struct EntryPreview: View {
    let entry: LibraryEntry
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                mediaPreview
                Divider()
                metaSection
                Divider()
                actionsSection
            }
        }
    }

    // ── Media Preview ─────────────────────────────────────────────────────────
    @ViewBuilder
    private var mediaPreview: some View {
        let url = entry.resolvedFileURL
        let exists = FileManager.default.fileExists(atPath: url.path)

        if !exists {
            missingFileView
        } else {
            SecurityScopedContainer(url: url) {
                switch entry.fileKind {
                case .video:
                    VideoPreviewView(url: url, jumpStartSec: store.selectedEntry?.id == entry.id ? store.videoJumpStartSec : nil)
                case .audio:
                    AudioPreviewView(url: url, fileName: entry.fileName)
                case .image:
                    ImagePreviewView(url: url)
                case .pdf:
                    PDFPreviewView(url: url)
                case .text, .document:
                    TextPreviewView(url: url)
                }
            }
        }
    }

    private var missingFileView: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text("File not found")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(entry.filePath)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }

    // ── Metadata ──────────────────────────────────────────────────────────────
    private var metaSection: some View {
        VStack(spacing: 0) {
            MetaRow(key: "NAME", value: entry.fileName)
            MetaRow(key: "TYPE", value: entry.fileKind.rawValue.uppercased())
            MetaRow(key: "SIZE", value: entry.sizeFormatted)
            MetaRow(key: "INDEXED", value: entry.embeddedAgo)
            MetaRow(key: "PATH", value: entry.filePath, isPath: true)
        }
        .padding(.vertical, 4)
    }

    // ── Actions ───────────────────────────────────────────────────────────────
    private var actionsSection: some View {
        VStack(spacing: 8) {
            ActionButton(
                label: "Open in Default App",
                icon: "arrow.up.right.square"
            ) {
                NSWorkspace.shared.open(entry.resolvedFileURL)
            }
            ActionButton(
                label: "Re-embed File",
                icon: "arrow.clockwise"
            ) {
                Task { await store.embedOne(url: entry.resolvedFileURL) }
            }
            ActionButton(
                label: "Show in Finder",
                icon: "folder"
            ) {
                NSWorkspace.shared.activateFileViewerSelecting([entry.resolvedFileURL])
            }
            ActionButton(
                label: "Remove from Library",
                icon: "trash",
                role: .destructive
            ) {
                store.delete(entry)
            }
        }
        .padding(14)
    }
}

// MARK: - Video Preview

struct VideoPreviewView: View {
    let url: URL
    let jumpStartSec: Int?
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
            } else {
                ProgressView()
                    .frame(height: 240)
            }
        }
        .onAppear {
            let p = AVPlayer(url: url)
            player = p
            if let jumpStartSec {
                let t = CMTime(seconds: Double(jumpStartSec), preferredTimescale: 600)
                p.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

// MARK: - Audio Preview

struct AudioPreviewView: View {
    let url: URL
    let fileName: String
    @State private var player: AVPlayer?
    @State private var isPlaying = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 24)

            Text(fileName)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Button {
                if isPlaying {
                    player?.pause()
                } else {
                    if player == nil { player = AVPlayer(url: url) }
                    player?.play()
                }
                isPlaying.toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .onDisappear {
            player?.pause()
            player = nil
            isPlaying = false
        }
    }
}

// MARK: - Image Preview

struct ImagePreviewView: View {
    let url: URL

    var body: some View {
        if let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 280)
        } else {
            Image(systemName: "photo.slash")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
                .frame(height: 180)
        }
    }
}

// MARK: - PDF Preview

struct PDFPreviewView: View {
    let url: URL

    var body: some View {
        PDFKitView(url: url)
            .frame(height: 360)
    }
}

struct PDFKitView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
    }
}

// MARK: - Text Preview

struct TextPreviewView: View {
    let url: URL
    @State private var text: String = ""

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .textSelection(.enabled)
        }
        .frame(height: 260)
        .background(Color(.textBackgroundColor).opacity(0.5))
        .onAppear {
            text = (try? String(contentsOf: url, encoding: .utf8)) ?? "(Unable to read file)"
            if text.count > 6000 { text = String(text.prefix(6000)) + "\n\n… (truncated)" }
        }
    }
}

// MARK: - Helper Components

struct MetaRow: View {
    let key: String
    let value: String
    var isPath: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 60, alignment: .trailing)
                .padding(.top, 1)

            Text(value)
                .font(isPath ? .system(size: 10, design: .monospaced) : .system(size: 12.5))
                .foregroundStyle(isPath ? Color(.tertiaryLabelColor) : Color(.labelColor))
                .textSelection(.enabled)
                .lineLimit(isPath ? 3 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

struct ActionButton: View {
    let label: String
    let icon: String
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .tint(role == .destructive ? .red : nil)
    }
}

// MARK: - Progress Toast Stack

struct ProgressToastStack: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(store.activeEmbeds.values.sorted(by: { $0.id.uuidString < $1.id.uuidString })) { embed in
                ProgressToast(embed: embed)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(16)
        .animation(.easeInOut(duration: 0.2), value: store.activeEmbeds.count)
    }
}

struct ProgressToast: View {
    let embed: ActiveEmbed

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(embed.fileName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Text(embed.status)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(embed.isError ? .red : .secondary)
            ProgressView(value: embed.fraction)
                .tint(embed.isDone ? .green : embed.isError ? .red : .accentColor)
        }
        .padding(12)
        .frame(width: 240)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    embed.isDone ? Color.green.opacity(0.4) :
                    embed.isError ? Color.red.opacity(0.4) :
                    Color(.separatorColor),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}
