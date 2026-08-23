#if os(macOS)
    import AppKit
    import Foundation

    /// User-facing accessibility copy for the macOS pull-to-refresh bridge.
    public enum PullRefreshAccessibility {
        public static let refreshLabel = String(
            localized: "Refresh",
            defaultValue: "Refresh",
            bundle: .module,
            comment: "VoiceOver label for the pull-to-refresh indicator"
        )
        public static let refreshHint = String(
            localized: "Pull down to refresh",
            defaultValue: "Pull down to refresh",
            bundle: .module,
            comment: "VoiceOver hint describing the pull gesture"
        )
        public static let refreshing = String(
            localized: "Refreshing",
            defaultValue: "Refreshing",
            bundle: .module,
            comment: "VoiceOver value while a refresh is running"
        )
        public static let refreshComplete = String(
            localized: "Refresh complete",
            defaultValue: "Refresh complete",
            bundle: .module,
            comment: "VoiceOver announcement when a refresh finishes"
        )
        public static let ready = String(
            localized: "Ready",
            defaultValue: "Ready",
            bundle: .module,
            comment: "VoiceOver value when the pull has passed the arming threshold"
        )
        public static let pulling = String(
            localized: "Pulling",
            defaultValue: "Pulling",
            bundle: .module,
            comment: "VoiceOver value while the user is pulling but not yet armed"
        )

        /// VoiceOver value while pulling, including progress toward the arming threshold.
        public static func pullingProgress(percent: Int) -> String {
            let format = String(
                localized: "Pulling, %lld percent",
                defaultValue: "Pulling, %lld percent",
                comment: "VoiceOver value while pulling; percent is 0–99 progress toward arming"
            )
            return String(format: format, locale: .current, Int64(percent))
        }
        public static let refreshAlreadyInProgress = String(
            localized: "Refresh already in progress",
            defaultValue: "Refresh already in progress",
            comment: "VoiceOver announcement when a pull completes while a refresh is running"
        )
    }
#endif
