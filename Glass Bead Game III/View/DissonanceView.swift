//
//  DissonanceView.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 4/19/23.
//
//  Renders the roughness/dissonance field (see GBGCore's Dissonance.swift for the math)
//  as a background layer under the grid/diamonds: for every point on the graph, how rough
//  would the root+X+Y triad sound if you played there? The diamonds mark the exact,
//  precise consonances; this fills in what's happening in between them.
//
//  True per-pixel resolution as of 2026-08-28 (Norm: a fixed grid still showed visible
//  pixelation once seen at full size) - one roughness value per screen pixel, not a coarse
//  grid stretched to fit. Measured on this Mac at limit 11, ~900px canvas, Release build:
//  ~305ms to compute the grid + build the bitmap - a real, noticeable one-time cost, but
//  cached (see below) so it's paid once per meaningful change, not per frame or per touch.
//  Measure performance-sensitive code like this in Release, not Debug - the same computation
//  measured ~17s in an unoptimized Debug build (-Onone vs -O on tight closure-heavy numeric
//  loops is roughly a 50x difference here), which looks like a hang/regression but isn't one.
//
//  Rendered as a single bitmap image, not one Path fill per cell - at true per-pixel
//  resolution that's 800000+ individual fills, a completely different (and much worse)
//  performance class than the grid math itself. This is also exactly how the tuning
//  artifact's own high-resolution preview rendered (context.draw(image, in:)) - and that
//  artifact's own bugnote is the reason the vertical flip below is handled explicitly by
//  writing rows in the correct order while building the pixel buffer, not via a context
//  transform: it documented losing X=Y mirror symmetry once from exactly this mistake, using
//  a raw unflipped CGBitmapContext where row 0 lands at the top instead of the bottom.

import SwiftUI
import CoreGraphics

struct DissonanceView: View {
    let scale: Scale
    @ObservedObject var settings: AppSettings
    let showDissonance: Bool

    // The grid/image only actually depend on root/limit/weighting/scale-shape/canvas size -
    // none of which change on a plain touch - but this View now correctly redraws on every
    // settings change (including xFrequency/yFrequency, published on every touch-move frame)
    // since fixing GraphView's missing @ObservedObject. Without this cache, that would mean
    // rebuilding the whole per-pixel bitmap on every touch-move frame. A plain class (not
    // @State itself) so it can be mutated freely from inside the Canvas closure without
    // tripping SwiftUI's "modifying state during view update" - @State only needs to keep the
    // box reference itself stable, not track what's inside it.
    @State private var cache = ImageCache()

    private final class ImageCache {
        var key: CacheKey?
        var image: CGImage?
    }

    private struct CacheKey: Equatable {
        let rootFrequency: Double
        let limit: Int
        let highestRatio: Double
        let lowestRatio: Double
        let resolution: Int
    }

    var body: some View {
        if showDissonance {
            Canvas { context, size in
                guard let limit = limitMap[settings.selectedLimit], limit > 0 else { return }
                // Square canvas (the graph is always aspectRatio 1:1) - one grid cell per pixel.
                let resolution = max(1, Int(size.width.rounded()))

                let key = CacheKey(
                    rootFrequency: settings.rootFrequency,
                    limit: limit,
                    highestRatio: scale.highestRatio,
                    lowestRatio: scale.lowestRatio,
                    resolution: resolution
                )

                let image: CGImage
                if cache.key == key, let cachedImage = cache.image {
                    image = cachedImage
                } else {
                    // Always linear falloff (1.0 at the fundamental down to 1/limit at the
                    // highest included harmonic) - was a user-facing toggle against the 1/n
                    // alternative, but linear reveals visibly more structure and was always the
                    // default; Norm decided it's not worth the UI real estate as a choice.
                    let grid = Dissonance.roughnessGrid(
                        scale: scale,
                        rootFrequency: settings.rootFrequency,
                        limit: limit,
                        resolution: resolution,
                        weighting: { Dissonance.linearHarmonicWeight($0, limit: limit) }
                    )
                    guard let maxRoughness = grid.flatMap({ $0 }).max(), maxRoughness > 0,
                          let built = makeRoughnessImage(grid: grid, maxRoughness: maxRoughness, resolution: resolution)
                    else { return }
                    image = built
                    cache.key = key
                    cache.image = image
                }

                context.draw(Image(decorative: image, scale: 1), in: CGRect(origin: .zero, size: size))
            }
        }
    }

