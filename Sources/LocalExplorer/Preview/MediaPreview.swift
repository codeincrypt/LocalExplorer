import AppKit
import AVFoundation
import AVKit
import SwiftUI
import ExplorerCore

struct MediaPreviewProvider: PreviewProvider {
    let kind: PreviewKind
    func makeView(_ context: PreviewContext) -> AnyView {
        AnyView(MediaPreview(item: context.item, style: context.style, isAudio: kind == .audio, open: context.open))
    }
}

/// AVFoundation playback for one file. Playability is checked before a player is
/// created, so unsupported codecs get a clear message instead of a black view. The
/// player and its item are released when the preview goes away.
@MainActor
final class MediaPlayerController: ObservableObject {
    enum LoadState: Equatable {
        case loading, ready
        case failed(String)
    }

    struct Option: Identifiable, Hashable {
        let id: Int
        let title: String
    }

    static let speeds: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    let playerView = AVPlayerView()
    @Published private(set) var state: LoadState = .loading
    @Published private(set) var speed: Float = 1
    @Published private(set) var audioOptions: [Option] = []
    @Published private(set) var subtitleOptions: [Option] = []
    @Published private(set) var selectedAudio: Int?
    @Published private(set) var selectedSubtitle: Int?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var title: String?
    @Published private(set) var artist: String?
    @Published private(set) var duration: Double?

    private var player: AVPlayer?
    private var audible: AVMediaSelectionGroup?
    private var legible: AVMediaSelectionGroup?

    func configure(isAudio: Bool, style: PreviewStyle) {
        playerView.controlsStyle = (isAudio || style == .compact) ? .inline : .floating
        playerView.showsFullScreenToggleButton = !isAudio
        playerView.allowsPictureInPicturePlayback = false
        playerView.showsSharingServiceButton = false
        playerView.videoGravity = .resizeAspect
    }

    func load(url: URL) async {
        let asset = AVURLAsset(url: url)
        do {
            let (playable, time) = try await asset.load(.isPlayable, .duration)
            guard !Task.isCancelled else { return }
            guard playable else {
                state = .failed("macOS can’t play this file. Its codec or container isn’t supported by AVFoundation.")
                return
            }
            duration = time.seconds.isFinite ? time.seconds : nil
            audible = try? await asset.loadMediaSelectionGroup(for: .audible)
            legible = try? await asset.loadMediaSelectionGroup(for: .legible)
            audioOptions = (audible?.options ?? []).enumerated().map { Option(id: $0.offset, title: $0.element.displayName) }
            subtitleOptions = (legible?.options ?? []).enumerated().map { Option(id: $0.offset, title: $0.element.displayName) }
            await loadMetadata(asset)
            guard !Task.isCancelled else { return }

            let item = AVPlayerItem(asset: asset)
            if let audible, let option = item.currentMediaSelection.selectedMediaOption(in: audible) {
                selectedAudio = audible.options.firstIndex(of: option)
            }
            if let legible, let option = item.currentMediaSelection.selectedMediaOption(in: legible) {
                selectedSubtitle = legible.options.firstIndex(of: option)
            }
            let player = AVPlayer(playerItem: item)
            player.actionAtItemEnd = .pause
            self.player = player
            playerView.player = player
            state = .ready
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed("This file couldn’t be read as media. It may be damaged. (\(error.localizedDescription))")
        }
    }

    private func loadMetadata(_ asset: AVAsset) async {
        guard let items = try? await asset.load(.commonMetadata) else { return }
        for item in items {
            let key = item.commonKey
            if key == .commonKeyArtwork {
                // `try?` flattens the optional result to `Data?`.
                if let data = try? await item.load(.dataValue), let image = NSImage(data: data) { artwork = image }
            } else if key == .commonKeyTitle {
                if let loaded = try? await item.load(.stringValue) { title = loaded }
            } else if key == .commonKeyArtist {
                if let loaded = try? await item.load(.stringValue) { artist = loaded }
            }
        }
    }

    func setSpeed(_ value: Float) {
        speed = value
        guard let player else { return }
        player.defaultRate = value
        if player.rate != 0 { player.rate = value }
    }

    func selectAudio(_ index: Int) {
        guard let audible, audible.options.indices.contains(index) else { return }
        player?.currentItem?.select(audible.options[index], in: audible)
        selectedAudio = index
    }

