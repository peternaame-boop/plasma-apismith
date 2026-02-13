import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: compact

    Layout.fillHeight: true
    Layout.preferredWidth: pillRow.width + Kirigami.Units.smallSpacing * 2

    Accessible.name: {
        if (root.services.length === 0) return i18n("ApiSmith: loading")
        var parts = []
        for (var i = 0; i < root.services.length; i++) {
            var s = root.services[i]
            if (root.isClaudeService(s) && s.details && s.details.five_hour_usage !== undefined) {
                parts.push(i18n("%1: 5-hour %2%, 7-day %3%", s.name,
                    Math.round(s.details.five_hour_usage),
                    Math.round(s.details.seven_day_usage || 0)))
            } else {
                parts.push(i18n("%1 %2%", s.name, Math.round(s.percentage)))
            }
        }
        return parts.join(", ")
    }
    Accessible.role: Accessible.Indicator

    Row {
        id: pillRow
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing

        Repeater {
            model: root.services

            Item {
                id: pill

                readonly property bool isClaude: root.isClaudeService(modelData)
                readonly property real fiveH: (isClaude && modelData.details)
                    ? (modelData.details.five_hour_usage || 0) : 0
                readonly property real sevenD: (isClaude && modelData.details)
                    ? (modelData.details.seven_day_usage || 0) : 0
                readonly property real worstPct: isClaude
                    ? Math.max(fiveH, sevenD) : (modelData.percentage || 0)
                readonly property string label: root.serviceLabel(modelData)

                width: pillShape.width
                height: pillShape.height

                // Outer clipping shape
                Rectangle {
                    id: pillShape
                    width: labelZone.width + valueZone.width
                    height: Math.min(compact.height - Kirigami.Units.smallSpacing * 2,
                                     Kirigami.Units.gridUnit * 1.3)
                    radius: Kirigami.Units.smallSpacing
                    clip: true
                    color: "transparent"

                    // Label zone (left segment)
                    Rectangle {
                        id: labelZone
                        width: labelText.implicitWidth + Kirigami.Units.smallSpacing * 2.5
                        height: parent.height
                        color: Qt.rgba(
                            Kirigami.Theme.textColor.r,
                            Kirigami.Theme.textColor.g,
                            Kirigami.Theme.textColor.b,
                            0.12)

                        Text {
                            id: labelText
                            anchors.centerIn: parent
                            text: pill.label
                            color: Kirigami.Theme.textColor
                            opacity: 0.85
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            font.weight: Font.Medium
                            font.letterSpacing: 0.3
                        }
                    }

                    // Value zone (right segment)
                    Rectangle {
                        id: valueZone
                        x: labelZone.width
                        width: valueText.implicitWidth + Kirigami.Units.smallSpacing * 3
                        height: parent.height
                        color: {
                            var level = root.usageStatus(pill.worstPct)
                            if (level === "ok" || level === "good" || level === "green")
                                return "#123F1C"
                            if (level === "warn" || level === "warning" || level === "orange")
                                return "#2A1A0D"
                            if (level === "error" || level === "critical" || level === "red")
                                return "#2A0D0D"
                            return "#1A1A1A"
                        }

                        Text {
                            id: valueText
                            anchors.centerIn: parent
                            text: pill.isClaude
                                ? Math.round(Math.min(pill.fiveH, 100))
                                  + "/" + Math.round(Math.min(pill.sevenD, 100)) + "%"
                                : Math.round(Math.min(modelData.percentage, 100)) + "%"
                            color: Kirigami.Theme.highlightedTextColor
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            font.bold: true
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onClicked: root.expanded = !root.expanded
                }

                // Error indicator dot
                Rectangle {
                    visible: !!modelData.error
                    anchors.top: pillShape.top
                    anchors.right: pillShape.right
                    anchors.margins: -2
                    width: 8; height: 8; radius: 4
                    color: statusColors.forLevel("error")
                    border.color: Kirigami.Theme.backgroundColor
                    border.width: 1
                    z: 3
                }
            }
        }

        // Loading indicator when no services yet
        Kirigami.Icon {
            visible: root.services.length === 0
            source: "view-refresh"
            width: Kirigami.Units.iconSizes.small
            height: width

            RotationAnimation on rotation {
                running: root.loading
                from: 0; to: 360
                duration: 1000
                loops: Animation.Infinite
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        visible: root.services.length === 0
        onClicked: root.expanded = !root.expanded
    }
}
