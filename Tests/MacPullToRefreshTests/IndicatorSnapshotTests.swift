#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing

    @testable import MacPullToRefresh

    @Suite("PullIndicator snapshots")
    @MainActor
    struct PullIndicatorSnapshotTests {
        @Test
        func `pull indicator renders at common states`() {
            for (pull, refreshing, label) in [
                (0.4, false, "pulling"),
                (1.0, false, "ready"),
                (0.0, true, "refreshing")
            ] {
                let view = PullIndicator(pull: pull, isRefreshing: refreshing)
                    .frame(width: 32, height: 32)
                let renderer = ImageRenderer(content: view)
                let image = renderer.nsImage
                #expect(image != nil, "expected \(label) snapshot")
                #expect(image?.size.width ?? 0 >= 24)
                #expect(image?.size.height ?? 0 >= 24)
            }
        }
    }
#endif