    /// `nil` turns subtitles off.
    func selectSubtitle(_ index: Int?) {
        guard let legible else { return }
        let option = index.flatMap { legible.options.indices.contains($0) ? legible.options[$0] : nil }
        player?.currentItem?.select(option, in: legible)
        selectedSubtitle = index
    }

    func togglePlayback() {
        guard let player else { return }
        if player.rate == 0 { player.playImmediately(atRate: speed) } else { player.pause() }
    }

    func release() {
        player?.pause()
        playerView.player = nil
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
}

private struct MediaPreview: View {
    let item: FileItem
    let style: PreviewStyle
    let isAudio: Bool
    let open: () -> Void
    @StateObject private var media = MediaPlayerController()
    @Environment(\.glass) private var glass

    var body: some View {
        Group {
            switch media.state {
            case .failed(let message):
                PreviewMessageView(item: item, title: "Can’t play “\(item.name)”", message: message, open: open, compact: style == .compact)
            case .loading:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready:
                if isAudio { audioLayout } else { videoLayout }
            }
        }
        .task(id: item.id) {
            media.configure(isAudio: isAudio, style: style)
            await media.load(url: item.url)
        }
        .onDisappear { media.release() }
    }

    private var videoLayout: some View {
        VStack(spacing: 8) {
            PlayerViewRepresentable(view: media.playerView)
                .accessibilityLabel("Video player for \(item.name)")
            if style == .full { optionsBar }
        }
        .padding(style == .full ? 8 : 0)
    }

    private var audioLayout: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Group {
                if let artwork = media.artwork {
                    Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: glass.shadow, radius: 10, y: 4)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(glass.controlFill)
                        Image(systemName: "waveform")
                            .font(.system(size: style == .full ? 64 : 40, weight: .light))
                            .foregroundStyle(glass.secondaryText)
                    }
                    .aspectRatio(1, contentMode: .fit)
                }
            }
            .frame(maxWidth: style == .full ? 280 : 150, maxHeight: style == .full ? 280 : 150)
            if style == .full || media.title != nil {
                VStack(spacing: 2) {
                    Text(media.title ?? item.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let artist = media.artist {
                        Text(artist).font(.system(size: 11)).foregroundStyle(glass.secondaryText).lineLimit(1)
                    }
                }
            }
            PlayerViewRepresentable(view: media.playerView)
                .frame(height: 44)
                .frame(maxWidth: 480)
                .accessibilityLabel("Audio player for \(item.name)")
            if style == .full { optionsBar }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var optionsBar: some View {
        PreviewControlBar {
            Menu {
                ForEach(MediaPlayerController.speeds, id: \.self) { value in
                    Button { media.setSpeed(value) } label: {
                        if media.speed == value { Label(speedTitle(value), systemImage: "checkmark") } else { Text(speedTitle(value)) }
                    }
                }
            } label: {
                Label(speedTitle(media.speed), systemImage: "gauge.with.dots.needle.33percent")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 6)
            .help("Playback speed")

            if media.audioOptions.count > 1 {
                Menu {
                    ForEach(media.audioOptions) { option in
                        Button { media.selectAudio(option.id) } label: {
                            if media.selectedAudio == option.id { Label(option.title, systemImage: "checkmark") } else { Text(option.title) }
                        }
                    }
                } label: {
                    Label("Audio", systemImage: "speaker.wave.2")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 6)
                .help("Audio track")
            }
            if !media.subtitleOptions.isEmpty {
                Menu {
                    Button { media.selectSubtitle(nil) } label: {
                        if media.selectedSubtitle == nil { Label("Off", systemImage: "checkmark") } else { Text("Off") }
                    }
                    Divider()
                    ForEach(media.subtitleOptions) { option in
                        Button { media.selectSubtitle(option.id) } label: {
                            if media.selectedSubtitle == option.id { Label(option.title, systemImage: "checkmark") } else { Text(option.title) }
                        }
                    }
                } label: {
                    Label("Subtitles", systemImage: "captions.bubble")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 6)
                .help("Subtitles")
            }
            if let duration = media.duration {
                Text(DisplayFormat.duration(duration))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(glass.secondaryText)
                    .padding(.horizontal, 6)
            }
        }
    }

    private func speedTitle(_ value: Float) -> String {
        String(format: "%g×", value)
    }
}

struct PlayerViewRepresentable: NSViewRepresentable {
    let view: AVPlayerView
    func makeNSView(context: Context) -> AVPlayerView { view }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}
