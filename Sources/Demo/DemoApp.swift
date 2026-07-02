//
//  DemoApp.swift
//  Demo
//
//  A minimal app for trying MacPullToRefresh live. Run the "Demo" scheme (⌘R),
//  then drag the list down past the top with a trackpad (two-finger swipe) to
//  rubber-band past the top edge and trigger a refresh.
//

import AppKit
import MacPullToRefresh
import SwiftUI

@main
struct DemoApp: App {
    // A SwiftPM executable launches without an app bundle, so macOS starts it as a
    // background process and the window never comes forward. The delegate promotes
    // it to a regular app and activates it so the window is actually visible.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("MacPullToRefresh Demo") {
            DemoView()
                .frame(minWidth: 360, minHeight: 480)
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

private struct DemoView: View {
    @State private var rows = Array(1 ... 20)
    @State private var refreshCount = 0

    var body: some View {
        List {
            Section("Pull down to refresh · refreshed \(refreshCount)×") {
                ForEach(rows, id: \.self) { row in
                    Text("Row \(row)")
                }
            }
        }
        .macPullToRefresh {
            // Simulate a network round-trip so the spinner is visible, then
            // prepend a fresh row as visible proof the refresh ran.
            try? await Task.sleep(for: .seconds(1.5))
            refreshCount += 1
            let next = (rows.first ?? 0) - 1
            rows.insert(next, at: 0)
        }
    }
}
