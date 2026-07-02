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
        /// releasing triggers a refresh. Sized so there's a visible ramp between the
        /// indicator appearing and arming, rather than snapping straight to armed.
        private let threshold: CGFloat = 44

        /// 0…1 as the user drags past the top; drives the indicator's reveal.
        @State private var pull: CGFloat = 0
        @State private var isRefreshing = false

        func body(content: Content) -> some View {
            content
                .background(
                    PullToRefreshScrollBridge(threshold: threshold, pull: $pull) {
                        guard !isRefreshing else { return }

                        isRefreshing = true
                        Task {
                            await action()
                            isRefreshing = false
                        }
                    }
                )
                .overlay(alignment: .top) {
                    // Visible whenever the user is mid-pull or a refresh is running.
                    if isRefreshing || pull > 0 {
                        PullIndicator(pull: pull, isRefreshing: isRefreshing)
                    }
                }
        }
    }

    /// The floating pull-to-refresh indicator: a ring that fills as the content is
    /// dragged toward the threshold and then morphs into a spinning arc while the
    /// refresh runs. Extracted from the modifier so it can be driven directly from
    /// fixed `pull`/`isRefreshing` values (and rendered in a preview).
    private struct PullIndicator: View {
        /// 0…1 as the user drags past the top.
        var pull: CGFloat
        var isRefreshing: Bool

        /// Drives the indeterminate spin while a refresh is in flight. Toggled on when
        /// `isRefreshing` becomes true so the arc rotates continuously.
        @State private var spin = false
        /// The chevron's point size, scaled with the user's preferred text size
        /// (tracking Caption 2) so it honors the accessibility setting.
        @ScaledMetric(relativeTo: .caption2) private var chevronSize: CGFloat = 9

        /// Whether the user has pulled far enough that releasing will refresh.
        private var isArmed: Bool { pull >= 1 }

        /// How much of the ring is drawn: it tracks the pull while dragging, then
        /// settles to a short segment that spins as the indeterminate refresh arc.
        private var arcEnd: CGFloat { isRefreshing ? 0.22 : pull }

        /// Grows from a nub toward full size as the pull nears the threshold, with a
        /// small pop once armed, then holds full size while refreshing.
        private var indicatorScale: CGFloat {
            if isRefreshing { return 1 }
            return max(0.65, pull) * (isArmed ? 1.06 : 1)
        }

        /// Fades in with the pull and stays solid while refreshing.
        private var indicatorOpacity: Double {
            isRefreshing ? 1 : Double(min(1, pull * 1.4))
        }

        /// Slides the indicator down out of the top edge as the user drags, so it
        /// follows the rubber-banding content instead of hanging at a fixed spot.
        private var indicatorOffset: CGFloat {
            (isRefreshing ? 1 : pull) * 14
        }

        var body: some View {
            ZStack {
                // The track the arc rides on.
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 2.5)
                // A single arc serves both roles: a determinate fill that follows
                // the pull, then a short segment that spins during the refresh.
                // Keeping one shape lets the two states morph into each other
                // rather than swapping a ring out for a separate spinner.
                Circle()
                    .trim(from: 0, to: arcEnd)
                    .stroke(Color.accentColor,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                // The chevron flips up to signal "release to refresh", then fades
                // out as the arc takes over the spinning role.
                Image(systemName: "chevron.down")
                    .font(.system(size: chevronSize, weight: .bold))
                    .foregroundStyle(isArmed ? Color.accentColor : Color.secondary)
                    // Stay flipped up while refreshing so it fades out pointing up
                    // instead of rotating back down as the arc takes over.
                    .rotationEffect(.degrees(isArmed || isRefreshing ? 180 : 0))
                    .opacity(isRefreshing ? 0 : 1)
                    .scaleEffect(isRefreshing ? 0.4 : 1)
            }
            .frame(width: 18, height: 18)
            .padding(8)
            // A floating indicator above the scrolling list, so it gets Liquid
            // Glass to refract the content sliding under it on macOS 26, keeping
            // the opaque material as the macOS 15 fallback.
            .floatingGlass(in: Circle(), fallback: .regularMaterial)
            .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
            .scaleEffect(indicatorScale)
            .opacity(indicatorOpacity)
            .offset(y: indicatorOffset)
            .padding(.top, 6)
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isRefreshing)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isArmed)
            .allowsHitTesting(false)
            // Runs on appearance and each time `isRefreshing` flips (`.task(id:)` is
            // available back to macOS 12, unlike the two-parameter `onChange`).
            .task(id: isRefreshing) {
                if isRefreshing {
                    // Kick off the endless rotation that turns the progress arc
                    // into an indeterminate spinner.
                    withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                        spin = true
                    }
                } else {
                    // Snap straight back to the resting angle; the indicator is
                    // fading out at this point, so there's no need to unwind the spin.
                    var stop = Transaction()
                    stop.disablesAnimations = true
                    withTransaction(stop) { spin = false }
                }
            }
        }
    }

    private extension View {
        /// Backs the view with Liquid Glass in `shape` on macOS 26, falling back to
        /// `fallback` painted in the same shape on earlier systems.
        @ViewBuilder
        func floatingGlass(in shape: some Shape, fallback: some ShapeStyle) -> some View {
            if #available(macOS 26, *) {
                glassEffect(.regular, in: shape)
            } else {
                background(fallback, in: shape)
            }
        }
    }

    #Preview("Indicator states") {
        HStack(spacing: 44) {
            VStack { PullIndicator(pull: 0.5, isRefreshing: false); Text("pulling") }
            VStack { PullIndicator(pull: 1, isRefreshing: false); Text("armed") }
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
        @Binding var pull: CGFloat
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
            context.coordinator.threshold = threshold
            context.coordinator.pull = $pull
            context.coordinator.onTrigger = onTrigger
            // Retry in case the scroll view wasn't reachable at first window attach.
            context.coordinator.connect(from: nsView)
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
            var pull: Binding<CGFloat>?
            var onTrigger: () -> Void = {}

            private weak var scrollView: NSScrollView?
            private var overscroll: CGFloat = 0
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
            }

            @objc private func liveScrollStarted() {
                isLiveScrolling = true
                overscroll = 0
                peakOverscroll = 0
            }

            @objc private func boundsChanged() {
                // Ignore bounds changes that aren't part of a user scroll (launch, list
                // reloads, programmatic layout) so the indicator only reveals on a pull.
                guard isLiveScrolling, let scrollView else { return }

                // A `List` uses a flipped clip view, so the visible origin dips below
                // zero as the content rubber-bands past the top edge.
                overscroll = max(0, -scrollView.contentView.bounds.origin.y)
                peakOverscroll = max(peakOverscroll, overscroll)
                // This AppKit notification can fire while SwiftUI is mid-layout (e.g. when
                // the list reloads), so defer the @State write to the next runloop tick to
                // avoid "modifying state during view update". `overscroll`/`peakOverscroll`
                // stay in sync synchronously, so the release trigger stays accurate.
                //
                // Drive the indicator from the peak, not the instantaneous over-scroll, so
                // the ring/chevron latch once armed and match the peak-based release: the
                // over-scroll eases back before the finger lifts, and tracking that live
                // would flip the chevron back down even though releasing still refreshes.
                let newPull = min(1, peakOverscroll / threshold)
                DispatchQueue.main.async { [weak self] in
                    self?.pull?.wrappedValue = newPull
                }
            }

            @objc private func liveScrollEnded() {
                isLiveScrolling = false
                // Decide on the peak reached during the drag: the over-scroll eases
                // back before the finger lifts, so the instantaneous value here is
                // often already below the threshold even after a firm pull.
                let shouldTrigger = peakOverscroll >= threshold
                overscroll = 0
                peakOverscroll = 0
                DispatchQueue.main.async { [weak self] in
                    self?.pull?.wrappedValue = 0
                    if shouldTrigger { self?.onTrigger() }
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
