# Changelog

This file documents project changes.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-08-05

### Fixed

- Restore scroll view insets, elasticity, and bounds notifications when the modifier
  detaches mid-refresh or mid-animation.
- Expose VoiceOver status for the refresh indicator and announce refresh start and
  completion.
- Honor Reduce Motion by skipping continuous indicator rotation.

## [0.4.0] - 2026-07-18

### Fixed

- Cancel a pull when the user drags back to the top before releasing.
- Keep the baseline top inset stable if a scroll starts during gap-close animation.
- Avoid a one-frame spinner blink at the hand-off from pull to refresh.

## [0.3.1] - 2026-07-02

### Changed

- Anchor the indicator in the clip view so it rides with content without lag.
- Drive spin from a wall-clock angle for a steady rotation rate.

## [0.3.0] - 2026-07-02

### Added

- iOS-style spoke-wheel indicator with pull reveal and refresh spin.

## [0.2.0] - 2026-07-02

### Added

- Cross-platform `.macPullToRefresh` that forwards to `.refreshable` on iOS.

## [0.1.0] - 2026-07-02

### Added

- Initial macOS pull-to-refresh bridge over `NSScrollView` over-scroll.

[Unreleased]: https://github.com/adamtheturtle/MacPullToRefresh/compare/0.5.0...HEAD
[0.5.0]: https://github.com/adamtheturtle/MacPullToRefresh/compare/0.4.0...0.5.0
[0.4.0]: https://github.com/adamtheturtle/MacPullToRefresh/compare/0.3.1...0.4.0
[0.3.1]: https://github.com/adamtheturtle/MacPullToRefresh/compare/0.3.0...0.3.1
[0.3.0]: https://github.com/adamtheturtle/MacPullToRefresh/compare/0.2.0...0.3.0
[0.2.0]: https://github.com/adamtheturtle/MacPullToRefresh/compare/0.1.0...0.2.0
[0.1.0]: https://github.com/adamtheturtle/MacPullToRefresh/releases/tag/0.1.0
