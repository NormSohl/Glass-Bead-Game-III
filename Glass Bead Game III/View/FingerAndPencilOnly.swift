//
//  FingerAndPencilOnly.swift
//  Glass Bead Game III
//
//  iOS-only: shared low-level touch-type filtering for any drag or tap surface a connected mouse
//  could otherwise drive just as well as a real finger - GCMouse's own prefersPointerLocked
//  (ContentView's MouseMonitor) turned out not to actually suppress the normal indirect-pointer
//  touch path the way that feature's own header comment always flagged as unverified, so a mouse
//  remained fully touch-equivalent for ordinary SwiftUI gestures/buttons throughout the app.
//
//  Two earlier attempts at fixing this on HitTestView's own graph drag, both reverted
//  2026-09-08, taught what each got wrong:
//    1. Reimplementing full touch handling (touchesBegan/Moved/Ended) inside a .background()
//       view - broke ALL touch/Pencil input outright, since a background view sits behind its
//       sibling content for hit-testing, not just visually, so it never received any touches at
//       all, mouse or real.
//    2. A transparent .overlay() (which DOES win hit-testing) that only overrode hitTest to
//       swallow indirect-pointer touches, letting everything else fall through untouched to the
//       existing SwiftUI DragGesture below - hitTest correctly claimed the mouse touches, but
//       the DragGesture recognized them anyway regardless: UIKit gesture recognizers don't
//       depend solely on which view wins raw hitTest, they see any touch landing within an
//       ancestor view's bounds via their own independent hierarchy walk, so "winning" hitTest
//       for an unrelated sibling/overlay view does nothing to stop a gesture recognizer attached
//       elsewhere in the tree from also recognizing that same touch.
//  FingerAndPencilDragCatcher/FingerAndPencilTapCatcher below combine what each got right:
//  reimplement the full touch lifecycle (like #1) so there's no separate SwiftUI gesture left on
//  iOS to race against at all, placed via .overlay() (like #2) so it actually receives touches.
//  Confirmed live on HitTestView's own graph drag; reused for any other iOS surface with the same
//  problem (Z-slider, ControlColumn's icon buttons).
//
//  Update 2026-09-28 (Norm): the iPad's separate mouse modes were removed - a mouse now behaves
//  exactly as on the Mac (left-drag plays the graph/Z-slider and taps buttons) alongside Pencil and
//  touch, so these catchers no longer filter by touch type at all. They're kept rather than
//  reverted to plain SwiftUI gestures because they still own single-touch tracking and the hover
//  preview (see handleHover). Known risk Norm accepted: mouse and Pencil moving X/Y at the same
//  moment fight over the pitch (seen live 2026-09-08 as apparent snapping flicker).

#if os(iOS)
import SwiftUI
import UIKit

// For a continuous drag surface (the graph, the Z-slider) - any touch (finger, Pencil, or a
// mouse's `.indirectPointer` click-and-drag, which carries the real absolute position for the
// whole press) drives onChanged/onEnded exactly like a DragGesture would.
struct FingerAndPencilDragCatcher: UIViewRepresentable {
    let onChanged: (CGPoint) -> Void
    let onEnded: () -> Void
    // Read-only crosshair-preview position, reported continuously whenever a pointer (mouse, or
    // Pencil on hover-capable hardware) is hovering nearby without actually touching down - see
    // this view's own UIHoverGestureRecognizer below for why this exists here rather than as a
    // plain SwiftUI .onContinuousHover on the Canvas this sits in front of.
    var onHover: ((CGPoint) -> Void)? = nil

    func makeUIView(context: Context) -> TouchFilteringView {
        let view = TouchFilteringView()
        view.onChanged = onChanged
        view.onEnded = onEnded
        view.onHover = onHover
        view.backgroundColor = .clear
        view.isOpaque = false
        let hoverRecognizer = UIHoverGestureRecognizer(target: view, action: #selector(TouchFilteringView.handleHover(_:)))
        view.addGestureRecognizer(hoverRecognizer)
        return view
    }

    func updateUIView(_ uiView: TouchFilteringView, context: Context) {
        uiView.onChanged = onChanged
        uiView.onEnded = onEnded
        uiView.onHover = onHover
    }

    final class TouchFilteringView: UIView {
        var onChanged: ((CGPoint) -> Void)?
        var onEnded: (() -> Void)?
        var onHover: ((CGPoint) -> Void)?
        // Only one touch is ever tracked (mirrors a plain DragGesture's own single-touch
        // behavior) - a second finger landing while one is already active is simply ignored
        // rather than taking over.
        private weak var activeTouch: UITouch?

        // This view sits in front of the Canvas for hit-testing (that's the whole point - see
        // this file's own header comment), which was silently blocking the Canvas's own plain
        // SwiftUI .onContinuousHover from ever firing - confirmed live 2026-09-08 ("For a moment
        // we had the cursor updating while the mouse was moving... it is gone now").
        // Attaching a UIHoverGestureRecognizer directly to this view instead - since it's already
        // the one actually receiving pointer interactions - and forwarding through onHover fixes
        // that without giving up any hit-testing this view still needs for touches. A hover
        // preview is read-only (nothing audible follows from it), so Pencil hover before touching
        // and mouse hover before clicking are the same feature for two input types.
        @objc func handleHover(_ recognizer: UIHoverGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                onHover?(recognizer.location(in: self))
            default:
                break
            }
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard activeTouch == nil, let touch = touches.first else { return }
            activeTouch = touch
            report(touch)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let activeTouch, touches.contains(activeTouch) else { return }
            report(activeTouch)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            end(touches)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            end(touches)
        }

        private func end(_ touches: Set<UITouch>) {
            guard let activeTouch, touches.contains(activeTouch) else { return }
            self.activeTouch = nil
            onEnded?()
        }

        // Callers' own coordinate convention has (0,0) at the top-left, same as this plain
        // UIView's own bounds (UIKit views are top-left origin by default) - no extra flip
        // needed here; each caller does its own single Y-flip same as before this existed.
        private func report(_ touch: UITouch) {
            onChanged?(touch.location(in: self))
        }
    }
}

// Same idea, for a plain tap target (ControlColumn's icon buttons) instead of a continuous drag
// - a touch-down-then-up inside the view's own bounds fires `onTap`; a touch that started or
// ended outside those bounds (a drag-away cancel, matching a plain SwiftUI Button's own
// behavior) does not.
struct FingerAndPencilTapCatcher: UIViewRepresentable {
    let onTap: () -> Void

    func makeUIView(context: Context) -> TapFilteringView {
        let view = TapFilteringView()
        view.onTap = onTap
        view.backgroundColor = .clear
        view.isOpaque = false
        return view
    }

    func updateUIView(_ uiView: TapFilteringView, context: Context) {
        uiView.onTap = onTap
    }

    final class TapFilteringView: UIView {
        var onTap: (() -> Void)?
        private weak var activeTouch: UITouch?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard activeTouch == nil else { return }
            activeTouch = touches.first
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let activeTouch, touches.contains(activeTouch) else { return }
            self.activeTouch = nil
            if bounds.contains(activeTouch.location(in: self)) {
                onTap?()
            }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let activeTouch, touches.contains(activeTouch) else { return }
            self.activeTouch = nil
        }
    }
}
#endif
