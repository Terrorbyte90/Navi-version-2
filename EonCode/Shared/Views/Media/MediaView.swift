import SwiftUI

// MARK: - LocalAsyncImage

/// Loads an image asynchronously from iCloud using iCloudSyncEngine.
private struct LocalAsyncImage: View {
    let url: URL?

    @State private var image: PlatformImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            if let img = image {
                platformImage(img)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                Color.clear
                    .overlay(ProgressView().scaleEffect(0.7))
            } else {
                Color.clear
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.25))
                    )
            }
        }
        .task(id: url) { await load() }
    }

    @ViewBuilder
    private func platformImage(_ img: PlatformImage) -> Image {
        #if os(macOS)
        Image(nsImage: img)
        #else
        Image(uiImage: img)
        #endif
    }

    private func load() async {
        isLoading = true
        image = nil
        guard let url else { isLoading = false; return }
        if let data = try? await iCloudSyncEngine.shared.readData(from: url) {
            #if os(macOS)
            image = NSImage(data: data)
            #else
            image = UIImage(data: data)
            #endif
        }
        isLoading = false
    }
}

#if os(macOS)
private typealias PlatformImage = NSImage
#else
private typealias PlatformImage = UIImage
#endif

// MARK: - MediaDetailSheet

private struct MediaDetailSheet: View {
    let generation: MediaGeneration
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex = 0

    private var urls: [URL] { MediaGenerationManager.shared.imageURLs(for: generation) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if urls.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.slash")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("Ingen bild tillgänglig")
                            .foregroundColor(.secondary)
                    }
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(urls.enumerated()), id: \.offset) { idx, url in
                            LocalAsyncImage(url: url)
                                .scaledToFit()
                                .tag(idx)
                        }
                    }
                    #if os(iOS)
                    .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .always : .never))
                    #endif
                }
            }
            .navigationTitle(generation.displayTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng") { dismiss() }
                        .foregroundColor(.white.opacity(0.8))
                }
                #if os(iOS)
                if !urls.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        if let url = urls[safe: currentIndex] {
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                }
                #elseif os(macOS)
                if !urls.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            if let url = urls[safe: currentIndex] {
                                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                            }
                        } label: {
                            Image(systemName: "folder")
                        }
                    }
                }
                #endif
            }
            .safeAreaInset(edge: .bottom) {
                detailFooter
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 500)
        #endif
    }

    private var detailFooter: some View {
        VStack(spacing: 6) {
            Text(generation.prompt)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 20)

            HStack(spacing: 16) {
                if generation.costSEK > 0 {
                    Label(String(format: "%.2f kr", generation.costSEK), systemImage: "creditcard")
                }
                if generation.variationCount > 1 {
                    Label("\(currentIndex + 1)/\(generation.variationCount)", systemImage: "square.on.square")
                }
                Label(generation.model.contains("pro") ? "Pro" : "Standard", systemImage: "wand.and.stars")
            }
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.5))
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial.opacity(0.8))
    }
}

// MARK: - MediaView

struct MediaView: View {
    @StateObject private var manager = MediaGenerationManager.shared

    @State private var prompt = ""
    @State private var selectedMode: MediaType = .image
    @State private var imageSize = "1024x1024"
    @State private var imageVariations = 1
    @State private var useProModel = false
    @State private var selectedGeneration: MediaGeneration?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @FocusState private var promptFocused: Bool

    var body: some View {
        #if os(macOS)
        macLayout
        #else
        iOSLayout
        #endif
    }

    // MARK: - macOS Layout

    #if os(macOS)
    private var macLayout: some View {
        HSplitView {
            controlsPanel
                .frame(minWidth: 320, maxWidth: 400)
            galleryPanel
                .frame(minWidth: 400)
        }
        .background(Color.chatBackground)
        .onAppear { Task { await manager.refreshBalance() } }
        .sheet(item: $selectedGeneration) { gen in
            MediaDetailSheet(generation: gen)
        }
    }
    #endif

    // MARK: - iOS Layout

    #if os(iOS)
    private var iOSLayout: some View {
        VStack(spacing: 0) {
            if manager.completedGenerations.isEmpty && !isGenerating {
                emptyStateWithPrompt
            } else {
                galleryWithPrompt
            }
        }
        .background(Color.chatBackground)
        .onAppear { Task { await manager.refreshBalance() } }
        .sheet(item: $selectedGeneration) { gen in
            MediaDetailSheet(generation: gen)
        }
    }

