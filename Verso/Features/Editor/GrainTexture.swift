import CoreGraphics
import SwiftUI

/// A small deterministic noise tile, generated once and tiled across the page.
///
/// Generated rather than shipped as an asset so it costs no bundle space and
/// scales with the device. Deterministic so the paper looks the same on every
/// launch and on every device — grain that reshuffles between launches reads as
/// a rendering bug.
@MainActor
enum GrainTexture {

    private static let tileSize = 128

    /// A cheap, fully deterministic PRNG. Quality is irrelevant here; the only
    /// requirement is that the same seed gives the same paper.
    private struct Noise {
        private var state: UInt64

        init(seed: UInt64) { self.state = seed }

        mutating func next() -> UInt8 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt8(truncatingIfNeeded: state >> 33)
        }
    }

    private static func makeTile() -> CGImage? {
        let side = tileSize
        var pixels = [UInt8](repeating: 0, count: side * side)
        var noise = Noise(seed: 0x5EED_C0FFEE)

        for index in pixels.indices {
            // Two samples averaged pull the distribution toward mid-grey, so
            // the texture reads as fibre rather than salt and pepper.
            let a = Int(noise.next())
            let b = Int(noise.next())
            pixels[index] = UInt8((a + b) / 2)
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    static let tile: Image? = makeTile().map { Image(decorative: $0, scale: 2) }
}

/// The paper texture. Intensity comes from the theme, and is already zero when
/// Increase Contrast or Reduce Transparency is on — `Theme.resolved` handles
/// that, so this view has no accessibility branch of its own.
struct GrainOverlay: View {
    let intensity: Double

    var body: some View {
        if intensity > 0, let tile = GrainTexture.tile {
            tile
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .opacity(intensity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
