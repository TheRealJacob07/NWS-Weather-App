import Foundation
import MapKit
internal import Combine

/// How far back the radar time-lapse loop reaches. IEM publishes archived
/// national composite tiles at 5-minute steps for the past 50 minutes
/// (services "nexrad-n0q-900913-m05m" … "-m50m"); the bare service is the
/// live frame. Verified: each step serves a distinct image.
enum RadarLoopDuration: String, CaseIterable, Identifiable {
    case thirtyMinutes
    case fiftyMinutes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thirtyMinutes: return "30 min"
        case .fiftyMinutes: return "50 min"
        }
    }

    /// Minutes-ago offsets ordered oldest → newest. Last entry is 0 ("now").
    var minuteOffsets: [Int] {
        switch self {
        case .thirtyMinutes: return Array(stride(from: 30, through: 0, by: -5))
        case .fiftyMinutes: return Array(stride(from: 50, through: 0, by: -5))
        }
    }
}

/// Builds IEM tile URLs for a given loop offset. Offset 0 = live frame.
nonisolated enum RadarTileURL {
    static func make(minutesAgo: Int, z: Int, x: Int, y: Int) -> URL? {
        let service = minutesAgo == 0
            ? "nexrad-n0q-900913"
            : String(format: "nexrad-n0q-900913-m%02dm", minutesAgo)
        return URL(string: "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/\(service)/\(z)/\(x)/\(y).png")
    }
}

