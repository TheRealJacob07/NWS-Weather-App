import Foundation
import CoreLocation
import UIKit

/// RadarScope-style tap inspection: samples the composite radar tile at the
/// tapped coordinate and estimates reflectivity from the pixel color.
nonisolated enum RadarTapInspector {
    /// Estimated dBZ at a coordinate for the given loop frame, or nil when
    /// there's no precipitation there.
    static func estimateDBZ(
        at coordinate: CLLocationCoordinate2D,
        minutesAgo: Int,
        zoom requestedZoom: Int
    ) async -> Double? {
        // Inspect at a detail-friendly zoom regardless of how far out the
        // map is — composite data tops out around z10.
        let zoom = min(max(requestedZoom, 6), 10)

        // Web Mercator coordinate → tile + in-tile pixel.
        let n = pow(2.0, Double(zoom))
        let xNorm = (coordinate.longitude + 180.0) / 360.0
        let latRad = coordinate.latitude * .pi / 180.0
        let yNorm = (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0
        guard xNorm >= 0, xNorm < 1, yNorm >= 0, yNorm < 1 else { return nil }

        let tileX = Int(xNorm * n)
        let tileY = Int(yNorm * n)
        let pixelX = Int((xNorm * n - Double(tileX)) * 256.0)
        let pixelY = Int((yNorm * n - Double(tileY)) * 256.0)

        // Cached tile if available, otherwise a one-off fetch.
        var tileData = RadarTileCache.shared.data(minutesAgo: minutesAgo, z: zoom, x: tileX, y: tileY)
        if tileData == nil,
           let url = RadarTileURL.make(minutesAgo: minutesAgo, z: zoom, x: tileX, y: tileY),
           let (data, response) = try? await NetworkSessions.tiles.data(for: URLRequest(url: url)),
           let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode {
            RadarTileCache.shared.store(data, minutesAgo: minutesAgo, z: zoom, x: tileX, y: tileY)
            tileData = data
        }

        guard let tileData, let cgImage = UIImage(data: tileData)?.cgImage else { return nil }
        guard let pixel = samplePixel(in: cgImage, x: pixelX, y: pixelY) else { return nil }

        // Transparent → no precipitation at that point.
        guard pixel.alpha >= 32 else { return nil }

        var red = pixel.red, green = pixel.green, blue = pixel.blue
        if pixel.alpha < 255 {
            red = min(255, red * 255 / pixel.alpha)
            green = min(255, green * 255 / pixel.alpha)
            blue = min(255, blue * 255 / pixel.alpha)
        }

        let dbz = ReflectivityScale.dbz(red: red, green: green, blue: blue)
        return dbz < 0 ? nil : dbz
    }

    private struct Pixel {
        let red: Int, green: Int, blue: Int, alpha: Int
    }

    private static func samplePixel(in image: CGImage, x: Int, y: Int) -> Pixel? {
        let width = image.width, height = image.height
        guard x >= 0, x < width, y >= 0, y < height else { return nil }

        guard let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Draw so the target pixel lands in our 1×1 context.
        context.draw(image, in: CGRect(x: -x, y: -(height - 1 - y), width: width, height: height))
        guard let data = context.data else { return nil }

        let bytes = data.assumingMemoryBound(to: UInt8.self)
        return Pixel(red: Int(bytes[0]), green: Int(bytes[1]), blue: Int(bytes[2]), alpha: Int(bytes[3]))
    }
}
