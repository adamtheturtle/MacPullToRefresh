//
//  MacPullToRefresh.swift
//  MacPullToRefresh
//
//  A native-feeling pull-to-refresh for macOS. SwiftUI's `.refreshable` compiles on
//  macOS but never fires from a gesture (AppKit has no system pull-to-refresh control),
//  so this bridges to the `NSScrollView` underneath the SwiftUI container, tracking
//  over-scroll past the top edge and running an action on release. On iOS it forwards to
//  the native `.refreshable`, so a call site can apply it unconditionally.
//

#if os(macOS)
    import AppKit
#endif
import SwiftUI

public extension View {
    /// Adds a pull-to-refresh gesture to a scrollable container such as `List` or
    /// `ScrollView`.
    ///
    /// On macOS this bridges to the `NSScrollView` underneath the SwiftUI container: it
    /// tracks how far the content rubber-bands past its top edge and, when the user
    /// releases beyond a threshold, runs `action`. A circular indicator fades in as the
    /// user pulls and spins while the refresh is in flight.
    ///
    /// On iOS the underlying `List`/`ScrollView` has a native pull-to-refresh, so this
    /// simply wires `action` to `.refreshable` - call sites can apply it unconditionally.
    func macPullToRefresh(_ action: @escaping () async -> Void) -> some View {
        #if os(macOS)
            return modifier(MacPullToRefresh(action: action))
        #else
            return refreshable { await action() }
        #endif
    }
}

