//
//  DissonanceView.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 4/19/23.
//
//  Renders the roughness/dissonance field (see GBGCore's Dissonance.swift for the math)
//  as a background layer under the grid/diamonds: for every point on the graph, how rough
//  would the root+X+Y+Z tetrad sound if you played there? The diamonds mark the exact,
//  precise consonances; this fills in what's happening in between them.
//
//  Half-pixel resolution while settings.zDragActive is true (Norm: "2x pixel to save time") -
//  one roughness value per 2x2 screen pixel block, upscaled by context.draw's own
//  interpolation, not one per screen pixel. Backed off from the true per-pixel resolution
//  added 2026-08-28 once Z joined the cache key: Z can now change continuously (a Z-slider
//  drag), not just on the occasional root/limit/scale-shape change, so the O(resolution^2)
//  grid cost needed to come down to match while that's happening.
//
//  Progressive refinement as of 2026-08-29 (Norm: "when the dragging stops for a moment can
//  we render in three more passes to fill in data? If dragging resumes stop and redraw
//  entirely?") - once zDragActive goes false, three more passes climb the resolution back up
//  toward the original true-per-pixel quality, each one computed off the main thread
//  (Task.detached) and swapped in as it finishes, so the field keeps sharpening while sitting
//  still rather than staying at drag-quality forever. A drag starting again cancels whatever
//  refinement pass is in flight and forces an immediate fresh coarse render (see
//  ImageCache.wasDragging below) rather than letting stale work finish and flash in.
//  Measure performance-sensitive code like this in Release, not Debug - the same computation
//  measured roughly 50x slower in an unoptimized Debug build (-Onone vs -O on tight
//  closure-heavy numeric loops), which looks like a hang/regression but isn't one.
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
import GBGCore
import CoreGraphics

struct DissonanceView: View {
    let scale: Scale
    @ObservedObject var settings: AppSettings
    let showDissonance: Bool

    // The grid/image only actually depend on root/Z/limit/weighting/scale-shape/canvas size -
    // none of which change on a plain X/Y touch - but this View now correctly redraws on every
    // settings change (including xFrequency/yFrequency, published on every touch-move frame)
    // since fixing GraphView's missing @ObservedObject. Without this cache, that would mean
    // rebuilding the whole bitmap on every touch-move frame. A plain class (not @State itself)
    // so it can be mutated freely from inside the Canvas closure without tripping SwiftUI's
    // "modifying state during view update" - @State only needs to keep the box reference
    // itself stable, not track what's inside it.
    @State private var cache = ImageCache()

    // A tiny, dedicated ObservableObject the refinement Task's MainActor callback below bumps
    // to force this View's body (and so the Canvas closure) to re-run and pick up cache's
    // newly-refined image. Kept entirely separate from `cache` itself: `cache`'s own fields
    // are mutated synchronously from inside the Canvas closure (during this View's normal
    // render pass), where publishing a change would trip SwiftUI's "modifying state during
    // view update"; this object is only ever touched later, from the async callback, which is
    // exactly the ordinary case @Published/@StateObject change tracking is for.
    @StateObject private var refinementTrigger = RefinementTrigger()

    private final class RefinementTrigger: ObservableObject, @unchecked Sendable {
        @Published var tick = 0
    }

    // @unchecked: every mutating access happens on the main actor (the Canvas closure itself,
    // and the `await MainActor.run` hop in scheduleRefinement below) - the only thing that
    // crosses onto the detached background task is read-only value types captured by
    // scheduleRefinement's parameters, never this class itself.
    private final class ImageCache: @unchecked Sendable {
        var key: CacheKey?
        var image: CGImage?
        // Whether the *finished* image for `key` is already at full resolution - guards
        // scheduleRefinement against re-launching a Task every idle re-render (any settings
        // change re-runs this whole View's body, refinement or not) once there's nothing left
        // to improve.
        var refinedKey: CacheKey?
        var refinementTask: Task<Void, Never>?
        // Last-seen settings.zDragActive, so the Canvas closure can detect the false->true
        // transition (a drag starting again) even on a render where `key` itself hasn't
        // changed yet (DragGesture's first onChanged can fire at the same location it ended
        // at) - see the "dragging resumed" check below.
        var wasDragging = false
    }

