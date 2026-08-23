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
| Mac Catalyst | Supported via iOS path | Uses `.refreshable`. Verify "Designed for iPad" vs scaled Mac idiom in your host app |
| visionOS | Not supported | No platform declaration in `Package.swift`. Do not depend on this product for visionOS targets |

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
Call refresh actions that touch UI or SwiftUI `@State` from that same isolation. The
modifier already resumes on the main actor when it clears the in-flight refresh flag.

## Supported scroll containers

Attach the modifier directly to the scrollable container you want to refresh:

| Container | Notes |
| --- | --- |
| `List` | Supported. Background placement resolves the list's `NSScrollView` via window lookup. |
| `ScrollView` / `LazyVStack` | Supported. Background lands inside the scroll view. |
| `Form` / grouped `List` style | Supported when backed by a scroll view. Attach to the form or list itself. |
| `Table` / `OutlineGroup` | Supported when AppKit provides an `NSScrollView` under the modified view. |
| `NavigationSplitView` detail | Supported. Lookup is scoped to the helper's window and smallest scroll view at the helper's point, so sidebar lists are not picked by mistake. |
| `ScrollView` + pinned section headers | Supported. The bridge tracks the scroll view hosting the modified content. Keep the modifier on the same `ScrollView` that owns the pinned header. |

## RTL layout

The indicator is a centered spoke wheel with no directional chevrons. It remains visually
correct in right-to-left layouts because reveal and spin are symmetric around the center.

## Topics

### Refreshing

- ``SwiftUICore/View/macPullToRefresh(_:)``

### Indicator

- ``PullIndicator``
- ``PullIndicator/continuouslyRotates(pull:isRefreshing:reduceMotion:)``

### Accessibility testing

- ``HostedIndicator``
- ``HostedIndicator/accessibilityStatus(pull:isRefreshing:)``

### Accessibility

- ``PullRefreshAccessibility``