#if os(macOS)

    private struct MacPullToRefresh: ViewModifier {
        let action: () async -> Void

        /// How far (in points) the content must be dragged past the top before
        /// releasing triggers a refresh.
        private let threshold: CGFloat = 44

        /// The gap held open at the top while a refresh runs, so the spinner sits in
        /// cleared space above the content rather than on top of it, as on iOS. Kept
        /// equal to `threshold` so the content is already about this far down when the
        /// user releases, making the hand-off from the rubber-band nearly seamless.
        private let refreshGap: CGFloat = 44

        @State private var isRefreshing = false

        func body(content: Content) -> some View {
            content
                .background(
                    // The bridge holds the gap open with the scroll view's own top
                    // content inset while refreshing, and hosts the indicator inside the
                    // scroll view's clip view so it rides with the content lag-free — the
                    // rows can never scroll over it, matching iOS.
                    PullToRefreshScrollBridge(threshold: threshold,
                                              refreshGap: refreshGap,
                                              isRefreshing: isRefreshing) {
                        guard !isRefreshing else { return }

                        isRefreshing = true
                        Task {
                            await action()
                            isRefreshing = false
                        }
                    }
                )
        }
    }

    /// Centres the ``PullIndicator`` within its bounds so it can be dropped straight
    /// into the scroll view's clip view as a plain AppKit subview (via `NSHostingView`)
    /// that scrolls with the content.
    private struct HostedIndicator: View {
        var pull: CGFloat
        var isRefreshing: Bool

        var body: some View {
            PullIndicator(pull: pull, isRefreshing: isRefreshing)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// An iOS-style pull-to-refresh indicator: a ring of tapered spokes that reveal
    /// one by one as the user drags and spin while the refresh runs, mirroring
    /// `UIRefreshControl`'s activity indicator. Extracted from the modifier so it can
    /// be driven directly from fixed `pull`/`isRefreshing` values (and previewed).
    private struct PullIndicator: View {
        /// 0…1 as the user drags past the top; reveals the spokes in turn.
        var pull: CGFloat
        var isRefreshing: Bool

        /// The indicator's side length, scaled with the user's preferred text size
        /// (tracking Caption 2) so it honors the accessibility setting.
        @ScaledMetric(relativeTo: .caption2) private var side: CGFloat = 24

        /// Seconds per full revolution while spinning.
        private let period: Double = 1.7

        /// Spin the moment the pull reaches the top — i.e. as soon as it's armed and
        /// fully revealed (`pull >= 1`) — and keep spinning through the release and the
        /// refresh, so the indicator comes alive as it settles into the gap rather than
        /// waiting a beat for the refresh to start.
        private var spinning: Bool { isRefreshing || pull >= 1 }

        var body: some View {
            Group {
                if spinning {
                    // Drive the rotation off a steady timeline clock rather than a
                    // `repeatForever` animation. Hosted in an `NSView` and carried along
                    // by the scroll, that animation visibly stutters and changes pace
                    // whenever the view re-renders or the content moves; an angle derived
                    // from the wall clock stays perfectly linear regardless.
                    TimelineView(.animation) { context in
                        SpokeWheel(reveal: pull, spinning: true, side: side)
                            .rotationEffect(.degrees(angle(at: context.date)))
                    }
                } else {
                    SpokeWheel(reveal: pull, spinning: false, side: side)
                }
            }
            // Fade and grow in with the pull, matching iOS; solid while refreshing.
            .opacity(isRefreshing ? 1 : Double(min(1, pull * 1.2)))
            .scaleEffect(isRefreshing ? 1 : max(0.7, min(1, pull)))
            .animation(.easeOut(duration: 0.2), value: isRefreshing)
            .allowsHitTesting(false)
        }

        /// A linear 0…360° angle derived from the wall clock, wrapping every `period`
        /// seconds so the spin never speeds up, slows, or jumps at a cycle boundary.
        private func angle(at date: Date) -> Double {
            let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
            return t / period * 360
        }
    }

    /// The bare spoke wheel behind ``PullIndicator``: `spokeCount` tapered capsules
    /// laid out around a circle. While `spinning` the spokes carry a fixed trailing
    /// fade so rotating the whole wheel reads as motion; otherwise they light up in
    /// order up to `reveal` (0…1) to track the pull.
    private struct SpokeWheel: View {
        var reveal: CGFloat
        var spinning: Bool
        var side: CGFloat
        private let spokeCount = 12

        var body: some View {
            ZStack {
                ForEach(0 ..< spokeCount, id: \.self) { index in
                    Capsule()
                        .fill(Color.secondary)
                        .frame(width: side * 0.11, height: side * 0.28)
                        .offset(y: -side * 0.34)
                        .rotationEffect(.degrees(Double(index) / Double(spokeCount) * 360))
                        .opacity(opacity(for: index))
                }
            }
            .frame(width: side, height: side)
        }

        private func opacity(for index: Int) -> Double {
            if spinning {
                // Classic trailing fade; rotating the wheel animates it.
                return Double(index + 1) / Double(spokeCount)
            }
            // Reveal spokes in order as the pull grows toward the threshold.
            let revealed = Double(reveal) * Double(spokeCount)
            return max(0, min(1, revealed - Double(index)))
        }
    }

    #Preview("Indicator states") {
        HStack(spacing: 44) {
            VStack { PullIndicator(pull: 0.4, isRefreshing: false); Text("pulling") }
            VStack { PullIndicator(pull: 1, isRefreshing: false); Text("ready") }
            VStack { PullIndicator(pull: 0, isRefreshing: true); Text("refreshing") }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(50)
        .frame(width: 380, height: 160)
    }

    // Switch the canvas to Live mode, then drag the list down past the top with a
    // trackpad to feel the real pull-to-refresh gesture end to end.
    #Preview("Live — pull to refresh") {
        List(0 ..< 20, id: \.self) { row in
            Text("Row \(row)")
        }
        .macPullToRefresh {
            try? await Task.sleep(for: .seconds(1.5))
        }
        .frame(width: 320, height: 400)
    }

    /// Locates the `NSScrollView` backing the SwiftUI container it is placed behind
    /// and reports over-scroll past the top edge back to SwiftUI.
    private struct PullToRefreshScrollBridge: NSViewRepresentable {
        let threshold: CGFloat
        let refreshGap: CGFloat
        let isRefreshing: Bool
        let onTrigger: () -> Void

        func makeNSView(context: Context) -> ScrollFinderView {
            let view = ScrollFinderView()
            let coordinator = context.coordinator
            // The enclosing scroll view doesn't exist yet at make time, so connect
            // once this helper view is committed into the window hierarchy.
            view.onMoveToWindow = { [weak coordinator, weak view] in
                guard let coordinator, let view else { return }

                coordinator.connect(from: view)
            }
            return view
        }

        func updateNSView(_ nsView: ScrollFinderView, context: Context) {
            let coordinator = context.coordinator
            coordinator.threshold = threshold
            coordinator.refreshGap = refreshGap
            coordinator.onTrigger = onTrigger
            // Retry in case the scroll view wasn't reachable at first window attach.
            coordinator.connect(from: nsView)
            // The gap is opened mid-pull by the coordinator; close it once the refresh
            // finishes (the true -> false edge).
            if coordinator.wasRefreshing, !isRefreshing { coordinator.closeGap() }
            coordinator.wasRefreshing = isRefreshing
            // Drive the hosted indicator's spin/fade from the refresh flag.
            coordinator.setRefreshing(isRefreshing)
        }

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        /// An otherwise-invisible helper that fires `onMoveToWindow` once it lands in
        /// the window, giving the coordinator a moment when sibling AppKit views exist.
        final class ScrollFinderView: NSView {
            var onMoveToWindow: (() -> Void)?
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                if window != nil { onMoveToWindow?() }
            }
        }

        @MainActor
        final class Coordinator: NSObject {
            var threshold: CGFloat = 80
            var refreshGap: CGFloat = 44
            var onTrigger: () -> Void = {}

            /// The indicator, hosted as a subview of the scroll view's clip view so it
            /// scrolls with the content. Driven directly (no SwiftUI state round-trip),
            /// so it never lags behind the rows.
            private var indicator: NSHostingView<HostedIndicator>?
            private var currentPull: CGFloat = 0
            private var currentRefreshing = false

            private weak var scrollView: NSScrollView?
            private var overscroll: CGFloat = 0
            /// Whether the top gap is currently held open by an added content inset.
            private var gapOpen = false
            /// Tracks the refresh flag across `updateNSView` calls so the gap closes on
            /// the refresh-finished edge.
            var wasRefreshing = false
            /// The scroll view's own top inset before the gap is added, so it can be
            /// restored afterwards (e.g. an inset the system keeps under a title bar).
            private var baselineTopInset: CGFloat = 0
            /// The furthest the content was dragged past the top during the current
            /// live scroll. The instantaneous over-scroll eases back before the finger
            /// lifts, so the release decision is made against this peak instead.
            private var peakOverscroll: CGFloat = 0
            /// True only between `willStartLiveScroll` and `didEndLiveScroll`, i.e. while
            /// the user is actively scrolling. Bounds changes also fire during launch and
            /// programmatic layout, when the flipped clip view's origin can briefly dip
            /// negative as the list settles - gating the pull on a live scroll keeps the
            /// indicator from appearing on its own at launch.
            private var isLiveScrolling = false

            private var connectAttempts = 0

            func connect(from view: NSView) {
                guard scrollView == nil else { return }
                guard let scrollView = Self.scrollView(near: view) else {
                    // A `List` builds its `NSScrollView` a beat after this helper lands
                    // in the window, so it isn't reachable at first attach. Retry on the
                    // next runloop ticks until it exists (bounded so we give up rather
                    // than spin forever if there genuinely is no scroll view).
                    connectAttempts += 1
                    if connectAttempts <= 60 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak view] in
                            guard let self, let view else { return }
                            self.connect(from: view)
                        }
                    }
                    return
                }

                self.scrollView = scrollView
                // Guarantee rubber-banding at the top even when the list is short.
                scrollView.verticalScrollElasticity = .allowed
                let clip = scrollView.contentView
                clip.postsBoundsChangedNotifications = true
                let center = NotificationCenter.default
                center.addObserver(self, selector: #selector(boundsChanged),
                                   name: NSView.boundsDidChangeNotification, object: clip)
                center.addObserver(self, selector: #selector(liveScrollStarted),
                                   name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
                center.addObserver(self, selector: #selector(liveScrollEnded),
                                   name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
                attachIndicator(to: scrollView)
            }

            /// Drops the hosted indicator into the clip view, occupying the gap band
            /// directly above the content's top edge. As a clip-view subview it is
            /// carried along by every scroll — including momentum — in the same pass as
            /// the rows, so it stays glued just above the first row with no lag and clips
            /// away at the top edge as it rides off.
            private func attachIndicator(to scrollView: NSScrollView) {
                guard indicator == nil else { return }
                let host = NSHostingView(rootView: HostedIndicator(pull: 0, isRefreshing: false))
                host.autoresizingMask = [.width]
                indicator = host
                let clip = scrollView.contentView
                clip.addSubview(host)
                positionIndicator()
            }

            /// Sizes the indicator to the gap band `[-refreshGap, 0]` in the clip view's
            /// (flipped) coordinates — i.e. `refreshGap` points immediately above the
            /// content's top edge (`y == 0`). It's off-screen above the top at rest and
            /// slides into view as the content rubber-bands or the gap opens.
            private func positionIndicator() {
                guard let indicator, let clip = scrollView?.contentView else { return }
                indicator.frame = NSRect(x: 0, y: -refreshGap,
                                         width: clip.bounds.width, height: refreshGap)
            }

            private func setPull(_ value: CGFloat) {
                currentPull = value
                indicator?.rootView = HostedIndicator(pull: value, isRefreshing: currentRefreshing)
            }

            func setRefreshing(_ value: Bool) {
                guard let indicator else { currentRefreshing = value; return }
                // Keep the indicator on top and correctly placed in case the List rebuilt
                // its clip-view contents between updates.
                if indicator.superview !== scrollView?.contentView, let clip = scrollView?.contentView {
                    clip.addSubview(indicator)
                }
                positionIndicator()
                guard value != currentRefreshing else { return }
                currentRefreshing = value
                indicator.rootView = HostedIndicator(pull: currentPull, isRefreshing: value)
            }

            @objc private func liveScrollStarted() {
                isLiveScrolling = true
                overscroll = 0
                peakOverscroll = 0
                // Capture the resting top inset (e.g. under a title bar) at the start of
                // the pull, before any gap is added, so over-scroll is measured from the
                // true content top rather than from that inset.
                if !gapOpen, let scrollView { baselineTopInset = scrollView.contentInsets.top }
            }

            @objc private func boundsChanged() {
                guard let scrollView else { return }

                // The hosted indicator is a clip-view subview, so AppKit already carries
                // it along with this scroll — nothing to reposition here. While a refresh
                // runs the pull is over, so there's no reveal to update either.
                if wasRefreshing { return }

                // Ignore bounds changes that aren't part of a user scroll (launch, list
                // reloads, programmatic layout) so the indicator only reveals on a pull.
                guard isLiveScrolling else { return }

                // A `List` uses a flipped clip view, so the visible origin dips below
                // zero as the content rubber-bands past the top edge. Subtract the
                // resting inset so a pull is measured from the true content top.
                overscroll = max(0, -scrollView.contentView.bounds.origin.y - baselineTopInset)
                peakOverscroll = max(peakOverscroll, overscroll)
                // Reserve the gap the instant the pull crosses the threshold — while the
                // finger is still down — so that when it lifts, the scroll view's own
                // elastic settle lands on the enlarged inset (the held gap) instead of
                // snapping the content flush to the top, over the spinner. Reserving on
                // release is too late: AppKit has already latched the old top as its
                // bounce target, and the rows yank up through the spinner before easing
                // back down.
                if overscroll >= threshold, !gapOpen { openGap() }
                // Reveal the spokes in step with the pull. Driven straight into the hosted
                // view (no SwiftUI state round-trip) so it stays in lock-step with the drag.
                setPull(min(1, peakOverscroll / threshold))
            }

            @objc private func liveScrollEnded() {
                isLiveScrolling = false
                // The gap was reserved mid-drag the moment the pull crossed the
                // threshold, so its being open is exactly the "should refresh" signal.
                // The scroll view now settles its own elastic bounce into that gap.
                let shouldTrigger = gapOpen
                overscroll = 0
                peakOverscroll = 0
                setPull(0)
                if shouldTrigger { onTrigger() }
            }

            /// Reserves the top gap by enlarging the scroll view's top content inset.
            /// Called mid-drag once the pull crosses the threshold: the content is
            /// already about `refreshGap` past the top at that moment, so enlarging the
            /// inset simply promotes the current position to the new resting top — the
            /// content doesn't jump. When the finger lifts, the scroll view's own elastic
            /// bounce settles into this gap instead of snapping to the very top, so the
            /// rows never rise into the spinner. The origin is deliberately left alone;
            /// animating it here is what made the content fight the elastic and bounce.
            private func openGap() {
                guard let scrollView, !gapOpen else { return }
                gapOpen = true
                scrollView.automaticallyAdjustsContentInsets = false
                scrollView.contentInsets.top = baselineTopInset + refreshGap
            }

            func closeGap() {
                guard let scrollView, gapOpen else { return }
                gapOpen = false
                let clip = scrollView.contentView
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    context.allowsImplicitAnimation = true
                    // Scroll the content up out of the gap first. The enlarged inset is
                    // left in place for the duration, so this is an ordinary in-range
                    // scroll with nothing for the elastic to clamp against — it glides.
                    // Lowering the inset up front instead makes AppKit snap the origin to
                    // the new resting top immediately, so the content jumps before this
                    // animation can run.
                    clip.animator().setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: -baselineTopInset))
                    scrollView.reflectScrolledClipView(clip)
                } completionHandler: { [weak self] in
                    Task { @MainActor in
                        guard let self, let scrollView = self.scrollView else { return }
                        // The content has arrived at the resting top; removing the gap
                        // inset now doesn't shift it further (position tracks the origin,
                        // not the inset), so the hand-off is seamless.
                        scrollView.contentInsets.top = self.baselineTopInset
                        scrollView.automaticallyAdjustsContentInsets = true
                    }
                }
            }

            /// Finds the scroll view this helper is layered over. A `ScrollView`'s
            /// `.background` lands *inside* its scroll view, so the enclosing one is
            /// correct. A `List` instead places the background outside its scroll
            /// view, so fall back to the smallest scroll view in the window whose
            /// frame sits under the helper - i.e. the one it fronts, not a
            /// neighbouring pane's, which a naive descendant search can pick by
            /// mistake.
            private static func scrollView(near view: NSView) -> NSScrollView? {
                if let enclosing = view.enclosingScrollView { return enclosing }
                guard let root = view.window?.contentView else { return nil }

                let point = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: root)
                var best: NSScrollView?
                var bestArea = CGFloat.greatestFiniteMagnitude
                func walk(_ node: NSView) {
                    if let scroll = node as? NSScrollView {
                        let frame = scroll.convert(scroll.bounds, to: root)
                        if frame.contains(point) {
                            let area = frame.width * frame.height
                            if area < bestArea {
                                best = scroll
                                bestArea = area
                            }
                        }
                    }
                    node.subviews.forEach(walk)
                }
                walk(root)
                return best
            }

            deinit { NotificationCenter.default.removeObserver(self) }
        }
    }
#endif
