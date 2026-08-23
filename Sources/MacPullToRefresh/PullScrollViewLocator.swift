#if os(macOS)
    import AppKit

    /// Locates the `NSScrollView` a pull-to-refresh helper should bridge to.
    enum PullScrollViewLocator {
        /// Prefers the innermost scroll view whose hierarchy contains `view`. When the
        /// helper sits outside any scroll view (typical `List` background placement),
        /// walks only `view.window` and picks the smallest scroll view whose frame
        /// contains the helper — i.e. a `NavigationSplitView` detail column, not a
        /// neighbouring pane.
        static func scrollView(near view: NSView) -> NSScrollView? {
            var node: NSView? = view
            while let current = node {
                if let scroll = current.enclosingScrollView {
                    return scroll
                }
                node = current.superview
            }

            guard let window = view.window, let root = window.contentView else { return nil }

            let point = view.convert(
                CGPoint(x: view.bounds.midX, y: view.bounds.midY),
                to: root
            )
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
    }
#endif
