# ``MacPullToRefresh``

Native-feeling pull-to-refresh for macOS SwiftUI.

## Overview

`MacPullToRefresh` adds a macOS pull gesture to SwiftUI scroll containers by bridging to
the underlying `NSScrollView` and observing real over-scroll past the top edge. On iOS, the
same modifier forwards to SwiftUI's native `.refreshable`.

Apply ``SwiftUICore/View/macPullToRefresh(_:)`` to a `List` or `ScrollView` and provide
an async refresh action.

## Topics

### Refreshing

- ``SwiftUICore/View/macPullToRefresh(_:)``
