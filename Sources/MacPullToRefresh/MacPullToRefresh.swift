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
    /// user pulls and spins while the refresh is in flight. Dragging back toward the top
    /// before releasing cancels the gesture without running `action`, as the equivalent
    /// iOS gesture does.
    ///
    /// On iOS the underlying `List`/`ScrollView` has a native pull-to-refresh, so this
    /// simply wires `action` to `.refreshable` - call sites can apply it unconditionally.
    ///
    /// - Parameters:
    ///   - threshold: Points past the top required to arm a refresh on macOS. Values that
    ///     are not finite or are `<= 0` fall back to `44`. Ignored on iOS.
    ///   - refreshGap: Top inset held open while a refresh runs on macOS. Values that are
    ///     not finite or are `<= 0` fall back to the sanitized `threshold`. Ignored on iOS.
    ///   - isEnabled: When `false`, the modifier is a no-op and no pull gesture or native
    ///     refresh control is installed.
    ///   - action: Async work to run when a refresh is triggered. Throwing actions are
    ///     supported; errors are caught so the in-flight refresh always completes.
    @ViewBuilder
    func macPullToRefresh(
        threshold: CGFloat = 44,
        refreshGap: CGFloat = 44,
        isEnabled: Bool = true,
        _ action: @escaping () async throws -> Void
    ) -> some View {
        macPullToRefresh(
            threshold: threshold,
            refreshGap: refreshGap,
            isEnabled: isEnabled,
            indicator: HostedIndicator.init,
            action
        )
    }

    /// Adds pull-to-refresh with a custom indicator view on macOS.
    func macPullToRefresh<I: View>(
        threshold: CGFloat = 44,
        refreshGap: CGFloat = 44,
        isEnabled: Bool = true,
        indicator: @escaping (_ pull: CGFloat, _ isRefreshing: Bool) -> I,
        _ action: @escaping () async throws -> Void
    ) -> some View {
        #if os(macOS)
            let safeThreshold = sanitizedPullDistance(threshold, fallback: 44)
            let safeGap = sanitizedPullDistance(refreshGap, fallback: safeThreshold)
            return modifier(MacPullToRefresh(
                action: action,
                trigger: nil as UInt64?,
                threshold: safeThreshold,
                refreshGap: safeGap,
                isEnabled: isEnabled,
                indicator: indicator
            ))
        #else
            return modifier(IOSPullToRefresh(
                isEnabled: isEnabled,
                trigger: nil as UInt64?,
                action: action
            ))
        #endif
    }

    /// Adds pull-to-refresh and also runs `action` whenever `trigger` changes to a new
    /// value (after the initial appearance). Use this for a toolbar button or other
    /// programmatic refresh:
    ///
    /// ```swift
    /// @State private var refreshTick: UInt64 = 0
    /// …
    /// .macPullToRefresh(trigger: refreshTick) { await load() }
    /// Button("Refresh") { refreshTick &+= 1 }
    /// ```
    ///
    /// - Parameters:
    ///   - trigger: Equatable value; each change after appear starts a refresh.
    ///   - threshold: Points past the top required to arm a refresh on macOS. Values that
    ///     are not finite or are `<= 0` fall back to `44`. Ignored on iOS.
    ///   - refreshGap: Top inset held open while a refresh runs on macOS. Values that are
    ///     not finite or are `<= 0` fall back to the sanitized `threshold`. Ignored on iOS.
    ///   - isEnabled: When `false`, the modifier is a no-op.
    ///   - action: Async work to run on pull or trigger. Throwing actions are supported.
    @ViewBuilder
    func macPullToRefresh<Trigger: Equatable>(
        trigger: Trigger,
        threshold: CGFloat = 44,
        refreshGap: CGFloat = 44,
        isEnabled: Bool = true,
        _ action: @escaping () async throws -> Void
    ) -> some View {
        if isEnabled {
            #if os(macOS)
                let safeThreshold = sanitizedPullDistance(threshold, fallback: 44)
                let safeGap = sanitizedPullDistance(refreshGap, fallback: safeThreshold)
                modifier(MacPullToRefresh(
                    action: action,
                    trigger: Optional(trigger),
                    threshold: safeThreshold,
                    refreshGap: safeGap,
                    isEnabled: true,
                    indicator: HostedIndicator.init
                ))
            #else
                modifier(IOSPullToRefresh(
                    isEnabled: true,
                    trigger: Optional(trigger),
                    action: action
                ))
            #endif
        } else {
            self
        }
    }
}

