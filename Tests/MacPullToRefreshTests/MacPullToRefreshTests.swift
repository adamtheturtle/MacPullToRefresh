//
//  MacPullToRefreshTests.swift
//  MacPullToRefreshTests
//
//  The value of this package is the AppKit `NSScrollView` bridge, which needs a real
//  window/run loop to exercise (over-scroll notifications, live-scroll gating) and so
//  belongs in a host app's UI tests. These checks cover what's testable headlessly: the
//  modifier is applicable to a view and produces a non-empty view tree on every platform.
//

import SwiftUI
import Testing

@testable import MacPullToRefresh

@Suite("macPullToRefresh modifier")
struct MacPullToRefreshTests {
    @Test
    func `a custom indicator builder compiles`() {
        let view = List { Text("row") }
            .macPullToRefresh(
                indicator: { pull, refreshing in
                    Text(refreshing ? "busy" : "\(Int(pull * 100))")
                },
                { }
            )
        #expect(view is (any View))
    }

    @Test
    func `the modifier accepts a programmatic trigger`() {
        let view = List { Text("row") }
            .macPullToRefresh(trigger: 0 as UInt64) { }
        #expect(view is (any View))
    }

    @Test
    func `the trigger overload accepts custom threshold and gap`() {
        let view = List { Text("row") }
            .macPullToRefresh(trigger: 0 as UInt64, threshold: 60, refreshGap: 48) { }
        #expect(view is (any View))
    }

    @Test
    func `the modifier can be applied to a scrollable container`() {
        // Compiles and returns a View unconditionally - the point of the cross-platform
        // API is that a call site applies it without an #if.
        let view = List { Text("row") }
            .macPullToRefresh { }
        #expect(view is (any View))
    }

    @Test
    func `the action closure is stored, not run at build time`() async {
        // Applying the modifier must not invoke the refresh action; it runs only on a
        // release-past-threshold gesture (macOS) or the native control (iOS).
        let ran = Ran()
        _ = ScrollView { Text("content") }
            .macPullToRefresh { await ran.mark() }
        #expect(await ran.value == false)
    }

    @Test
    func `non-positive thresholds fall back to the default distance`() {
        #expect(sanitizedPullDistance(0, fallback: 44) == 44)
        #expect(sanitizedPullDistance(-12, fallback: 44) == 44)
        #expect(sanitizedPullDistance(.nan, fallback: 44) == 44)
        #expect(sanitizedPullDistance(.infinity, fallback: 44) == 44)
        #expect(sanitizedPullDistance(60, fallback: 44) == 60)
    }

    @Test
    func `custom threshold and gap compile on the modifier`() {
        let view = List { Text("row") }
            .macPullToRefresh(threshold: 60, refreshGap: 48) { }
        #expect(view is (any View))
    }

    @Test
    func `a disabled modifier remains a plain view`() {
        let view = List { Text("row") }
            .macPullToRefresh(isEnabled: false) { }
        #expect(view is (any View))
    }

    @Test
    func `a throwing action is accepted by the modifier`() {
        enum Sample: Error { case boom }
        let view = List { Text("row") }
            .macPullToRefresh { throw Sample.boom }
        #expect(view is (any View))
    }

    #if os(macOS)
        @Test
        func `accessibility strings resolve from the package bundle`() {
            #expect(PullRefreshAccessibility.refreshLabel == "Refresh")
            #expect(PullRefreshAccessibility.refreshHint == "Pull down to refresh")
            #expect(PullRefreshAccessibility.refreshing == "Refreshing")
        }
    #endif
}

/// A tiny actor so the test can assert the refresh closure was never called during view
/// construction.
private actor Ran {
    private(set) var value = false
    func mark() { value = true }
}
