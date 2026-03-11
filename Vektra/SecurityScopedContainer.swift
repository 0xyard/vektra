import SwiftUI

struct SecurityScopedContainer<Content: View>: View {
    let url: URL
    @ViewBuilder let content: () -> Content

    @State private var isAccessing = false

    var body: some View {
        content()
            .onAppear {
                if !isAccessing {
                    isAccessing = url.startAccessingSecurityScopedResource()
                }
            }
            .onDisappear {
                if isAccessing {
                    url.stopAccessingSecurityScopedResource()
                    isAccessing = false
                }
            }
    }
}