    // Tone curve replacing the earlier plain gamma-0.5 power curve (2026-08-28): that curve
    // lifted shadows well but left highlights reading as "too bright for too long" - too much
    // of the upper range saturated toward full intensity. Tuned interactively against the
    // real field data in the "Dissonance Curve" artifact (a draggable 5-point curve, same
    // Catmull-Rom shape as here) and ported directly - these are exactly the y values chosen
    // there, still lifting shadows above a straight line but pulling back from gamma 0.5's
    // more aggressive lift, giving highlights more room to separate before they saturate.
    private static let curveXs: [Double] = [0, 0.25, 0.5, 0.75, 1.0]
    private static let curveYs: [Double] = [0.0, 0.443, 0.646, 0.805, 1.0]

    private static func toneCurve(_ x: Double) -> Double {
        let clampedX = min(max(x, 0), 1)
        var i = 0
        while i < curveXs.count - 2 && clampedX > curveXs[i + 1] { i += 1 }
        let y0 = curveYs[max(i - 1, 0)]
        let y1 = curveYs[i]
        let y2 = curveYs[i + 1]
        let y3 = curveYs[min(i + 2, curveYs.count - 1)]
        let span = curveXs[i + 1] - curveXs[i]
        let t = span == 0 ? 0 : (clampedX - curveXs[i]) / span
        let t2 = t * t, t3 = t2 * t
        let v = 0.5 * ((2 * y1) + (-y0 + y2) * t + (2 * y0 - 5 * y1 + 4 * y2 - y3) * t2 + (-y0 + 3 * y1 - 3 * y2 + y3) * t3)
        return min(max(v, 0), 1)
    }

    // 256-entry lookup table, built once per image (not per pixel) - toneCurve's short while
    // loop is cheap, but this is still hundreds of thousands of calls at true per-pixel
    // resolution, so precomputing once and looking up by quantized input is worth it.
    private static let toneCurveLUT: [Double] = (0...255).map { toneCurve(Double($0) / 255) }

    // Builds the field as a single RGBA8 bitmap, one pixel per grid cell - straight (not
    // premultiplied) alpha, matching how the bytes are written below. row 0 of `grid` is the
    // lowest pitch (bottom of the graph, same convention as Graph/DiamondView/HitTestView),
    // so it's written into the LAST image row here - the image's own row 0 is its top when
    // drawn normally, so this is the explicit flip (see the header comment on why this isn't
    // left to a context transform instead).
    private func makeRoughnessImage(grid: [[Double]], maxRoughness: Double, resolution: Int) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: resolution * resolution * 4)
        pixels.withUnsafeMutableBufferPointer { buffer in
            for gridRow in 0..<resolution {
                let imageRow = resolution - 1 - gridRow
                let rowStart = imageRow * resolution * 4
                for col in 0..<resolution {
                    let normalizedRoughness = grid[gridRow][col] / maxRoughness
                    let lutIndex = min(255, max(0, Int((normalizedRoughness * 255).rounded())))
                    let t = Self.toneCurveLUT[lutIndex]
                    let idx = rowStart + col * 4
                    buffer[idx] = UInt8(clamping: Int((t * 255).rounded()))
                    buffer[idx + 1] = UInt8(clamping: Int((t * 0.35 * 255).rounded()))
                    buffer[idx + 2] = UInt8(clamping: Int((t * 0.15 * 255).rounded()))
                    buffer[idx + 3] = UInt8(clamping: Int((t * 0.9 * 255).rounded()))
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: resolution,
            height: resolution,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: resolution * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
