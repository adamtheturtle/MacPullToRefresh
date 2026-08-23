// swift-tools-version: 6.2
import Foundation
import PackageDescription

let buildDocumentation = ProcessInfo.processInfo.environment["MACPULL_BUILD_DOCS"] != nil

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
            exclude: buildDocumentation ? [] : ["MacPullToRefresh.docc"],
            resources: buildDocumentation ? [.copy("MacPullToRefresh.docc")] : [],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances")
            ]
        ),
        .executableTarget(
            name: "Demo",
            dependencies: ["MacPullToRefresh"],
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

if buildDocumentation {
    package.dependencies.append(
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
    )
}
