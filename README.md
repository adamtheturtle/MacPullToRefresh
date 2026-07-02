# MacPullToRefresh

Native-feeling pull-to-refresh for macOS SwiftUI, backed by `NSScrollView` over-scroll and
forwarded to `.refreshable` on iOS.

[Documentation](https://swiftpackageindex.com/adamtheturtle/MacPullToRefresh/documentation/macpulltorefresh) |
[Swift Package Index](https://swiftpackageindex.com/adamtheturtle/MacPullToRefresh)

## Demo

<video src="https://github.com/adamtheturtle/MacPullToRefresh/raw/main/Documentation/pull-to-refresh.mp4" controls muted playsinline width="360"></video>

Pull past the top of a `List` or `ScrollView`: the indicator fills as you drag,
arms once you pass the threshold, and spins while the refresh runs.

> If the player above doesn't load, [watch the clip directly](Documentation/pull-to-refresh.mp4).

## Installation

```swift
.package(url: "https://github.com/adamtheturtle/MacPullToRefresh.git", from: "0.2.0")
```

Add the `MacPullToRefresh` product to your target dependencies.

## Product

- `MacPullToRefresh`: A SwiftUI modifier for pull-to-refresh on macOS and iOS.

## Requirements

- Swift 6.2+
- macOS 13+ or iOS 16+

## License

MIT. See [LICENSE](LICENSE).
