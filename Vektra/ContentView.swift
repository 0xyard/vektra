import SwiftUI
internal import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            LibrarySidebar()
        } content: {
            SearchView()
        } detail: {
            PreviewPanel()
        }
        .navigationSplitViewStyle(.balanced)
        // File drop on the whole window
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = try? await provider.loadItem(forTypeIdentifier: "public.file-url") as? URL {
                        urls.append(url)
                    }
                }
                await MainActor.run { store.prepareFiles(urls: urls) }
            }
            return true
        }
        // File picker trigger
        .fileImporter(
            isPresented: $store.triggerFilePicker,
            allowedContentTypes: [.movie, .audio, .image, .pdf, .text, .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { store.prepareFiles(urls: urls) }
        }
        // Confirm embed sheet
        .sheet(isPresented: $store.showConfirmEmbed) {
            ConfirmEmbedView()
        }
        // Embed progress sheet (dismissible; embeds continue in background)
        .sheet(isPresented: $store.showEmbedProgress) {
            EmbedProgressView()
        }
        // Settings
        .sheet(isPresented: $store.showSettings) {
            SettingsView()
        }
        // Error alert
        .alert("Error", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        // Progress toasts overlay
        .overlay(alignment: .bottomTrailing) {
            ProgressToastStack()
        }
    }
}