/// In-memory tile store shared by the timeline overlay and the cache
/// warmer, so each frame is fetched from the network once per 5-minute
/// window and every replay of the loop is instant.
nonisolated final class RadarTileCache: @unchecked Sendable {
    static let shared = RadarTileCache()

    private let cache = NSCache<NSString, NSData>()

    private init() {
        cache.countLimit = 1200
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    /// The IEM "-mXXm" services slide forward in time, so cached entries
    /// are bucketed to the 5-minute window they were fetched in and age
    /// out automatically when the window advances.
    private static var epoch: Int {
        Int(Date().timeIntervalSince1970) / 300
    }

    private func key(minutesAgo: Int, z: Int, x: Int, y: Int) -> NSString {
        "\(Self.epoch)/\(minutesAgo)/\(z)/\(x)/\(y)" as NSString
    }

    func data(minutesAgo: Int, z: Int, x: Int, y: Int) -> Data? {
        cache.object(forKey: key(minutesAgo: minutesAgo, z: z, x: x, y: y)) as Data?
    }

    func store(_ data: Data, minutesAgo: Int, z: Int, x: Int, y: Int) {
        cache.setObject(
            data as NSData,
            forKey: key(minutesAgo: minutesAgo, z: z, x: x, y: y),
            cost: data.count
        )
    }
}

/// Drives the always-visible radar timeline. Frames are addressed by
/// minutes-ago offset; tiles stream in on demand at whatever zoom MapKit
/// requests, backed by RadarTileCache.
@MainActor
final class RadarTimelineController: ObservableObject {
    @Published private(set) var frames: [Int] = RadarLoopDuration.thirtyMinutes.minuteOffsets
    @Published var position: Int = RadarLoopDuration.thirtyMinutes.minuteOffsets.count - 1
    @Published var isPlaying = false
    @Published var loopDuration: RadarLoopDuration = .thirtyMinutes {
        didSet { rebuildFrames() }
    }
    @Published var playbackSpeed: Double = 1.0 {
        didSet { if isPlaying { scheduleTimer() } }
    }

    private var animationTimer: Timer?
    private let frameInterval: TimeInterval = 0.55
    private var warmTask: Task<Void, Never>?
    private var lastWarmKey = ""

    /// Minutes-ago offset for the current scrubber position.
    var minutesAgo: Int {
        frames.indices.contains(position) ? frames[position] : 0
    }

    /// True when parked on the newest frame and paused — the map shows the
    /// live, full-quality WMS product instead of the loop frame.
    var isLive: Bool {
        position == frames.count - 1 && !isPlaying
    }

    var currentFrameLabel: String {
        let ago = minutesAgo
        if ago == 0 { return isPlaying ? "Now" : "Live" }
        return "\(ago) min ago"
    }

    // MARK: - Playback

    func play(visibleMapRect: MKMapRect, zoom: Int) {
        guard !isPlaying else { return }
        warmCache(visibleMapRect: visibleMapRect, zoom: zoom)
        if position == frames.count - 1 { position = 0 }
        isPlaying = true
        scheduleTimer()
    }

    /// All mutators dedupe their @Published writes: the scrubber's drag
    /// gesture calls pause()/seek() on every tick, and redundant
    /// objectWillChange storms make glassEffect update multiple times per
    /// frame — which crashes the Metal renderer (MTLStoreActionMultisampleResolve
    /// assertion). Only publish when state actually changes.
    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        animationTimer?.invalidate()
        animationTimer = nil
    }

    func seek(to index: Int) {
        let clamped = max(0, min(index, frames.count - 1))
        guard clamped != position else { return }
        position = clamped
    }

    func backToLive() {
        pause()
        let live = frames.count - 1
        guard position != live else { return }
        position = live
    }

    /// Warm the cache for scrubbing even before the first play.
    func prepare(visibleMapRect: MKMapRect, zoom: Int) {
        warmCache(visibleMapRect: visibleMapRect, zoom: zoom)
    }

    private func advance() {
        guard !frames.isEmpty else { return }
        position = (position + 1) % frames.count
    }

    private func rebuildFrames() {
        let wasLive = isLive
        pause()
        frames = loopDuration.minuteOffsets
        position = wasLive ? frames.count - 1 : 0
    }

    private func scheduleTimer() {
        animationTimer?.invalidate()
        let interval = frameInterval / max(0.5, playbackSpeed)
        animationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.advance() }
        }
    }

    // MARK: - Cache warming

    /// Fire-and-forget: pulls every loop frame's visible tiles into
    /// RadarTileCache so playback is smooth from the first pass.
    private func warmCache(visibleMapRect: MKMapRect, zoom: Int) {
        let tiles = Self.visibleTiles(in: visibleMapRect, zoom: zoom)
        guard !tiles.isEmpty, tiles.count <= 64 else { return }

        // The scrubber calls this on every drag tick — don't cancel and
        // restart an identical in-flight warm pass.
        let epoch = Int(Date().timeIntervalSince1970) / 300
        let key = "\(epoch)|\(zoom)|\(tiles.first!.x),\(tiles.first!.y)-\(tiles.count)|\(loopDuration.rawValue)"
        guard key != lastWarmKey else { return }
        lastWarmKey = key

        warmTask?.cancel()
        let offsets = frames

        warmTask = Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: Void.self) { group in
                for minutesAgo in offsets {
                    for tile in tiles {
                        group.addTask {
                            guard !Task.isCancelled else { return }
                            let cache = RadarTileCache.shared
                            guard cache.data(minutesAgo: minutesAgo, z: zoom, x: tile.x, y: tile.y) == nil,
                                  let url = RadarTileURL.make(minutesAgo: minutesAgo, z: zoom, x: tile.x, y: tile.y) else { return }
                            if let (data, response) = try? await NetworkSessions.tiles.data(for: URLRequest(url: url)),
                               let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode {
                                cache.store(data, minutesAgo: minutesAgo, z: zoom, x: tile.x, y: tile.y)
                            }
                        }
                    }
                }
            }
        }
    }

    nonisolated static func visibleTiles(in mapRect: MKMapRect, zoom: Int) -> [(x: Int, y: Int)] {
        let worldWidth = MKMapSize.world.width
        let scale = pow(2.0, Double(zoom)) / worldWidth
        let tileCount = Int(pow(2.0, Double(zoom)))
        let minX = max(0, Int(floor(mapRect.minX * scale)))
        let maxX = min(tileCount - 1, Int(floor((mapRect.maxX - 1) * scale)))
        let minY = max(0, Int(floor(mapRect.minY * scale)))
        let maxY = min(tileCount - 1, Int(floor((mapRect.maxY - 1) * scale)))
        guard minX <= maxX, minY <= maxY else { return [] }
        return (minX...maxX).flatMap { x in (minY...maxY).map { y in (x, y) } }
    }

    deinit {
        animationTimer?.invalidate()
        warmTask?.cancel()
    }
}