#if !os(macOS)
    /// Stable-type iOS wrapper so enabling/disabling refresh does not swap the view type.
    private struct IOSPullToRefresh<Trigger: Equatable>: ViewModifier {
        let isEnabled: Bool
        let trigger: Trigger?
        let action: () async throws -> Void

        @State private var isRefreshing = false
        @State private var didAppear = false

        func body(content: Content) -> some View {
            Group {
                if isEnabled {
                    content.refreshable {
                        await runAction()
                    }
                } else {
                    content
                }
            }
            .onAppear { didAppear = true }
            .onChange(of: trigger) { newValue in
                guard isEnabled, didAppear, newValue != nil, !isRefreshing else { return }
                Task { await runAction() }
            }
        }

        private func runAction() async {
            guard !isRefreshing else { return }

            isRefreshing = true
            defer { isRefreshing = false }
            do {
                try await action()
            } catch {
                // Always clear the native refresh control; callers own errors.
            }
        }
    }
#endif

/// Ensures pull distances used for arming and gap sizing stay positive and finite.
func sanitizedPullDistance(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
    value.isFinite && value > 0 ? value : fallback
}

#if os(macOS)

    private struct MacPullToRefresh<Trigger: Equatable, I: View>: ViewModifier {
        let action: () async throws -> Void
        let trigger: Trigger?
        let threshold: CGFloat
        let refreshGap: CGFloat
        let isEnabled: Bool
        let indicator: (CGFloat, Bool) -> I

        @State private var isRefreshing = false
        @State private var didAppear = false
        @State private var refreshTask: Task<Void, Never>?

        func body(content: Content) -> some View {
            // Always wrap `content` in the same modifier type so toggling `isEnabled`
            // does not rebuild the scroll hierarchy via `_ConditionalContent`.
            content
                .background {
                    if isEnabled {
                        PullToRefreshScrollBridge(
                            threshold: threshold,
                            refreshGap: refreshGap,
                            isRefreshing: isRefreshing,
                            indicator: indicator
                        ) {
                            startRefresh()
                        }
                    }
                }
                .onAppear { didAppear = true }
                // macOS 13-compatible onChange (single-parameter form).
                .onChange(of: trigger) { newValue in
                    guard isEnabled, didAppear, newValue != nil else { return }
                    startRefresh()
                }
                .onDisappear {
                    // Cancelling the in-flight refresh when the modified view leaves the
                    // hierarchy lets cooperative actions observe Task.isCancelled and
                    // stops the spinner from outliving its host.
                    refreshTask?.cancel()
                    refreshTask = nil
                    isRefreshing = false
                }
        }

        private func startRefresh() {
            guard isEnabled, !isRefreshing else { return }

            isRefreshing = true
            refreshTask?.cancel()
            refreshTask = Task {
                do {
                    try await action()
                } catch {
                    // Always clear the refresh UI; callers own error presentation.
                }
                // A cancelled task must not clear a newer refresh that started after
                // onDisappear (or another cancel) handed off to a fresh Task.
                guard !Task.isCancelled else { return }

                isRefreshing = false
                refreshTask = nil
            }
        }
    }

    /// Centres the ``PullIndicator`` within its bounds so it can be dropped straight
    /// into the scroll view's clip view as a plain AppKit subview (via `NSHostingView`)
    /// that scrolls with the content.
    ///
    /// Public so tests and host apps can assert VoiceOver status strings without depending
    /// on private layout details of the spoke wheel.
    public struct HostedIndicator: View {
        public var pull: CGFloat
        public var isRefreshing: Bool

        public init(pull: CGFloat, isRefreshing: Bool) {
            self.pull = pull
            self.isRefreshing = isRefreshing
        }

        public var body: some View {
            PullIndicator(pull: pull, isRefreshing: isRefreshing)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(PullRefreshAccessibility.refreshLabel)
                .accessibilityHint(PullRefreshAccessibility.refreshHint)
                .accessibilityValue(Self.accessibilityStatus(
                    pull: pull,
                    isRefreshing: isRefreshing
                ))
                .accessibilityHidden(pull <= 0 && !isRefreshing)
        }

        /// VoiceOver value for the current pull / refresh phase.
        ///
        /// Exposed as a testing API so clients can lock accessibility copy without hosting
        /// a live `NSScrollView`.
        public static func accessibilityStatus(pull: CGFloat, isRefreshing: Bool) -> String {
            if isRefreshing { return PullRefreshAccessibility.refreshing }
            if pull >= 1 { return PullRefreshAccessibility.ready }
            if pull <= 0 { return PullRefreshAccessibility.pulling }
            let percent = Int((pull * 100).rounded(.down))
            return PullRefreshAccessibility.pullingProgress(percent: percent)
        }

        /// Pull progress toward the arming threshold, clamped to 0…1.
        static func progressFraction(pull: CGFloat) -> CGFloat {
            min(1, max(0, pull))
        }
    }

    /// An iOS-style pull-to-refresh indicator: a ring of tapered spokes that reveal
    /// one by one as the user drags and spin while the refresh runs, mirroring
    /// `UIRefreshControl`'s activity indicator. Extracted from the modifier so it can
    /// be driven directly from fixed `pull`/`isRefreshing` values (and previewed).
    public struct PullIndicator: View {
        /// 0…1 as the user drags past the top; reveals the spokes in turn.
        public var pull: CGFloat
        /// Whether a refresh action is currently running.
        public var isRefreshing: Bool

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

        public init(pull: CGFloat, isRefreshing: Bool) {
            self.pull = pull
            self.isRefreshing = isRefreshing
        }

        public static func continuouslyRotates(
            pull: CGFloat,
            isRefreshing: Bool,
            reduceMotion: Bool
        ) -> Bool {
            (isRefreshing || pull >= 1) && !reduceMotion
        }

        public var body: some View {
            Group {
                if Self.continuouslyRotates(
                    pull: pull,
                    isRefreshing: isRefreshing,
                    reduceMotion: reduceMotion
                ) {
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
                    SpokeWheel(
                        reveal: spinning ? 1 : pull,
                        spinning: spinning,
                        side: side
                    )
                }
            }
            // Fade and grow in with the pull, matching iOS; solid while refreshing.
            .opacity(isRefreshing ? 1 : Double(min(1, pull * 1.2)))
            .scaleEffect(isRefreshing ? 1 : max(0.7, min(1, pull)))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isRefreshing)
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

        @Environment(\.colorSchemeContrast) private var contrast

        private var spokeColor: Color {
            contrast == .increased ? .primary : .secondary
        }

        var body: some View {
            ZStack {
                ForEach(0 ..< spokeCount, id: \.self) { index in
                    Capsule()
                        .fill(spokeColor)
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

    // The coordinator intentionally keeps the complete AppKit lifecycle and gesture
    // state machine together so every mutation is restored by one disconnect path.
    // swiftlint:disable type_body_length
    /// Locates the `NSScrollView` backing the SwiftUI container it is placed behind
    /// and reports over-scroll past the top edge back to SwiftUI.
    /// Internal rather than private so the gesture state machine in ``Coordinator`` can be
    /// driven directly from tests against a real `NSScrollView`, without a window or a
    /// live trackpad gesture.
    struct PullToRefreshScrollBridge: NSViewRepresentable {
        let threshold: CGFloat
        let refreshGap: CGFloat
        let isRefreshing: Bool
        let makeIndicator: (CGFloat, Bool) -> AnyView
        let onTrigger: () -> Void

        init<I: View>(
            threshold: CGFloat,
            refreshGap: CGFloat,
            isRefreshing: Bool,
            indicator: @escaping (CGFloat, Bool) -> I,
            onTrigger: @escaping () -> Void
        ) {
            self.threshold = threshold
            self.refreshGap = refreshGap
            self.isRefreshing = isRefreshing
            self.makeIndicator = { pull, refreshing in
                AnyView(
                    indicator(pull, refreshing)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                )
            }
            self.onTrigger = onTrigger
        }

        func makeNSView(context: Context) -> ScrollFinderView {
            let view = ScrollFinderView()
            let coordinator = context.coordinator
            coordinator.configureIndicator(makeIndicator: makeIndicator)
            // The enclosing scroll view doesn't exist yet at make time, so connect
            // once this helper view is committed into the window hierarchy.
            view.onMoveToWindow = { [weak coordinator, weak view] in
                guard let coordinator, let view else { return }

                coordinator.connect(from: view)
            }
            view.onWindowChanged = { [weak coordinator, weak view] in
                guard let coordinator, let view else { return }

                coordinator.disconnect()
                coordinator.connect(from: view)
            }
            return view
        }

        func updateNSView(_ nsView: ScrollFinderView, context: Context) {
            let coordinator = context.coordinator
            coordinator.threshold = threshold
            coordinator.refreshGap = refreshGap
            coordinator.onTrigger = onTrigger
            coordinator.configureIndicator(makeIndicator: makeIndicator)
            // Retry in case the scroll view wasn't reachable at first window attach.
            coordinator.connect(from: nsView)
            // Programmatic refresh never crosses the pull threshold, so open the gap
            // when the refresh flag rises; pull-driven refreshes may already have it open.
            // Close it once the refresh finishes (the true -> false edge).
            if isRefreshing, !coordinator.wasRefreshing {
                coordinator.openGapForRefresh()
            } else if coordinator.wasRefreshing, !isRefreshing {
                coordinator.closeGap()
            }
            coordinator.wasRefreshing = isRefreshing
            // Drive the hosted indicator's spin/fade from the refresh flag.
            coordinator.setRefreshing(isRefreshing)
        }

        static func dismantleNSView(_ nsView: ScrollFinderView, coordinator: Coordinator) {
            nsView.onMoveToWindow = nil
            coordinator.disconnect()
        }

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        /// An otherwise-invisible helper that fires `onMoveToWindow` once it lands in
        /// the window, giving the coordinator a moment when sibling AppKit views exist.
        final class ScrollFinderView: NSView {
            var onMoveToWindow: (() -> Void)?
            var onWindowChanged: (() -> Void)?
            private weak var trackedWindow: NSWindow?

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                guard let window else { return }

                if let trackedWindow, trackedWindow !== window {
                    onWindowChanged?()
                }
                trackedWindow = window
                onMoveToWindow?()
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
            private let indicatorHost = PullIndicatorHost()
            var currentPull: CGFloat { indicatorHost.pull }
            var currentRefreshing: Bool { indicatorHost.isRefreshing }

            func configureIndicator(makeIndicator: @escaping (CGFloat, Bool) -> AnyView) {
                indicatorHost.configure(makeIndicator)
            }

            private weak var scrollView: NSScrollView?
            private var originalContentInsets: NSEdgeInsets?
            private var originalAutoInsets: Bool?
            private var originalVerticalScrollElasticity: NSScrollView.Elasticity?
            private var originalPostsBoundsChangedNotifications: Bool?
            /// Document height before ``ensureScrollableRubberBand`` bumped it; restored on disconnect.
            private var originalDocumentHeight: CGFloat?
            /// Invalidates animation completions and delayed connection attempts after a
            /// disconnect or reconnection.
            private var connectionGeneration = 0
            private var overscroll: CGFloat = 0
            /// Whether the top gap is currently held open by an added content inset.
            private(set) var gapOpen = false
            /// True while ``closeGap()``'s 0.3s animation is in flight. The enlarged gap
            /// inset is deliberately left in place for its whole duration, so the scroll
            /// view's top inset does not describe the baseline during this window and must
            /// not be mistaken for it.
            private(set) var isClosingGap = false
            /// Tracks the refresh flag across `updateNSView` calls so the gap closes on
            /// the refresh-finished edge.
            var wasRefreshing = false
            /// The scroll view's own top inset before the gap is added, so it can be
            /// restored afterwards (e.g. an inset the system keeps under a title bar).
            private(set) var baselineTopInset: CGFloat = 0
            /// The furthest the content was dragged past the top during the current live
            /// scroll. The reveal is driven from this peak rather than the instantaneous
            /// over-scroll so the spokes don't flicker back and forth on the jitter of a
            /// drag. (The release *decision* is made on the instantaneous value, so that
            /// deliberately dragging back to the top cancels the gesture.)
            private var peakOverscroll: CGFloat = 0
            /// True only between `willStartLiveScroll` and `didEndLiveScroll`, i.e. while
            /// the user is actively scrolling. Bounds changes also fire during launch and
            /// programmatic layout, when the flipped clip view's origin can briefly dip
            /// negative as the list settles - gating the pull on a live scroll keeps the
            /// indicator from appearing on its own at launch.
            private var isLiveScrolling = false
            /// True while the primary mouse button is down during a content drag that does
            /// not emit live-scroll notifications (common with mouse pulls).
            private var isMousePulling = false
            private var mouseUpMonitor: Any?

            /// Bounded connect retries while waiting for a `List` to materialize its
            /// `NSScrollView`. Exposed for tests that assert the give-up path.
            static let maxConnectAttempts = 60

            private(set) var connectAttempts = 0
            /// Whether the most recent failed `connect(from:)` scheduled another retry.
            private(set) var didScheduleConnectRetry = false
            /// True between an armed release and `setRefreshing(true)` (or the hand-off
            /// fallback). Exposed so tests can assert the fallback path.
            private(set) var awaitingRefreshHandoff = false

            func connect(from view: NSView) {
                guard let candidate = PullScrollViewLocator.scrollView(near: view) else {
                    if scrollView != nil {
                        disconnect()
                    }
                    // A `List` builds its `NSScrollView` a beat after this helper lands
                    // in the window, so it isn't reachable at first attach. Retry on the
                    // next runloop ticks until it exists (bounded so we give up rather
                    // than spin forever if there genuinely is no scroll view).
                    connectAttempts += 1
                    if connectAttempts <= Self.maxConnectAttempts {
                        didScheduleConnectRetry = true
                        let generation = connectionGeneration
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak view] in
                            guard let self, let view,
                                  self.connectionGeneration == generation
                            else { return }
                            self.connect(from: view)
                        }
                    } else {
                        didScheduleConnectRetry = false
                    }
                    return
                }
                guard candidate !== scrollView else {
                    // Document or clip size may have changed since the initial connect
                    // (filtering, deletions, window resize); re-apply the short-list bump.
                    ensureScrollableRubberBand(in: candidate)
                    return
                }

                if scrollView != nil {
                    disconnect()
                }

                connectAttempts = 0
                didScheduleConnectRetry = false
                connectionGeneration += 1
                scrollView = candidate
                originalContentInsets = candidate.contentInsets
                originalAutoInsets = candidate.automaticallyAdjustsContentInsets
                originalVerticalScrollElasticity = candidate.verticalScrollElasticity
                originalPostsBoundsChangedNotifications = candidate.contentView.postsBoundsChangedNotifications
                baselineTopInset = candidate.contentInsets.top
                // Guarantee rubber-banding at the top even when the list is short.
                candidate.verticalScrollElasticity = .allowed
                ensureScrollableRubberBand(in: candidate)
                let clip = candidate.contentView
                clip.postsBoundsChangedNotifications = true
                let center = NotificationCenter.default
                center.addObserver(self, selector: #selector(boundsChanged),
                                   name: NSView.boundsDidChangeNotification, object: clip)
                center.addObserver(self, selector: #selector(liveScrollStarted),
                                   name: NSScrollView.willStartLiveScrollNotification, object: candidate)
                center.addObserver(self, selector: #selector(liveScrollEnded),
                                   name: NSScrollView.didEndLiveScrollNotification, object: candidate)
                installMouseUpMonitor()
                attachIndicator(to: candidate)
            }

            private func installMouseUpMonitor() {
                guard mouseUpMonitor == nil else { return }

                mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                    self?.mousePullEnded()
                    return event
                }
            }

            private func attachIndicator(to scrollView: NSScrollView) {
                indicatorHost.attach(to: scrollView, refreshGap: refreshGap)
            }

            /// Stops observing the current host and restores every AppKit property the
            /// bridge changed. This is synchronous so removal during a refresh or closing
            /// animation cannot leave a surviving scroll view in a modified state.
            func disconnect() {
                connectionGeneration += 1
                // Reconnection is an explicit lifecycle boundary, not deallocation;
                // keeping the old notifications would deliver stale scroll events.
                // swiftlint:disable:next notification_center_detachment
                NotificationCenter.default.removeObserver(self)
                if let mouseUpMonitor {
                    NSEvent.removeMonitor(mouseUpMonitor)
                    self.mouseUpMonitor = nil
                }
                indicatorHost.removeFromSuperview()

                if let scrollView {
                    if let originalAutoInsets {
                        scrollView.automaticallyAdjustsContentInsets = originalAutoInsets
                    }
                    if let originalContentInsets {
                        scrollView.contentInsets = originalContentInsets
                    }
                    if let originalVerticalScrollElasticity {
                        scrollView.verticalScrollElasticity = originalVerticalScrollElasticity
                    }
                    if let originalPostsBoundsChangedNotifications {
                        scrollView.contentView.postsBoundsChangedNotifications =
                            originalPostsBoundsChangedNotifications
                    }
                    if let originalDocumentHeight, let document = scrollView.documentView {
                        document.frame.size.height = originalDocumentHeight
                    }
                }

                scrollView = nil
                originalContentInsets = nil
                originalAutoInsets = nil
                originalVerticalScrollElasticity = nil
                originalPostsBoundsChangedNotifications = nil
                originalDocumentHeight = nil
                overscroll = 0
                peakOverscroll = 0
                gapOpen = false
                isClosingGap = false
                awaitingRefreshHandoff = false
                wasRefreshing = false
                isLiveScrolling = false
                isMousePulling = false
            }

            private func setPull(_ value: CGFloat) {
                indicatorHost.setPull(value)
            }

            func setRefreshing(_ value: Bool) {
                guard value != indicatorHost.isRefreshing else { return }

                if let scrollView {
                    indicatorHost.reposition(in: scrollView, refreshGap: refreshGap)
                }
                announce(value ? PullRefreshAccessibility.refreshing : PullRefreshAccessibility.refreshComplete)
                awaitingRefreshHandoff = false
                indicatorHost.setRefreshing(value)
            }

            private func announce(_ message: String) {
                guard let scrollView else { return }
                NSAccessibility.post(
                    element: scrollView,
                    notification: .announcementRequested,
                    userInfo: [
                        .announcement: message,
                        .priority: NSAccessibilityPriorityLevel.high.rawValue
                    ]
                )
            }

            @objc private func liveScrollStarted() {
                isLiveScrolling = true
                overscroll = 0
                peakOverscroll = 0
                // Capture the resting top inset (e.g. under a title bar) at the start of
                // the pull, before any gap is added, so over-scroll is measured from the
                // true content top rather than from that inset. While a gap is open — or
                // still being closed, which holds the enlarged inset in place for the
                // whole animation — the current inset is the gap, not the baseline, so
                // re-capturing it here would latch the gap into the baseline permanently.
                if !gapOpen, !isClosingGap, let scrollView { baselineTopInset = scrollView.contentInsets.top }
            }

            @objc private func boundsChanged() {
                guard let scrollView else { return }

                ensureScrollableRubberBand(in: scrollView)

                // Ignore bounds changes that aren't part of a user scroll (launch, list
                // reloads, programmatic layout) so the indicator only reveals on a pull.
                let mouseDown = NSEvent.pressedMouseButtons & (1 << 0) != 0
                if mouseDown, !isLiveScrolling, !isMousePulling {
                    beginMousePull()
                }
                guard isLiveScrolling || isMousePulling else { return }

                // A `List` uses a flipped clip view, so the visible origin dips below
                // zero as the content rubber-bands past the top edge. Subtract the
                // resting inset so a pull is measured from the true content top.
                overscroll = max(0, -scrollView.contentView.bounds.origin.y - baselineTopInset)
                peakOverscroll = max(peakOverscroll, overscroll)

                // While a refresh runs, keep measuring over-scroll so a second pull can
                // announce "already in progress" on release — but do not update the
                // indicator reveal or re-open the gap.
                if wasRefreshing { return }

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
                // Skip hosting updates when the rounded reveal is unchanged — bounds
                // notifications fire far more often than the indicator needs to redraw.
                let nextPull = min(1, peakOverscroll / threshold)
                if nextPull != currentPull {
                    setPull(nextPull)
                }
            }

            /// The over-scroll at which the pull still counts as armed when the finger
            /// lifts.
            ///
            /// Once the gap is reserved the content's resting position sits `refreshGap`
            /// past the true content top, so the elastic eases back to `refreshGap` rather
            /// than to zero and an ordinary release must not read as a cancel — hence the
            /// lower bar (and a hair of tolerance for rounding) while the gap is open.
            /// Dragging back *through* that resting position, toward the content top, is
            /// unambiguously a cancel.
            private var releaseArmingOverscroll: CGFloat {
                gapOpen ? min(threshold, refreshGap) - 0.5 : threshold
            }

            @objc private func liveScrollEnded() {
                finishPullGesture(fromLiveScroll: true)
            }

            private func mousePullEnded() {
                finishPullGesture(fromLiveScroll: false)
            }

            /// Arms a mouse-driven pull: reset peak tracking and re-capture baseline.
            private func beginMousePull() {
                isMousePulling = true
                overscroll = 0
                peakOverscroll = 0
                if !gapOpen, !isClosingGap, let scrollView {
                    baselineTopInset = scrollView.contentInsets.top
                }
            }

            /// Test hook for mouse pulls that never post live-scroll notifications.
            func beginMousePullForTesting() {
                beginMousePull()
            }

            func mousePullEndedForTesting() {
                mousePullEnded()
            }

            private func finishPullGesture(fromLiveScroll: Bool) {
                if fromLiveScroll {
                    isLiveScrolling = false
                } else {
                    guard isMousePulling else { return }
                    isMousePulling = false
                }
                let shouldTrigger = overscroll >= releaseArmingOverscroll
                overscroll = 0
                peakOverscroll = 0
                if shouldTrigger {
                    // A pull that arms while a refresh is already running must not restart
                    // the action (SwiftUI guards that), but announce so VoiceOver is not
                    // silent when the gesture completes with no visible change.
                    if currentRefreshing || wasRefreshing {
                        announce(PullRefreshAccessibility.refreshAlreadyInProgress)
                        setPull(0)
                        return
                    }
                    // Leave the pull at full reveal across the hand-off: `currentRefreshing`
                    // only flips once `setRefreshing(true)` arrives via `updateNSView`, and
                    // zeroing the pull before then renders the indicator at opacity 0 for
                    // those frames, blinking it out exactly where it should come alive.
                    awaitingRefreshHandoff = true
                    onTrigger()
                    scheduleHandoffFallback()
                } else {
                    setPull(0)
                    closeGap()
                }
            }

            /// Clears a pull left at full reveal for a hand-off that never happened — the
            /// refresh finished before SwiftUI could round-trip the flag, or the trigger
            /// was swallowed because one was already in flight. Without this the indicator
            /// would sit on screen spinning with nothing behind it.
            private func scheduleHandoffFallback() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, self.awaitingRefreshHandoff else { return }
                    self.awaitingRefreshHandoff = false
                    guard !self.currentRefreshing, !self.isLiveScrolling else { return }
                    self.setPull(0)
                }
            }

            /// Opens the refresh gap for a programmatic start (no mid-pull reserve).
            func openGapForRefresh() {
                guard let scrollView else { return }

                if !gapOpen, !isClosingGap {
                    baselineTopInset = scrollView.contentInsets.top
                }
                openGap()
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

            /// Short lists whose document is shorter than the clip view cannot rubber-band
            /// unless the document is at least one point taller than the visible area.
            private func ensureScrollableRubberBand(in scrollView: NSScrollView) {
                guard let document = scrollView.documentView else { return }

                let visibleHeight = scrollView.contentView.bounds.height
                // A document that is taller than our +1 bump is naturally scrollable (or was
                // replaced). Drop bump bookkeeping so we do not shrink it on the next pass.
                if document.frame.height > visibleHeight + 1 {
                    originalDocumentHeight = nil
                    return
                }
                if document.frame.height <= visibleHeight {
                    if originalDocumentHeight == nil {
                        originalDocumentHeight = document.frame.height
                    }
                    document.frame.size.height = visibleHeight + 1
                } else if let original = originalDocumentHeight, original <= visibleHeight {
                    // Still on our bump after a clip resize — keep it one point past the clip.
                    document.frame.size.height = visibleHeight + 1
                }
            }

            func closeGap() {
                guard let scrollView, gapOpen else { return }

                gapOpen = false
                isClosingGap = true
                // Capture the baseline now, while it is still known to be the baseline.
                // Re-reading `self.baselineTopInset` in the completion handler instead
                // reads it 300ms later, by which time a scroll started during the
                // animation may have re-captured it from the still-enlarged gap inset.
                let baseline = baselineTopInset
                let clip = scrollView.contentView
                let generation = connectionGeneration
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
                    clip.animator().setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: -baseline))
                    scrollView.reflectScrolledClipView(clip)
                } completionHandler: { [weak self] in
                    Task { @MainActor in
                        guard let self, self.connectionGeneration == generation else { return }

                        self.isClosingGap = false
                        guard let scrollView = self.scrollView else { return }

                        // A fresh pull may have re-opened the gap while this animation ran,
                        // in which case the enlarged inset it just installed is the current
                        // truth and must be left alone.
                        guard !self.gapOpen else { return }

                        // The content has arrived at the resting top; removing the gap
                        // inset now doesn't shift it further (position tracks the origin,
                        // not the inset), so the hand-off is seamless.
                        scrollView.contentInsets.top = baseline
                        if let original = self.originalAutoInsets {
                            scrollView.automaticallyAdjustsContentInsets = original
                        }
                    }
                }
            }

            isolated deinit { disconnect() }
        }
    }
    // swiftlint:enable type_body_length
#endif
