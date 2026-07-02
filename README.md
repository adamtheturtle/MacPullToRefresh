# MacPullToRefresh

A native-feeling **pull-to-refresh for macOS SwiftUI**, backed by the real `NSScrollView`
rubber-band — and it works with `List`, not just `ScrollView`.

SwiftUI's `.refreshable` compiles on macOS but **never fires from a gesture**: AppKit has
no system pull-to-refresh control, so there's nothing for it to hook. The cross-platform
"pure SwiftUI" packages work around this by tracking scroll offset manually, which doesn't
feel native (no elastic coupling). MacPullToRefresh instead bridges to the `NSScrollView`
underneath your SwiftUI container and tracks genuine over-scroll past the top edge, so the
gesture feels like the rest of the system.

On iOS it simply forwards to the native `.refreshable`, so a single call site works on both
platforms without an `#if`.

## Why this one

- **Native `NSScrollView` over-scroll** — hooks `willStartLiveScroll` / bounds changes, not
  a hand-rolled offset hack, so pulls feel native.
- **Works with SwiftUI `List`** — `List` places its background *outside* its scroll view, a
  quirk that trips up naive introspection; MacPullToRefresh finds the right scroll view
  anyway. Plain `ScrollView` works too.
- **Liquid Glass indicator** — the pull indicator uses `glassEffect` on macOS 26, with an
  opaque-material fallback on earlier systems.
- **Polished** — a fill-as-you-pull ring with a "release to refresh" chevron, an
  accessibility-scaled indicator (`@ScaledMetric`), `async` refresh actions, and live-scroll
  gating so it never false-triggers during launch or list reloads.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/adamtheturtle/MacPullToRefresh.git", from: "0.1.0")
]
```

Then depend on the `MacPullToRefresh` product from your target. Requires macOS 13+ / iOS
16+, built with the macOS 26 SDK (Xcode 26+).

## Usage

Apply `.macPullToRefresh` to any scrollable container:

```swift
import MacPullToRefresh
import SwiftUI

struct ContentView: View {
    @State private var items: [Item] = []

    var body: some View {
        List(items) { item in
            Text(item.title)
        }
        .macPullToRefresh {
            items = await loadItems()   // async; the indicator spins until it returns
        }
    }
}
```

The same call works with a `ScrollView`, and on iOS it becomes a plain `.refreshable`, so
you never need to branch on platform.

## Testing note

The heart of this package is an AppKit `NSScrollView` bridge, whose behavior (over-scroll
tracking, live-scroll gating) needs a real window and run loop — exercise it in your app's
UI tests. The included unit tests cover what's meaningful headlessly: the modifier applies
to a view and doesn't run the action at build time.

## License

MIT — see [LICENSE](LICENSE).