    private var emptyStateWithPrompt: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.accentNavi.opacity(0.7), Color.accentNavi.opacity(0.5)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 56, height: 56)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text("Skapa med AI")
                    .font(.system(size: 22, weight: .semibold))
                Text("Beskriv en bild så genererar Grok den åt dig.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            promptBar
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
    }

    private var galleryWithPrompt: some View {
        VStack(spacing: 0) {
            ScrollView {
                galleryContent
            }
            .scrollDismissesKeyboard(.interactively)
            promptBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.chatBackground)
        }
    }
    #endif

    // MARK: - Prompt Bar (iOS)

    #if os(iOS)
    private var promptBar: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Menu {
                    Picker("Storlek", selection: $imageSize) {
                        Text("1024×1024").tag("1024x1024")
                        Text("1792×1024").tag("1792x1024")
                        Text("1024×1792").tag("1024x1792")
                    }
                    Picker("Variationer", selection: $imageVariations) {
                        ForEach(1...4, id: \.self) { n in
                            Text("\(n) bild\(n > 1 ? "er" : "")").tag(n)
                        }
                    }
                    Toggle("Pro-modell ($0.07)", isOn: $useProModel)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.surfaceHover)
                            .frame(width: 30, height: 30)
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                TextField("Beskriv bilden du vill skapa...", text: $prompt, axis: .vertical)
                    .focused($promptFocused)
                    .font(.callout)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 10)
                    .padding(.leading, 4)

                if isGenerating {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 30, height: 30)
                } else {
                    Button(action: generate) {
                        ZStack {
                            Circle()
                                .fill(canGenerate ? Color.accentNavi : Color.secondary.opacity(0.2))
                                .frame(width: 30, height: 30)
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(canGenerate ? .white : .secondary.opacity(0.5))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGenerate)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.userBubble)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(Color.inputBorder, lineWidth: 0.5)
                    )
            )

            HStack {
                let cost = estimateCostSEK()
                if cost > 0 {
                    Text("~\(String(format: "%.2f kr", cost)) · \(useProModel ? "Pro" : "Standard") · \(imageSize)")
                        .font(.caption2)
                        .foregroundColor(.accentNavi.opacity(0.7))
                }
                Spacer()
                if let bal = manager.balance {
                    Text("Saldo: \(bal.formattedRemaining)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
        }
    }
    #endif

    // MARK: - Gallery Content (shared)

    private var galleryContent: some View {
        let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]
        return VStack(alignment: .leading, spacing: 20) {
            // Active generations
            if !manager.activeGenerations.isEmpty {
                VStack(spacing: 8) {
                    ForEach(manager.activeGenerations) { gen in
                        activeGenerationRow(gen)
                    }
                }
            }

            // Dismissible error banner
            if let error = errorMessage {
                errorBanner(error)
            }

            // Grouped gallery by month
            if manager.completedGenerations.isEmpty {
                if manager.activeGenerations.isEmpty {
                    galleryEmpty
                }
            } else {
                ForEach(manager.groupedCompletedGenerations, id: \.0) { label, items in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(items) { gen in
                                galleryCard(gen)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
    }

    private func activeGenerationRow(_ gen: MediaGeneration) -> some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.7)
            VStack(alignment: .leading, spacing: 2) {
                Text(gen.displayTitle)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(gen.status.displayName)
                    .font(.system(size: 11))
                    .foregroundColor(.accentNavi)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentNavi.opacity(0.3), lineWidth: 0.5)
                )
        )
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.system(size: 13))
            Text(error)
                .font(.system(size: 12))
                .foregroundColor(.red.opacity(0.9))
            Spacer()
            Button { errorMessage = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.red.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    private var galleryEmpty: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.15))
            Text("Genererade bilder visas här")
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(0.4))
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    // MARK: - Gallery Card

    @ViewBuilder
    private func galleryCard(_ gen: MediaGeneration) -> some View {
        let isSelected = selectedGeneration?.id == gen.id
        let firstURL = manager.imageURLs(for: gen).first

        Button { selectedGeneration = gen } label: {
            VStack(spacing: 0) {
                ZStack {
                    Color.surfaceHover

                    // Prefer live iCloud image; fall back to cached thumbnail
                    if firstURL != nil {
                        LocalAsyncImage(url: firstURL)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let thumbData = gen.thumbnailData {
                        #if os(macOS)
                        if let nsImage = NSImage(data: thumbData) {
                            Image(nsImage: nsImage).resizable().scaledToFill()
                        }
                        #else
                        if let uiImage = UIImage(data: thumbData) {
                            Image(uiImage: uiImage).resizable().scaledToFill()
                        }
                        #endif
                    } else {
                        Image(systemName: gen.type == .image ? "photo" : "video")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.2))
                    }

                    // Variation badge
                    if gen.variationCount > 1 {
                        VStack {
                            HStack {
                                Spacer()
                                HStack(spacing: 3) {
                                    Image(systemName: "square.on.square")
                                        .font(.system(size: 9, weight: .semibold))
                                    Text("\(gen.variationCount)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color.black.opacity(0.6), in: Capsule())
                                .padding(6)
                            }
                            Spacer()
                        }
                    }

                    // Video duration badge
                    if let duration = gen.durationText {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text(duration)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                                    .padding(6)
                            }
                        }
                    }
                }
                .frame(height: 160)
                .clipped()
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(gen.displayTitle)
                        .font(.system(size: 12)).lineLimit(2)
                    HStack(spacing: 4) {
                        Text(gen.createdAt.relativeString)
                        if gen.costSEK > 0 {
                            Text("·")
                            Text(String(format: "%.2f kr", gen.costSEK))
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.5))
                }
                .padding(.horizontal, 8).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isSelected
                                    ? AnyShapeStyle(Color.accentNavi)
                                    : AnyShapeStyle(LinearGradient(
                                        colors: [.white.opacity(0.12), .white.opacity(0.04)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )),
                                lineWidth: isSelected ? 2 : 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            #if os(macOS)
            Button {
                if let url = manager.imageURL(for: gen) {
                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                }
            } label: {
                Label("Visa i Finder", systemImage: "folder")
            }
            #endif
            Button(role: .destructive) {
                Task { await manager.delete(gen) }
            } label: {
                Label("Radera", systemImage: "trash")
            }
        }
    }

    // MARK: - Controls Panel (macOS)

    private var controlsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                balanceBar
                modeSelector
                promptInput
                parameterControls
                costEstimate
                generateButton

                if !manager.activeGenerations.isEmpty {
                    activeGenerationsList
                }

                if let error = errorMessage {
                    errorBanner(error)
                }
            }
            .padding(20)
        }
        .background(Color.sidebarBackground)
    }

    // MARK: - Balance Bar

    private var balanceBar: some View {
        GlassCard(cornerRadius: 12, padding: 12) {
            HStack(spacing: 12) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.accentNavi)

                VStack(alignment: .leading, spacing: 2) {
                    Text("xAI Saldo")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    if manager.isLoadingBalance {
                        ProgressView().scaleEffect(0.6)
                    } else if let balance = manager.balance {
                        HStack(spacing: 8) {
                            Text(balance.formattedRemaining)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            Text("(\(balance.formattedRemainingInSEK))")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Ange xAI API-nyckel i Inställningar")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }

                Spacer()

                Button {
                    Task { await manager.refreshBalance() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Mode Selector

    private var modeSelector: some View {
        HStack(spacing: 0) {
            ForEach(MediaType.allCases, id: \.rawValue) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedMode = mode }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon).font(.system(size: 12))
                        Text(mode.displayName).font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedMode == mode ? Color.accentNavi.opacity(0.15) : Color.clear)
                    )
                    .foregroundColor(selectedMode == mode ? .accentNavi : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Prompt Input (macOS)

    private var promptInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Prompt")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text(selectedMode == .image
                         ? "Beskriv bilden du vill skapa…"
                         : "Beskriv videon du vill generera…")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.4))
                        .padding(.top, 12).padding(.leading, 12)
                }
                TextEditor(text: $prompt)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80, maxHeight: 160)
                    .padding(10)
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.userBubble)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.inputBorder, lineWidth: 0.5)
                    )
            )
        }
    }

    // MARK: - Parameter Controls

    @ViewBuilder
    private var parameterControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Parametrar")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            GlassCard(cornerRadius: 10, padding: 12) {
                switch selectedMode {
                case .image: imageParameters
                case .video: videoParameters
                }
            }
        }
    }

    private var imageParameters: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Storlek").font(.system(size: 13)).foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $imageSize) {
                    Text("1024×1024").tag("1024x1024")
                    Text("1792×1024").tag("1792x1024")
                    Text("1024×1792").tag("1024x1792")
                }
                .pickerStyle(.menu).font(.system(size: 12))
            }

            HStack {
                Text("Variationer: \(imageVariations)").font(.system(size: 13)).foregroundColor(.secondary)
                Spacer()
                Stepper("", value: $imageVariations, in: 1...4).labelsHidden()
            }

            Toggle("Pro-modell (grok-imagine-image-pro)", isOn: $useProModel)
                .font(.system(size: 13))
                .tint(.accentNavi)
        }
    }

    private var videoParameters: some View {
        Text("Video-generering via xAI — kommer snart")
            .font(.system(size: 13))
            .foregroundColor(.secondary.opacity(0.6))
            .italic()
    }

    // MARK: - Cost Estimate

    private var costEstimate: some View {
        let sek = estimateCostSEK()
        let usd = estimateCostUSD()

        return HStack(spacing: 8) {
            Image(systemName: "banknote").font(.system(size: 12)).foregroundColor(.accentNavi)
            Text("Uppskattad kostnad:").font(.system(size: 12)).foregroundColor(.secondary)
            Text(String(format: "%.2f kr", sek))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.accentNavi)
            Text("(\(String(format: "$%.3f", usd)))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentNavi.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentNavi.opacity(0.15), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        Button(action: generate) {
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView().scaleEffect(0.7).tint(.white)
                } else {
                    Image(systemName: "wand.and.stars").font(.system(size: 14, weight: .medium))
                }
                Text(isGenerating ? "Genererar…" : "Generera")
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(canGenerate ? Color.accentNavi : Color.secondary.opacity(0.3))
            )
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        .disabled(!canGenerate)
    }

    // MARK: - Active Generations List (macOS sidebar)

    private var activeGenerationsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pågående (\(manager.activeGenerations.count))")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            ForEach(manager.activeGenerations) { gen in
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.6)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(gen.displayTitle).font(.system(size: 12)).lineLimit(1)
                        Text(gen.status.displayName).font(.system(size: 10)).foregroundColor(.accentNavi)
                    }
                    Spacer()
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.accentNavi.opacity(0.2), lineWidth: 0.5)
                        )
                )
            }
        }
    }

    // MARK: - Gallery Panel (macOS)

    private var galleryPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Galleri").font(.system(size: 16, weight: .bold))
                Spacer()
                Text("\(manager.completedGenerations.count) objekt")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)

            ScrollView {
                galleryContent
            }
        }
        .background(Color.chatBackground)
    }

    // MARK: - Cost helpers

    private func estimateCostUSD() -> Double {
        switch selectedMode {
        case .image:
            return Double(imageVariations) * (useProModel ? 0.07 : 0.02)
        case .video:
            return 0.05
        }
    }

    private func estimateCostSEK() -> Double {
        estimateCostUSD() * ExchangeRateService.shared.usdToSEK
    }

    private var canGenerate: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !isGenerating
        && manager.canGenerate
        && KeychainManager.shared.xaiAPIKey?.isEmpty == false
    }

    // MARK: - Generate Action

    private func generate() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        errorMessage = nil
        isGenerating = true
        let model = useProModel ? "grok-imagine-image-pro" : "grok-imagine-image"

        Task {
            switch selectedMode {
            case .image:
                await manager.generateImage(
                    prompt: trimmed,
                    model: model,
                    size: imageSize,
                    variations: imageVariations
                )
            case .video:
                errorMessage = "Video-generering stöds ännu inte via xAI API."
            }
            isGenerating = false
            if errorMessage == nil { prompt = "" }
        }
    }
}

// MARK: - Safe subscript

fileprivate extension Collection where Index == Int {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#Preview("MediaView") {
    MediaView()
        .frame(width: 900, height: 600)
}