    private struct CacheKey: Equatable {
        let rootFrequency: Double
        let zFrequency: Double?
        let limit: Int
        let highestRatio: Double
        let lowestRatio: Double
        // The canvas's own pixel width, not whatever resolution a given pass happened to
        // render at - resolution varies pass to pass (coarse while dragging, climbing during
        // refinement) but shouldn't by itself invalidate an already-cached image for the same
        // field; only an actual resize should.
        let canvasWidth: Int
    }

    var body: some View {
        if showDissonance {
            Canvas { context, size in
                guard let limit = limitMap[settings.selectedLimit], limit > 0 else { return }
                // Dissonance.roughnessGrid accepts an optional Z for its own more general
                // 2-or-3-voice API, but Z is always live here (ZSliderView is always mounted),
                // so this is never actually nil.
                let zFrequency: Double? = settings.zFrequency
                let isDragging = settings.zDragActive
                let canvasWidth = max(1, Int(size.width.rounded()))
                // Half the per-axis pixel count (Norm: "2x pixel to save time") while a drag
                // is live, rather than one grid cell per screen pixel - context.draw upscales
                // the result to the full canvas below, same as any other resolution mismatch.
                let liveResolution = max(1, canvasWidth / 2)

                let key = CacheKey(
                    rootFrequency: settings.rootFrequency,
                    zFrequency: zFrequency,
                    limit: limit,
                    highestRatio: scale.highestRatio,
                    lowestRatio: scale.lowestRatio,
                    canvasWidth: canvasWidth
                )

                // Dragging resumed: drop whatever's cached (drag-quality or already-refined)
                // and force the block below to render a brand new coarse pass this frame,
                // regardless of whether `key` itself happened to already match - Norm: "if
                // dragging resumes stop and redraw entirely."
                if isDragging && !cache.wasDragging {
                    cache.refinementTask?.cancel()
                    cache.refinementTask = nil
                    cache.key = nil
                }
                cache.wasDragging = isDragging

                let image: CGImage
                if cache.key == key, let cachedImage = cache.image {
                    image = cachedImage
                } else {
                    cache.refinementTask?.cancel()
                    cache.refinementTask = nil
                    guard let built = Self.renderRoughnessImage(
                        scale: scale, rootFrequency: settings.rootFrequency, zFrequency: zFrequency,
                        limit: limit, resolution: liveResolution
                    ) else { return }
                    image = built
                    cache.key = key
                    cache.image = image
                }

                context.draw(Image(decorative: image, scale: 1), in: CGRect(origin: .zero, size: size))

                // Idle, and this exact field isn't already fully refined or mid-refinement -
                // climb back up toward full resolution in the background. Covers both "just
                // rendered a fresh coarse pass above" and "dragging just stopped but the last
                // drag frame's key still matches" (the latter never enters the block above, so
                // this is the only place that case gets picked up).
                if !isDragging, cache.refinementTask == nil, cache.refinedKey != key {
                    scheduleRefinement(
                        scale: scale, rootFrequency: settings.rootFrequency, zFrequency: zFrequency,
                        limit: limit, canvasWidth: canvasWidth, startKey: key
                    )
                }
            }
        }
    }

