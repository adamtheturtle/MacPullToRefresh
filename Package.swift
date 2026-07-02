// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacPullToRefresh",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(name: "MacPullToRefresh", targets: ["MacPullToRefresh"])
    ],
    targets: [
        .target(
            name: "MacPullToRefresh",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances")
            ]
        ),
        .testTarget(
            name: "MacPullToRefreshTests",
            dependencies: ["MacPullToRefresh"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances")
            ]
        )
    ]
)
