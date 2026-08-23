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
        let finder: NSView
        let threshold: CGFloat = 44

        init(
            baselineTopInset: CGFloat = 0,
            automaticallyAdjustsContentInsets: Bool = false,
            verticalScrollElasticity: NSScrollView.Elasticity = .automatic,
            postsBoundsChangedNotifications: Bool = false,
            coordinator: PullToRefreshScrollBridge.Coordinator? = nil
        ) {
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
            scrollView.contentView = UnconstrainedClipView(frame: scrollView.bounds)
            let document = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 2000))
            scrollView.documentView = document
            scrollView.automaticallyAdjustsContentInsets = automaticallyAdjustsContentInsets
            scrollView.verticalScrollElasticity = verticalScrollElasticity
            scrollView.contentView.postsBoundsChangedNotifications = postsBoundsChangedNotifications
            scrollView.contentInsets.top = baselineTopInset
            self.scrollView = scrollView

            // `connect(from:)` finds the scroll view via `enclosingScrollView`, so a helper
            // view inside the document is enough - no window required.
            let finder = NSView(frame: .zero)
            document.addSubview(finder)
            self.finder = finder

            let coordinator = coordinator ?? PullToRefreshScrollBridge.Coordinator()
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
    struct PullGestureTests { // swiftlint:disable:this type_body_length
        @Test
        func `mouse pull release triggers a refresh without live scroll notifications`() {
            let harness = PullHarness()
            var triggered = 0
            harness.coordinator.onTrigger = { triggered += 1 }

            harness.coordinator.beginMousePullForTesting()
            harness.drag(past: 60)
            harness.coordinator.mousePullEndedForTesting()

            #expect(triggered == 1)
        }


        @Test
        func `mouse up after a live-scroll trigger does not cancel the gap`() {
            let harness = PullHarness()
            var triggered = 0
            harness.coordinator.onTrigger = { triggered += 1 }

            harness.coordinator.beginMousePullForTesting()
            harness.beginPull()
            harness.drag(past: 60)
            harness.release()
            #expect(triggered == 1)
            #expect(harness.coordinator.gapOpen)

            harness.coordinator.mousePullEndedForTesting()
            #expect(triggered == 1)
            #expect(harness.coordinator.gapOpen)
            #expect(harness.coordinator.currentPull == 1)
        }

        @Test
        func `openGapForRefresh reserves the gap without a pull`() {
            let harness = PullHarness(baselineTopInset: 8)
            #expect(!harness.coordinator.gapOpen)

            harness.coordinator.openGapForRefresh()

            #expect(harness.coordinator.gapOpen)
            #expect(harness.scrollView.contentInsets.top == 8 + harness.threshold)
            #expect(harness.coordinator.baselineTopInset == 8)
        }

        @Test
        func `closeGap begins closing while holding the gap inset`() {
            // Core Animation completions do not run in this headless harness (no window /
            // run loop), so assert the mid-close state that is reachable here. The 0.3s
            // completion path that restores the baseline inset is covered by lifecycle
            // disconnect tests instead of a wall-clock sleep.
            let harness = PullHarness(baselineTopInset: 8)

            harness.beginPull()
            harness.drag(past: 60)
            harness.release()
            #expect(harness.coordinator.gapOpen)

            harness.coordinator.closeGap()
            #expect(harness.coordinator.isClosingGap)
            #expect(!harness.coordinator.gapOpen)
            #expect(harness.scrollView.contentInsets.top == 8 + harness.threshold,
                    "the enlarged inset is held for the animation's duration")
        }

        @Test
        func `a short document still allows rubber-band pulls`() {
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
            scrollView.contentView = UnconstrainedClipView(frame: scrollView.bounds)
            let document = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
            scrollView.documentView = document
            let finder = NSView(frame: .zero)
            document.addSubview(finder)

            let coordinator = PullToRefreshScrollBridge.Coordinator()
            coordinator.threshold = 44
            coordinator.refreshGap = 44
            coordinator.connect(from: finder)

            #expect(document.frame.height > scrollView.contentView.bounds.height)
            #expect(scrollView.verticalScrollElasticity == .allowed)
            coordinator.disconnect()
        }

        @Test
        func `disconnect restores a short document height bump`() {
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
            scrollView.contentView = UnconstrainedClipView(frame: scrollView.bounds)
            let document = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
            scrollView.documentView = document
            let finder = NSView(frame: .zero)
            document.addSubview(finder)

            let coordinator = PullToRefreshScrollBridge.Coordinator()
            coordinator.threshold = 44
            coordinator.refreshGap = 44
            coordinator.connect(from: finder)
            #expect(document.frame.height == 401)

            coordinator.disconnect()
            #expect(document.frame.height == 80)
        }

        @Test
        func `rubber-band bump reapplies when the clip grows while connected`() {
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
            scrollView.contentView = UnconstrainedClipView(frame: scrollView.bounds)
            let document = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
            scrollView.documentView = document
            let finder = NSView(frame: .zero)
            document.addSubview(finder)

            let coordinator = PullToRefreshScrollBridge.Coordinator()
            coordinator.threshold = 44
            coordinator.refreshGap = 44
            coordinator.connect(from: finder)
            #expect(document.frame.height == 401)

            scrollView.setFrameSize(NSSize(width: 300, height: 500))
            scrollView.contentView.setFrameSize(NSSize(width: 300, height: 500))
            // Same scroll view reconnect path (updateNSView) must re-bump.
            coordinator.connect(from: finder)
            #expect(document.frame.height == 501)
        }

        @Test
        func `boundsChanged updates stay within a reasonable budget`() {
            let harness = PullHarness()
            var triggered = 0
            harness.coordinator.onTrigger = {}

            harness.beginPull()
            let start = ContinuousClock.now
            for step in 0 ..< 500 {
                harness.drag(past: CGFloat(step % 60))
            }
            let elapsed = start.duration(to: ContinuousClock.now)
            #expect(elapsed < .seconds(0.75))
            _ = triggered
        }

        @Test
        func `disconnect drops the single hosted indicator subview`() {
            let harness = PullHarness()
            let afterConnect = harness.scrollView.contentView.subviews.count
            #expect(afterConnect >= 1)

            harness.coordinator.disconnect()
            #expect(harness.scrollView.contentView.subviews.count == afterConnect - 1)
        }

        @Test
        func `refresh indicator exposes meaningful accessibility states`() {
            #expect(HostedIndicator.accessibilityStatus(pull: 0.5, isRefreshing: false) ==
                "Pulling, 50 percent")
            #expect(HostedIndicator.accessibilityStatus(pull: 1, isRefreshing: false) == "Ready")
            #expect(HostedIndicator.accessibilityStatus(pull: 0, isRefreshing: true) == "Refreshing")
            #expect(HostedIndicator.progressFraction(pull: 0.5) == 0.5)
            #expect(HostedIndicator.progressFraction(pull: 1.5) == 1)
        }

        @Test
        func `nested scroll views resolve to the innermost scroll view`() {
            let outer = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
            outer.contentView = NSClipView(frame: outer.bounds)
            let inner = NSScrollView(frame: NSRect(x: 20, y: 20, width: 200, height: 200))
            inner.contentView = NSClipView(frame: inner.bounds)
            outer.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 800))
            outer.documentView?.addSubview(inner)
            inner.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 800))
            let helper = NSView(frame: NSRect(x: 30, y: 30, width: 10, height: 10))
            inner.documentView?.addSubview(helper)

            let found = PullScrollViewLocator.scrollView(near: helper)
            #expect(found === inner)
        }

        @Test
        func `refresh indicator respects Reduce Motion`() {
            #expect(PullIndicator.continuouslyRotates(
                pull: 1,
                isRefreshing: false,
                reduceMotion: false
            ))
            #expect(!PullIndicator.continuouslyRotates(
                pull: 1,
                isRefreshing: false,
                reduceMotion: true
            ))
            #expect(!PullIndicator.continuouslyRotates(
                pull: 0,
                isRefreshing: true,
                reduceMotion: true
            ))
        }

        @Test
        func `a second arming while refreshing announces and does not re-trigger`() {
            let harness = PullHarness()
            var triggered = 0
            harness.coordinator.onTrigger = { triggered += 1 }

            harness.beginPull()
            harness.drag(past: 60)
            harness.release()
            #expect(triggered == 1)

            harness.coordinator.setRefreshing(true)
            harness.coordinator.wasRefreshing = true

            harness.beginPull()
            harness.drag(past: 60)
            harness.release()

            #expect(triggered == 1)
            #expect(harness.coordinator.currentPull == 0)
        }

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
        func `a custom threshold arms only after that distance`() {
            let harness = PullHarness()
            harness.coordinator.threshold = 80
            harness.coordinator.refreshGap = 80
            var triggered = 0
            harness.coordinator.onTrigger = { triggered += 1 }

            harness.beginPull()
            harness.drag(past: 60)
            harness.release()
            #expect(triggered == 0)

            harness.beginPull()
            harness.drag(past: 90)
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

        @Test
        func `disconnect during refresh restores every host mutation`() {
            let harness = PullHarness(
                baselineTopInset: 20,
                automaticallyAdjustsContentInsets: true,
                verticalScrollElasticity: .none,
                postsBoundsChangedNotifications: false
            )
            let originalInsets = harness.scrollView.contentInsets
            let originalSubviewCount = harness.scrollView.contentView.subviews.count - 1

            harness.beginPull()
            harness.drag(past: 60)
            harness.release()
            harness.coordinator.setRefreshing(true)
            #expect(harness.scrollView.contentInsets.top == 64)
            #expect(harness.scrollView.verticalScrollElasticity == .allowed)
            #expect(harness.scrollView.contentView.postsBoundsChangedNotifications)

            harness.coordinator.disconnect()

            #expect(harness.scrollView.contentInsets.top == originalInsets.top)
            #expect(harness.scrollView.contentInsets.left == originalInsets.left)
            #expect(harness.scrollView.contentInsets.bottom == originalInsets.bottom)
            #expect(harness.scrollView.contentInsets.right == originalInsets.right)
            #expect(harness.scrollView.automaticallyAdjustsContentInsets)
            #expect(harness.scrollView.verticalScrollElasticity == .none)
            #expect(!harness.scrollView.contentView.postsBoundsChangedNotifications)
            #expect(harness.scrollView.contentView.subviews.count == originalSubviewCount)
            #expect(!harness.coordinator.gapOpen)
            #expect(!harness.coordinator.currentRefreshing)
        }

        @Test
        func `disconnect while closing restores a host that disabled automatic insets`() {
            let harness = PullHarness(
                baselineTopInset: 12,
                automaticallyAdjustsContentInsets: false
            )

            harness.beginPull()
            harness.drag(past: 60)
            harness.release()
            harness.coordinator.closeGap()
            #expect(harness.coordinator.isClosingGap)

            harness.coordinator.disconnect()

            #expect(harness.scrollView.contentInsets.top == 12)
            #expect(!harness.scrollView.automaticallyAdjustsContentInsets)
            #expect(!harness.coordinator.isClosingGap)
        }

        @Test
        func `connecting after a hierarchy replacement detaches the old scroll view`() {
            let coordinator = PullToRefreshScrollBridge.Coordinator()
            let first = PullHarness(
                baselineTopInset: 8,
                verticalScrollElasticity: .none,
                coordinator: coordinator
            )
            let second = PullHarness(
                baselineTopInset: 16,
                verticalScrollElasticity: .automatic,
                coordinator: coordinator
            )

            #expect(first.scrollView.contentInsets.top == 8)
            #expect(first.scrollView.verticalScrollElasticity == .none)
            #expect(!first.scrollView.contentView.postsBoundsChangedNotifications)
            #expect(second.scrollView.verticalScrollElasticity == .allowed)
            #expect(second.scrollView.contentView.postsBoundsChangedNotifications)
            coordinator.disconnect()
            #expect(second.scrollView.contentInsets.top == 16)
            #expect(second.scrollView.verticalScrollElasticity == .automatic)
        }

        @Test
        func `scrollView near prefers the enclosing scroll view`() {
            let harness = PullHarness()
            let found = PullScrollViewLocator.scrollView(near: harness.finder)
            #expect(found === harness.scrollView)
        }

        @Test
        func `scrollView near window walk picks the smallest covering scroll view`() {
            // Issue #28: when the helper is not inside a scroll view (List background
            // placement), walk the window and prefer the smallest frame that contains
            // the helper — not a neighbouring, larger pane.
            _ = NSApplication.shared
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
            window.contentView = root

            let large = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
            let small = NSScrollView(frame: NSRect(x: 40, y: 40, width: 200, height: 200))
            root.addSubview(large)
            root.addSubview(small)

            let helper = NSView(frame: NSRect(x: 50, y: 50, width: 20, height: 20))
            root.addSubview(helper)

            let found = PullScrollViewLocator.scrollView(near: helper)
            #expect(found === small)
            window.contentView = nil
            window.close()
        }

        @Test
        func `connection retry gives up after the attempt budget`() {
            let coordinator = PullToRefreshScrollBridge.Coordinator()
            let orphan = NSView(frame: .zero)

            for _ in 1 ... PullToRefreshScrollBridge.Coordinator.maxConnectAttempts {
                coordinator.connect(from: orphan)
                #expect(coordinator.didScheduleConnectRetry)
            }
            coordinator.connect(from: orphan)
            #expect(coordinator.connectAttempts ==
                PullToRefreshScrollBridge.Coordinator.maxConnectAttempts + 1)
            #expect(!coordinator.didScheduleConnectRetry)
            // Invalidate any timers scheduled during the budgeted retries.
            coordinator.disconnect()
        }

        @Test
        func `handoff fallback clears a stuck full reveal`() async {
            // Issue #30: if release arms a refresh but SwiftUI never round-trips
            // setRefreshing(true), the 0.5s fallback must clear the spinning pull.
            let harness = PullHarness()
            harness.coordinator.onTrigger = {}

            harness.beginPull()
            harness.drag(past: 60)
            harness.release()
            #expect(harness.coordinator.awaitingRefreshHandoff)
            #expect(harness.coordinator.currentPull == 1)

            try? await Task.sleep(for: .milliseconds(600))

            #expect(!harness.coordinator.awaitingRefreshHandoff)
            #expect(harness.coordinator.currentPull == 0)
        }

        @Test
        func `disconnect mid closeGap restores insets before the animation ends`() {
            // Issue #62: removal during the 0.3s close must not leave an enlarged inset.
            let harness = PullHarness(baselineTopInset: 10)
            harness.beginPull()
            harness.drag(past: 60)
            harness.release()
            #expect(harness.coordinator.gapOpen || harness.scrollView.contentInsets.top == 54)

            harness.coordinator.closeGap()
            #expect(harness.coordinator.isClosingGap)
            harness.coordinator.disconnect()

            #expect(harness.scrollView.contentInsets.top == 10)
            #expect(!harness.coordinator.isClosingGap)
            #expect(!harness.coordinator.gapOpen)
        }

        @Test
        func `reconnect after a list rebuilds its scroll view restores the new host`() {
            // Issue #63: SwiftUI can replace the backing NSScrollView; connect must
            // detach the stale host and attach the replacement.
            let coordinator = PullToRefreshScrollBridge.Coordinator()
            let first = PullHarness(
                baselineTopInset: 4,
                verticalScrollElasticity: .none,
                postsBoundsChangedNotifications: false,
                coordinator: coordinator
            )
            #expect(first.scrollView.verticalScrollElasticity == .allowed)

            let rebuilt = PullHarness(
                baselineTopInset: 12,
                verticalScrollElasticity: .automatic,
                postsBoundsChangedNotifications: false,
                coordinator: coordinator
            )
            #expect(first.scrollView.verticalScrollElasticity == .none)
            #expect(rebuilt.scrollView.verticalScrollElasticity == .allowed)
            #expect(rebuilt.scrollView.contentView.postsBoundsChangedNotifications)
            #expect(coordinator.baselineTopInset == 12)
            coordinator.disconnect()
        }
    }
#endif
