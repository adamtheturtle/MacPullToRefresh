// swift-tools-version: 5.9
import Foundation
import PackageDescription

let buildDocumentation = ProcessInfo.processInfo.environment["MACPULL_BUILD_DOCS"] != nil

let package = Package(
    name: "MacPullToRefresh",
    defaultLocalization: "en",
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
            // Keep the DocC catalog in the target so Swift Package Index (and local
            // doc builds) always see curated overview/topics. Do not put it in `exclude`
            // or `resources` — DocC discovers `.docc` catalogs from target sources.
            resources: [
                .process("Localizable.xcstrings")
            ],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances")
            ]
        ),
        .executableTarget(
            name: "Demo",
            dependencies: ["MacPullToRefresh"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances")
            ]
        ),
        .testTarget(
            name: "MacPullToRefreshTests",
            dependencies: ["MacPullToRefresh"],
            swiftSettings: [
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
