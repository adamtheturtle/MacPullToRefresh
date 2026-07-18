//
//  PullGestureTests.swift
//  MacPullToRefreshTests
//
//  Exercises the gesture state machine in `PullToRefreshScrollBridge.Coordinator` against
//  a real `NSScrollView`. The coordinator's whole input surface is notifications - the
//  clip view's `boundsDidChangeNotification`, and the scroll view's live-scroll
//  start/end - so moving the clip view's bounds origin and posting the live-scroll
//  notifications reproduces a pull faithfully, headlessly, without a window, a trackpad,
//  or a run loop. What is *not* reachable this way is anything gated on Core Animation
//  actually running (the tail of `closeGap`'s 0.3s animation) or on SwiftUI committing an
//  `updateNSView` pass; those are noted where they bound a test.
//

#if os(macOS)
    import AppKit
    import Testing

    @testable import MacPullToRefresh

    /// A clip view that accepts whatever origin it is given.
    ///
    /// Rubber-banding past the top is normally the scroll view's own doing, driven by a
    /// live gesture; outside one, `NSClipView` clamps any origin set on it straight back
    /// into range, so the over-scroll the coordinator exists to measure could never be
    /// staged. Declining to constrain is exactly how AppKit itself opts a clip view into
    /// letting content sit outside its bounds.
    private final class UnconstrainedClipView: NSClipView {
        override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect { proposedBounds }
    }

    /// A scroll view wired to a coordinator, with helpers that speak in gesture terms.
    @MainActor
    private struct PullHarness {
        let scrollView: NSScrollView
        let coordinator: PullToRefreshScrollBridge.Coordinator
        let threshold: CGFloat = 44

        init(baselineTopInset: CGFloat = 0) {
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
            scrollView.contentView = UnconstrainedClipView(frame: scrollView.bounds)
            let document = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 2000))
            scrollView.documentView = document
            scrollView.automaticallyAdjustsContentInsets = false
            scrollView.contentInsets.top = baselineTopInset
            self.scrollView = scrollView

            // `connect(from:)` finds the scroll view via `enclosingScrollView`, so a helper
            // view inside the document is enough - no window required.
            let finder = NSView(frame: .zero)
            document.addSubview(finder)

            let coordinator = PullToRefreshScrollBridge.Coordinator()
            coordinator.threshold = threshold
            coordinator.refreshGap = threshold
            coordinator.connect(from: finder)
            self.coordinator = coordinator
        }

        func beginPull() {
            NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification,
                                           object: scrollView)
        }

        /// Drags the content `points` past its true top edge. A flipped clip view's origin
        /// dips below the resting inset as the content rubber-bands, which is exactly what
        /// the coordinator measures.
        func drag(past points: CGFloat) {
            let clip = scrollView.contentView
            clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x,
                                         y: -(coordinator.baselineTopInset + points)))
        }

        func release() {
            NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification,
                                            object: scrollView)
        }
    }

    @Suite("Pull gesture state machine")
    @MainActor
    struct PullGestureTests {
        @Test
        func `releasing past the threshold triggers a refresh`() {
            let harness = PullHarness()
            var triggered = 0
            harness.coordinator.onTrigger = { triggered += 1 }

            harness.beginPull()
            harness.drag(past: 60)
            harness.release()

            #expect(triggered == 1)
        }

        @Test
        func `dragging back to the top before releasing cancels the refresh`() {
            // Issue #2: `gapOpen` latches at the threshold crossing and was never cleared
            // mid-drag, so a pull the user changed their mind about still fired on release.
            let harness = PullHarness()
            var triggered = 0
            harness.coordinator.onTrigger = { triggered += 1 }

            harness.beginPull()
            harness.drag(past: 60)
            #expect(harness.coordinator.gapOpen, "the gap is still reserved mid-drag")
            harness.drag(past: 0)
            harness.release()

            #expect(triggered == 0)
        }

        @Test
        func `a cancelled pull gives the reserved gap back`() {
            // The gap is reserved on the threshold crossing whether or not the pull is
            // eventually seen through, so cancelling has to take it down again - otherwise
            // the list rests with an empty 44pt band and no spinner in it.
            let harness = PullHarness()

            harness.beginPull()
            harness.drag(past: 60)
            harness.drag(past: 0)
            harness.release()

            #expect(harness.coordinator.gapOpen == false)
            #expect(harness.coordinator.isClosingGap)
        }

        @Test
        func `easing back onto the reserved gap still counts as armed`() {
            // Once the gap is open the content's resting position is `refreshGap` past the
            // true top, so the elastic settles there rather than at zero as the finger
            // lifts. That settle is an ordinary release, not a cancel.
            let harness = PullHarness()
            var triggered = 0
            harness.coordinator.onTrigger = { triggered += 1 }

            harness.beginPull()
            harness.drag(past: 70)
            harness.drag(past: harness.threshold)
            harness.release()

            #expect(triggered == 1)
        }

        @Test
        func `a scroll during the gap-close animation does not become the new baseline`() {
            // Issue #3: `closeGap` clears `gapOpen` up front but leaves the enlarged inset
            // in place for the whole 0.3s animation, so a scroll starting in that window
            // used to capture the *gap* inset as the baseline - after which every pull was
            // measured from 44 and the user had to drag 88pt to arm a refresh.
            let harness = PullHarness()

            harness.beginPull()
            harness.drag(past: 60)
            harness.release()
            #expect(harness.coordinator.baselineTopInset == 0)
            #expect(harness.scrollView.contentInsets.top == 44, "the gap inset is installed")

            harness.coordinator.setRefreshing(true)
            harness.coordinator.setRefreshing(false)
            harness.coordinator.closeGap()
            #expect(harness.coordinator.isClosingGap)
            #expect(harness.scrollView.contentInsets.top == 44,
                    "the gap inset is deliberately held for the animation's duration")

            // The user starts scrolling again while the close is still in flight.
            harness.beginPull()

            #expect(harness.coordinator.baselineTopInset == 0)
        }

        @Test
        func `a baseline inset survives a pull and is not compounded by it`() {
            // The same compounding, from a non-zero starting baseline: the inset the system
            // keeps under a title bar must come back out of a refresh unchanged.
            let harness = PullHarness(baselineTopInset: 20)

            harness.beginPull()
            #expect(harness.coordinator.baselineTopInset == 20)
            harness.drag(past: 60)
            #expect(harness.scrollView.contentInsets.top == 64)
            harness.release()

            harness.coordinator.setRefreshing(true)
            harness.coordinator.setRefreshing(false)
            harness.coordinator.closeGap()
            harness.beginPull()

            #expect(harness.coordinator.baselineTopInset == 20)
        }

        @Test
        func `the pull stays revealed until the refresh flag lands`() {
            // Issue #4: zeroing the pull on release rendered the indicator at
            // `opacity(min(1, 0 * 1.2)) == 0` for every frame between the release and
            // `setRefreshing(true)` arriving via `updateNSView`, blinking the spinner out
            // at precisely the hand-off it is meant to carry.
            let harness = PullHarness()

            harness.beginPull()
            harness.drag(past: 60)
            harness.release()

            #expect(harness.coordinator.currentPull == 1,
                    "the indicator is still fully revealed and spinning across the hand-off")

            harness.coordinator.setRefreshing(true)
            #expect(harness.coordinator.currentPull == 0,
                    "the refresh flag now covers the indicator, so the pull is spent")
        }

        @Test
        func `a cancelled pull clears the indicator immediately`() {
            // No refresh is coming, so there is nothing to hand off to and the indicator
            // must not linger.
            let harness = PullHarness()

            harness.beginPull()
            harness.drag(past: 60)
            harness.drag(past: 0)
            harness.release()

            #expect(harness.coordinator.currentPull == 0)
        }

        @Test
        func `the pull does not survive the end of a refresh`() {
            // A pull left at full reveal for the hand-off would otherwise keep the wheel
            // spinning (`spinning` is `isRefreshing || pull >= 1`) after the refresh ended.
            let harness = PullHarness()

            harness.beginPull()
            harness.drag(past: 60)
            harness.release()
            harness.coordinator.setRefreshing(true)
            harness.coordinator.setRefreshing(false)

            #expect(harness.coordinator.currentPull == 0)
        }
    }
#endif
