import QtQuick
import org.kde.kirigami as Kirigami

QtObject {
    // Semantic status colors derived from the active Kirigami/Plasma theme.
    // These automatically adapt to Breeze Light, Breeze Dark, and third-party themes.

    readonly property color positive:  Kirigami.Theme.positiveTextColor
    readonly property color neutral:   Kirigami.Theme.neutralTextColor
    readonly property color negative:  Kirigami.Theme.negativeTextColor
    readonly property color info:      Kirigami.Theme.linkColor
    readonly property color disabled:  Kirigami.Theme.disabledTextColor

    // Maps a status level string to the appropriate theme color.
    // Accepts common status vocabulary from all widgets in the portfolio.
    function forLevel(level) {
        switch (level) {
            case "ok":
            case "good":
            case "green":
            case "healthy":
            case "operational":
            case "resolved":
                return positive

            case "warn":
            case "warning":
            case "orange":
            case "degraded":
            case "degraded_performance":
            case "partial_outage":
            case "suspect":
                return neutral

            case "error":
            case "critical":
            case "red":
            case "major_outage":
            case "outage":
            case "offline":
            case "full_down":
            case "internet_down":
                return negative

            case "info":
            case "maintenance":
            case "under_maintenance":
                return info

            default:
                return disabled
        }
    }
}
