#if os(macOS)
    import AppKit
    import SwiftUI

    /// Owns the clip-view `NSHostingView` that renders the refresh indicator.
    ///
    /// Keeps a single hosting view per bridge attachment and updates `rootView` in place
    /// so AppKit does not accumulate indicator subviews across pulls.
    @MainActor
    final class PullIndicatorHost {
        private var hostingView: NSHostingView<AnyView>?
        private var makeIndicator: (CGFloat, Bool) -> AnyView = { pull, refreshing in
            AnyView(HostedIndicator(pull: pull, isRefreshing: refreshing)
                .frame(maxWidth: .infinity, maxHeight: .infinity))
        }

        private(set) var pull: CGFloat = 0
        private(set) var isRefreshing = false

        func configure(_ builder: @escaping (CGFloat, Bool) -> AnyView) {
            makeIndicator = builder
            hostingView?.rootView = makeIndicator(pull, isRefreshing)
        }

        func attach(to scrollView: NSScrollView, refreshGap: CGFloat) {
            guard hostingView == nil else { return }

            let host = NSHostingView(rootView: makeIndicator(pull, isRefreshing))
            host.autoresizingMask = [.width]
            hostingView = host
            scrollView.contentView.addSubview(host)
            position(in: scrollView, refreshGap: refreshGap)
        }

        func reposition(in scrollView: NSScrollView, refreshGap: CGFloat) {
            guard let hostingView else { return }

            if hostingView.superview !== scrollView.contentView {
                scrollView.contentView.addSubview(hostingView)
            }
            position(in: scrollView, refreshGap: refreshGap)
        }

        func setPull(_ value: CGFloat) {
            pull = value
            hostingView?.rootView = makeIndicator(value, isRefreshing)
        }

        func setRefreshing(_ value: Bool) {
            guard value != isRefreshing else { return }

            isRefreshing = value
            pull = 0
            hostingView?.rootView = makeIndicator(0, value)
        }

        func removeFromSuperview() {
            hostingView?.removeFromSuperview()
            hostingView = nil
            pull = 0
            isRefreshing = false
        }

        private func position(in scrollView: NSScrollView, refreshGap: CGFloat) {
            guard let hostingView else { return }

            let clip = scrollView.contentView
            hostingView.frame = NSRect(
                x: 0,
                y: -refreshGap,
                width: clip.bounds.width,
                height: refreshGap
            )
        }
    }
#endif