    // Three passes climbing from the live (half-resolution) quality back up to the original
    // true-per-pixel resolution, each computed off the main thread and swapped into `cache`
    // as it finishes so the field visibly sharpens in steps rather than jumping once at the
    // end. cache.refinementTask.cancel() (called the instant a new drag starts, see the Canvas
    // closure above) doesn't just skip *applying* a pass already computing - the isCancelled
    // closure passed to renderRoughnessImage below is polled from inside roughnessGrid's own
    // row-batch loop (GBGCore), so a cancellation actually stops that loop within a batch or
    // two, not once it happens to finish computing a result that would only get thrown away.
    private func scheduleRefinement(scale: Scale, rootFrequency: Double, zFrequency: Double?, limit: Int, canvasWidth: Int, startKey: CacheKey) {
        let steps = [0.7, 0.85, 1.0]
            .map { max(1, Int((Double(canvasWidth) * $0).rounded())) }

        // Capture the ImageCache/RefinementTrigger references themselves, not `self` (the
        // View struct, which carries a non-Sendable @ObservedObject settings) - Task.detached's
        // closure must be @Sendable, and these two objects are the only state the refinement
        // passes touch.
        let cache = cache
        let refinementTrigger = refinementTrigger
        cache.refinementTask = Task.detached(priority: .utility) { [cache, refinementTrigger] in
            for (index, resolution) in steps.enumerated() {
                if Task.isCancelled { return }
                guard let built = Self.renderRoughnessImage(
                    scale: scale, rootFrequency: rootFrequency, zFrequency: zFrequency,
                    limit: limit, resolution: resolution, isCancelled: { Task.isCancelled }
                ) else { return }
                if Task.isCancelled { return }
                await MainActor.run {
                    // Bail if a drag started (and so invalidated `key`) while this pass was
                    // computing - applying a stale-Z image now would flash outdated data.
                    guard cache.key == startKey else { return }
                    cache.image = built
                    if index == steps.count - 1 { cache.refinedKey = startKey }
                    refinementTrigger.tick += 1
                }
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

    // Computes the roughness grid and builds it into a bitmap in one call - the shared path
    // both the synchronous coarse render (inside the Canvas closure) and every background
    // refinement pass (scheduleRefinement, off the main thread) go through, so the two can
    // never drift into computing the field differently. Static and free of View state
    // (everything it needs comes in as a parameter) so it's safe to call from Task.detached.
    // `isCancelled` is forwarded straight to Dissonance.roughnessGrid's own polling (nil for
    // the live coarse path, which is never cancelled) - Norm: "interrupt the redraw the
    // moment the drag message comes in, don't wait" - so a resumed drag stops a mid-flight
    // refinement pass's own O(resolution^2) loop directly, not just its result once it happens
    // to finish.
    private static func renderRoughnessImage(scale: Scale, rootFrequency: Double, zFrequency: Double?, limit: Int, resolution: Int, isCancelled: (() -> Bool)? = nil) -> CGImage? {
        // Always linear falloff (1.0 at the fundamental down to 1/limit at the highest
        // included harmonic) - was a user-facing toggle against the 1/n alternative, but
        // linear reveals visibly more structure and was always the default; Norm decided it's
        // not worth the UI real estate as a choice.
        let grid = Dissonance.roughnessGrid(
            scale: scale,
            rootFrequency: rootFrequency,
            zFrequency: zFrequency,
            limit: limit,
            resolution: resolution,
            weighting: { Dissonance.linearHarmonicWeight($0, limit: limit) },
            isCancelled: isCancelled
        )
        guard let maxRoughness = grid.flatMap({ $0 }).max(), maxRoughness > 0 else { return nil }
        return makeRoughnessImage(grid: grid, maxRoughness: maxRoughness, resolution: resolution)
    }

    // Builds the field as a single RGBA8 bitmap, one pixel per grid cell - straight (not
    // premultiplied) alpha, matching how the bytes are written below. row 0 of `grid` is the
    // lowest pitch (bottom of the graph, same convention as Graph/HitTestView), so it's written
    // into the LAST image row here - the image's own row 0 is its top when drawn normally, so
    // this is the explicit flip (see the header comment on why this isn't left to a context
    // transform instead).
    private static func makeRoughnessImage(grid: [[Double]], maxRoughness: Double, resolution: Int) -> CGImage? {
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
