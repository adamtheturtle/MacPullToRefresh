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
    }
#endif
