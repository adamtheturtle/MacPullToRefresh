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

iOS 16 is the floor because SwiftUI's `.refreshable` is the iOS refresh path. Raising or
lowering that floor should track SwiftUI refresh-control availability, not the macOS bridge.

## Reduce Motion

When Reduce Motion is enabled, ``PullIndicator`` skips continuous wall-clock rotation and
ease-out transitions. The spoke wheel still reveals with the pull and can show a static
"armed" layout while refreshing, matching the expectation of a calm, non-spinning control.

## ScrollView vs List placement

On macOS, attach the modifier to the scrollable container itself:

- Prefer `.macPullToRefresh { ... }` on the `List` or `ScrollView` that should refresh.
- Avoid wrapping an outer `VStack` or navigation chrome and expecting the inner list to
  rubber-band: the bridge locates the nearest `NSScrollView` under the modified view.
- A `ScrollView`'s `.background` lands inside its scroll view, so the enclosing scroll view
  is used directly. A `List` places the background outside its scroll view, so the bridge
  falls back to the smallest window scroll view whose frame contains the helper.

## MainActor isolation

The package enables Swift 6 default `MainActor` isolation. Public entry points such as
``SwiftUICore/View/macPullToRefresh(_:)`` and the macOS bridge types run on the main actor.
Call refresh actions that touch UI or SwiftUI `@State` from that same isolation; the
modifier already resumes on the main actor when it clears the in-flight refresh flag.

## Topics

### Refreshing

- ``SwiftUICore/View/macPullToRefresh(_:)``

### Indicator

- ``PullIndicator``
- ``PullIndicator/continuouslyRotates(pull:isRefreshing:reduceMotion:)``

### Accessibility testing

- ``HostedIndicator``
- ``HostedIndicator/accessibilityStatus(pull:isRefreshing:)``
