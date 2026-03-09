import SwiftUI
import AVKit

// MARK: - MediaDetailView (fullscreen preview for generated images & videos)

struct MediaDetailView: View {
    let generation: MediaGeneration
    let manager: MediaGenerationManager

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if let url = manager.imageURL(for: generation) {
                    if generation.type == .video {
                        MediaVideoPlayer(url: url)
                    } else {
                        imageContent(url: url)
                    }
                } else if let thumbData = generation.thumbnailData {
                    thumbnailFallback(thumbData)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Kunde inte ladda media")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(generation.displayTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng") { dismiss() }
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .primaryAction) {
                    shareButton
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            #else
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng") { dismiss() }
                }
            }
            #endif
        }
    }

    // MARK: - Image content

    @ViewBuilder
    private func imageContent(url: URL) -> some View {
        if let data = try? Data(contentsOf: url) {
            #if os(macOS)
            if let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
            #else
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
            #endif
        }
    }

    @ViewBuilder
    private func thumbnailFallback(_ data: Data) -> some View {
        #if os(macOS)
        if let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .padding()
        }
        #else
        if let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .padding()
        }
        #endif
    }

    // MARK: - Share

    #if os(iOS)
    @ViewBuilder
    private var shareButton: some View {
        if let url = manager.imageURL(for: generation) {
            ShareLink(item: url) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(.white)
            }
        }
    }
    #else
    @ViewBuilder
    private var shareButton: some View {
        EmptyView()
    }
    #endif
}
