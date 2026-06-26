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

/// Fully describes which radar imagery a timeline frame should draw. The
/// national mosaic is addressed by minutes-ago offset; a local frame is a
/// single IEM RIDGE volume scan ("0" timestamp = the live scan).
nonisolated enum RadarFrameSource: Equatable, Sendable {
    case national(minutesAgo: Int)
    case localSite(siteID: String, product: String, timestamp: String)

    /// Stable cache key. National frames and the live local scan are bucketed
    /// to the current 5-minute window (their imagery slides forward in time);
    /// archived local scans carry an absolute timestamp, so they never expire.
    var cacheToken: String {
        switch self {
        case .national(let minutesAgo):
            return "nat/\(RadarTileCache.epoch)/\(minutesAgo)"
        case .localSite(let siteID, let product, let timestamp):
            return timestamp == "0"
                ? "loc/\(siteID)/\(product)/0/\(RadarTileCache.epoch)"
                : "loc/\(siteID)/\(product)/\(timestamp)"
        }
    }
}

/// Builds IEM tile URLs for a given loop offset. Offset 0 = live frame.
nonisolated enum RadarTileURL {
    static func make(minutesAgo: Int, z: Int, x: Int, y: Int) -> URL? {
        make(source: .national(minutesAgo: minutesAgo), z: z, x: x, y: y)
    }

    static func make(source: RadarFrameSource, z: Int, x: Int, y: Int) -> URL? {
        switch source {
        case .national(let minutesAgo):
            let service = minutesAgo == 0
                ? "nexrad-n0q-900913"
                : String(format: "nexrad-n0q-900913-m%02dm", minutesAgo)
            return URL(string: "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/\(service)/\(z)/\(x)/\(y).png")
        case .localSite(let siteID, let product, let timestamp):
            // Live scan uses the short-cache endpoint; stable archived scans
            // use the 14-day-cache endpoint so the device caches them harder.
            let base = timestamp == "0"
                ? "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0"
                : "https://mesonet.agron.iastate.edu/c/tile.py/1.0.0"
            let layer = "ridge::\(siteID)-\(product)-\(timestamp)"
            return URL(string: "\(base)/\(layer)/\(z)/\(x)/\(y).png")
        }
    }
}

