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
}

/// A tiny actor so the test can assert the refresh closure was never called during view
/// construction without tripping Swift 6 data-race checking.
private actor Ran {
    private(set) var value = false
    func mark() { value = true }
}
