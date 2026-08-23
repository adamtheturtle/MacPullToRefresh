//
//  DemoApp.swift
//  Demo
//
//  A minimal app for trying MacPullToRefresh live. Run the "Demo" scheme (⌘R),
//  then drag the list or scroll view down past the top with a trackpad (two-finger
//  swipe) to rubber-band past the top edge and trigger a refresh.
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
        WindowGroup("Pull down to refresh") {
            DemoRootView()
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

private struct DemoRootView: View {
    var body: some View {
        TabView {
            ListDemoView()
                .tabItem { Text("List") }
            ScrollViewDemoView()
                .tabItem { Text("ScrollView") }
        }
    }
}

private struct ListDemoView: View {
    @State private var rows = Array(1 ... 20)

    var body: some View {
        // Plain rows, no pinned section header — so the spinner clearly sits above the
        // content and nothing crosses it during the pull. The row count doubles as
        // visible proof each refresh ran.
        List(rows, id: \.self) { row in
            Text("Row \(row)")
        }
        .macPullToRefresh {
            try? await Task.sleep(for: .seconds(1.5))
            let next = (rows.first ?? 0) - 1
            rows.insert(next, at: 0)
        }
    }
}

private struct ScrollViewDemoView: View {
    @State private var rows = Array(1 ... 20)

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(rows, id: \.self) { row in
                    Text("Row \(row)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                }
            }
            .padding(.vertical, 8)
        }
        .macPullToRefresh {
            try? await Task.sleep(for: .seconds(1.5))
            let next = (rows.first ?? 0) - 1
            rows.insert(next, at: 0)
        }
    }
}