/// In-memory tile store shared by the timeline overlay and the cache
/// warmer, so each frame is fetched from the network once per 5-minute
/// window and every replay of the loop is instant.
nonisolated final class RadarTileCache: @unchecked Sendable {
    static let shared = RadarTileCache()

    private let cache = NSCache<NSString, NSData>()

    private init() {
        // Headroom for several loops at multiple zooms across both the
        // national mosaic and a local single-site site, so replays and
        // scope switches stay on cached tiles instead of the network.
        cache.countLimit = 2400
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    /// The IEM "-mXXm" services slide forward in time, so cached entries
    /// are bucketed to the 5-minute window they were fetched in and age
    /// out automatically when the window advances.
    static var epoch: Int {
        Int(Date().timeIntervalSince1970) / 300
    }

    // MARK: - Frame-source keyed access (national + local timeline)

    private func key(token: String, z: Int, x: Int, y: Int) -> NSString {
        "\(token)/\(z)/\(x)/\(y)" as NSString
    }

    func data(source: RadarFrameSource, z: Int, x: Int, y: Int) -> Data? {
        cache.object(forKey: key(token: source.cacheToken, z: z, x: x, y: y)) as Data?
    }

    func store(_ data: Data, source: RadarFrameSource, z: Int, x: Int, y: Int) {
        cache.setObject(
            data as NSData,
            forKey: key(token: source.cacheToken, z: z, x: x, y: y),
            cost: data.count
        )
    }

    // MARK: - Minutes-ago access (national composite tap inspector)

    func data(minutesAgo: Int, z: Int, x: Int, y: Int) -> Data? {
        data(source: .national(minutesAgo: minutesAgo), z: z, x: x, y: y)
    }

    func store(_ data: Data, minutesAgo: Int, z: Int, x: Int, y: Int) {
        store(data, source: .national(minutesAgo: minutesAgo), z: z, x: x, y: y)
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
    /// Bumped when local volume-scan timestamps resolve, so SwiftUI re-reads
    /// `currentSource` and the map swaps the single-site frame in.
    @Published private(set) var localScansVersion = 0

    private var animationTimer: Timer?
    private let frameInterval: TimeInterval = 0.55
    private var warmTask: Task<Void, Never>?
    private var lastWarmKey = ""

    // MARK: - Scope / local-site state
    //
    // The scrubber axis stays a list of minutes-ago offsets for both scopes.
    // In local scope each offset is resolved to a single-site IEM RIDGE
    // volume-scan timestamp so the loop animates the local radar instead of
    // the national mosaic.
    private var scope: RadarScope = .national
    private var localSiteID: String?
    private var localProduct: String = "N0B"
    private var localTimestamps: [Int: String] = [:]
    private var scanLoadTask: Task<Void, Never>?

    /// Point RadarView calls whenever the scope, active site, or product
    /// changes. Reloads the local volume-scan timestamps when needed.
    func configure(scope: RadarScope, siteID: String?, product: String) {
        let changed = scope != self.scope
            || siteID != localSiteID
            || product != localProduct
        self.scope = scope
        self.localSiteID = siteID
        self.localProduct = product
        guard changed else { return }
        if scope == .local, siteID != nil {
            loadLocalScans()
        } else {
            scanLoadTask?.cancel()
            localTimestamps = [:]
        }
    }

    /// The imagery source for a given scrubber offset.
    func source(forOffset offset: Int) -> RadarFrameSource {
        if scope == .local, let siteID = localSiteID {
            let timestamp = offset == 0 ? "0" : (localTimestamps[offset] ?? "0")
            return .localSite(siteID: siteID, product: localProduct, timestamp: timestamp)
        }
        return .national(minutesAgo: offset)
    }

    /// Source for the frame currently under the scrubber.
    var currentSource: RadarFrameSource { source(forOffset: minutesAgo) }

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
        // The loop window changed, so the local timestamp map must be rebuilt.
        if scope == .local, localSiteID != nil { loadLocalScans() }
    }

    // MARK: - Local single-site volume scans

    /// IEM's list service emits and accepts minute-resolution UTC stamps with
    /// no seconds ("2026-06-24T16:03Z"), which ISO8601DateFormatter rejects —
    /// so parse and format with an explicit UTC pattern.
    private static let scanQueryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        return formatter
    }()

    private static let scanTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMddHHmm"
        return formatter
    }()

    /// Fetches the recent volume-scan times for the active site/product and
    /// maps each loop offset to the nearest available scan, so a local loop
    /// animates real single-site frames.
    private func loadLocalScans() {
        guard let siteID = localSiteID else { return }
        let product = localProduct
        let offsets = frames.filter { $0 > 0 }
        let windowMinutes = (offsets.max() ?? 30) + 10

        scanLoadTask?.cancel()
        scanLoadTask = Task { [weak self] in
            let now = Date()
            let start = now.addingTimeInterval(-Double(windowMinutes) * 60)
            let startText = Self.scanQueryFormatter.string(from: start)
            let endText = Self.scanQueryFormatter.string(from: now)
            var components = URLComponents(string: "https://mesonet.agron.iastate.edu/json/radar.py")!
            components.queryItems = [
                URLQueryItem(name: "operation", value: "list"),
                URLQueryItem(name: "radar", value: siteID),
                URLQueryItem(name: "product", value: product),
                URLQueryItem(name: "start", value: startText),
                URLQueryItem(name: "end", value: endText)
            ]
            guard let url = components.url,
                  let (data, response) = try? await NetworkSessions.api.data(for: URLRequest(url: url)),
                  let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
                  let payload = try? JSONDecoder().decode(RadarScanList.self, from: data) else {
                return
            }

            let scans: [(date: Date, stamp: String)] = payload.scans.compactMap { scan in
                guard let date = Self.scanQueryFormatter.date(from: scan.ts) else { return nil }
                return (date, Self.scanTimestampFormatter.string(from: date))
            }
            guard !scans.isEmpty, !Task.isCancelled else { return }

            var mapping: [Int: String] = [:]
            for offset in offsets {
                let target = now.addingTimeInterval(-Double(offset) * 60)
                if let nearest = scans.min(by: {
                    abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target))
                }) {
                    mapping[offset] = nearest.stamp
                }
            }

            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.localTimestamps = mapping
                self.lastWarmKey = ""          // force a re-warm for the new frames
                self.localScansVersion &+= 1   // nudge SwiftUI to re-read currentSource
            }
        }
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

        // Resolve every frame to its imagery source (national offset or local
        // single-site scan) up front, on the main actor.
        let sources = frames.map { source(forOffset: $0) }

        // The scrubber calls this on every drag tick — don't cancel and
        // restart an identical in-flight warm pass. The scope token makes a
        // national↔local switch (or a new scan set) re-warm.
        let scopeKey = sources.first?.cacheToken ?? "none"
        let key = "\(RadarTileCache.epoch)|\(zoom)|\(tiles.first!.x),\(tiles.first!.y)-\(tiles.count)|\(loopDuration.rawValue)|\(scopeKey)"
        guard key != lastWarmKey else { return }
        lastWarmKey = key

        warmTask?.cancel()

        warmTask = Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: Void.self) { group in
                for source in sources {
                    for tile in tiles {
                        group.addTask {
                            guard !Task.isCancelled else { return }
                            let cache = RadarTileCache.shared
                            guard cache.data(source: source, z: zoom, x: tile.x, y: tile.y) == nil,
                                  let url = RadarTileURL.make(source: source, z: zoom, x: tile.x, y: tile.y) else { return }
                            if let (data, response) = try? await NetworkSessions.tiles.data(for: URLRequest(url: url)),
                               let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode {
                                cache.store(data, source: source, z: zoom, x: tile.x, y: tile.y)
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
        scanLoadTask?.cancel()
    }
}

/// IEM `json/radar.py?operation=list` response: `{"scans": [{"ts": "...Z"}]}`.
private struct RadarScanList: Decodable {
    struct Scan: Decodable { let ts: String }
    let scans: [Scan]
}
