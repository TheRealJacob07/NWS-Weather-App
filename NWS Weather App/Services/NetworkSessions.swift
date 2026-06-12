import Foundation

/// Shared URLSessions with tuned caches so repeated map pans, forecast
/// refreshes, and product image loads hit the local cache instead of the
/// network. `nonisolated` because tile loads call in from MapKit's
/// background queues (the project defaults to MainActor isolation).
nonisolated enum NetworkSessions {
    /// API calls (api.weather.gov etc.) — modest cache, honors server headers.
    static let api: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 40 * 1024 * 1024)
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = [
            "User-Agent": "NWS Weather App (jaseastrunk@gmail.com)"
        ]
        return URLSession(configuration: config)
    }()

    /// Radar/lightning tiles and NOAA product imagery — larger cache and
    /// more parallelism. Radar frames change every ~5 minutes, so cached
    /// tiles age out naturally via server cache headers.
    static let tiles: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 24 * 1024 * 1024, diskCapacity: 120 * 1024 * 1024)
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 25
        config.httpMaximumConnectionsPerHost = 8
        config.httpAdditionalHeaders = [
            "User-Agent": "NWS Weather App (jaseastrunk@gmail.com)"
        ]
        return URLSession(configuration: config)
    }()
}
