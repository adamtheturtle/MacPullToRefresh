# ``MacPullToRefresh``

Native-feeling pull-to-refresh for macOS SwiftUI.

## Overview

`MacPullToRefresh` adds a macOS pull gesture to SwiftUI scroll containers by bridging to
the underlying `NSScrollView` and observing real over-scroll past the top edge. On iOS, the
same modifier forwards to SwiftUI's native `.refreshable`.

Apply ``SwiftUICore/View/macPullToRefresh(_:)`` to a `List` or `ScrollView` and provide
an async refresh action.

## Platform support

| Platform | Status | Notes |
| --- | --- | --- |
| macOS 13+ | Supported | AppKit `NSScrollView` over-scroll bridge and custom indicator |
| iOS 16+ | Supported | Forwards to SwiftUI `.refreshable` (native control) |
| Mac Catalyst | Supported via iOS path | Uses `.refreshable`; verify "Designed for iPad" vs scaled Mac idiom in your host app |
| visionOS | Not supported | No platform declaration in `Package.swift`; do not depend on this product for visionOS targets |

iOS 16 is the floor because SwiftUI's `.refreshable` is the iOS implementation. Raising or
lowering that floor should track SwiftUI refresh-control availability, not the macOS bridge.

## Reduce Motion

When Reduce Motion is enabled, ``PullIndicator`` skips continuous wall-clock rotation and
ease-out transitions. The spoke wheel still reveals with the pull and can show a static
"armed" layout while refreshing, matching the expectation of a calm, non-spinning control.

## Topics

### Refreshing

- ``SwiftUICore/View/macPullToRefresh(_:)``
