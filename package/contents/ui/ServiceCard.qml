import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

ColumnLayout {
    id: card

    property var service: ({})
    property bool isClaude: false
    property string serviceId: ""

    Accessible.name: i18n("%1: %2%", service.name || "", Math.round(Math.min(service.percentage || 0, 100)))
    Accessible.role: Accessible.ListItem

    spacing: Kirigami.Units.smallSpacing

    function estimateExhaustion(usagePct, resetMins, windowMins) {
        if (usagePct <= 0 || usagePct >= 100) return ""
        var elapsed = windowMins - resetMins
        if (elapsed <= 0) return ""
        var rate = usagePct / elapsed
        var remaining = (100 - usagePct) / rate
        if (remaining < 1) return i18n("Used up soon")
        if (remaining < 60) return i18n("Used up in %1m", Math.round(remaining))
        if (remaining < 1440) return i18n("Used up in %1h %2m", Math.floor(remaining / 60), Math.round(remaining % 60))
        return i18n("Used up in %1d %2h", Math.floor(remaining / 1440), Math.floor((remaining % 1440) / 60))
    }

    // --- Header row ---
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            source: service.icon || "network-server"
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }

        PlasmaComponents.Label {
            text: service.name || ""
            font.bold: true
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        PlasmaComponents.Label {
            text: service.plan_name || ""
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        PlasmaComponents.Label {
            visible: !card.isClaude
            text: Math.round(Math.min(service.percentage || 0, 100)) + "%"
            font.bold: true
            color: statusColors.forLevel(root.usageStatus(Math.min(service.percentage || 0, 100)))
        }
    }

    // --- Error ---
    PlasmaComponents.Label {
        visible: !!service.error
        text: service.error || ""
        color: Kirigami.Theme.negativeTextColor
        font: Kirigami.Theme.smallFont
        Layout.fillWidth: true
        wrapMode: Text.Wrap
    }

    // --- Progress bar (non-Claude only) ---
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 6
        visible: !service.error && !card.isClaude

        Rectangle {
            anchors.fill: parent
            radius: 3
            color: Kirigami.Theme.separatorColor
            opacity: 0.3
        }

        Rectangle {
            width: parent.width * Math.min((service.percentage || 0) / 100, 1)
            height: parent.height
            radius: 3
            color: statusColors.forLevel(root.usageStatus(Math.min(service.percentage || 0, 100)))

            Behavior on width {
                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
            }
        }
    }

    // --- Usage detail row (non-Claude only) ---
    RowLayout {
        Layout.fillWidth: true
        visible: !service.error && !card.isClaude
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            text: {
                var used = service.used || 0
                var total = service.total || 0
                var unit = service.unit || ""
                if (unit === "%") return ""
                return i18n("%1 / %2 %3", used.toLocaleString(), total.toLocaleString(), unit)
            }
            visible: text !== ""
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }

        Item { Layout.fillWidth: true }

        PlasmaComponents.Label {
            visible: !!(service.reset_info)
            text: service.reset_info ? i18n("Resets in %1", service.reset_info) : ""
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }
    }

    // --- Claude-specific: 5-hour and 7-day breakout ---
    ColumnLayout {
        Layout.fillWidth: true
        visible: !!(service.details && service.details.five_hour_usage !== undefined)
        spacing: Kirigami.Units.smallSpacing

        // 5-hour section
        RowLayout {
            Layout.fillWidth: true
            Kirigami.Icon {
                source: "speedometer"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
            PlasmaComponents.Label {
                text: i18n("5-Hour Session")
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            PlasmaComponents.Label {
                text: Math.round(service.details ? service.details.five_hour_usage || 0 : 0) + "%"
                font.bold: true
                color: statusColors.forLevel(root.usageStatus(
                    service.details ? service.details.five_hour_usage || 0 : 0))
            }
        }

        // 5-hour bar
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 6
            Rectangle {
                anchors.fill: parent; radius: 3
                color: Kirigami.Theme.separatorColor; opacity: 0.3
            }
            Rectangle {
                width: parent.width * Math.min((service.details ? service.details.five_hour_usage || 0 : 0) / 100, 1)
                height: parent.height; radius: 3
                color: statusColors.forLevel(root.usageStatus(
                    service.details ? service.details.five_hour_usage || 0 : 0))
                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            }
        }

        // 5-hour reset + exhaustion estimate
        RowLayout {
            Layout.fillWidth: true
            visible: !!(service.details && service.details.five_hour_reset_minutes > 0)

            PlasmaComponents.Label {
                text: {
                    var mins = service.details ? service.details.five_hour_reset_minutes || 0 : 0
                    if (mins <= 0) return ""
                    if (mins >= 60) return i18n("Resets in %1h %2m", Math.floor(mins / 60), mins % 60)
                    return i18n("Resets in %1m", mins)
                }
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }

            Item { Layout.fillWidth: true }

            PlasmaComponents.Label {
                text: card.estimateExhaustion(
                    service.details ? service.details.five_hour_usage || 0 : 0,
                    service.details ? service.details.five_hour_reset_minutes || 0 : 0,
                    300)
                visible: text !== ""
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.neutralTextColor
            }
        }

        // Spacer between sections
        Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

        // 7-day section
        RowLayout {
            Layout.fillWidth: true
            Kirigami.Icon {
                source: "view-calendar-week"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
            PlasmaComponents.Label {
                text: i18n("7-Day Weekly")
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            PlasmaComponents.Label {
                text: Math.round(service.details ? service.details.seven_day_usage || 0 : 0) + "%"
                font.bold: true
                color: statusColors.forLevel(root.usageStatus(
                    service.details ? service.details.seven_day_usage || 0 : 0))
            }
        }

        // 7-day bar
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 6
            Rectangle {
                anchors.fill: parent; radius: 3
                color: Kirigami.Theme.separatorColor; opacity: 0.3
            }
            Rectangle {
                width: parent.width * Math.min((service.details ? service.details.seven_day_usage || 0 : 0) / 100, 1)
                height: parent.height; radius: 3
                color: statusColors.forLevel(root.usageStatus(
                    service.details ? service.details.seven_day_usage || 0 : 0))
                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            }
        }

        // 7-day reset + exhaustion estimate
        RowLayout {
            Layout.fillWidth: true
            visible: !!(service.details && service.details.seven_day_reset_minutes > 0)

            PlasmaComponents.Label {
                text: {
                    var mins = service.details ? service.details.seven_day_reset_minutes || 0 : 0
                    if (mins <= 0) return ""
                    if (mins >= 1440) return i18n("Resets in %1d %2h", Math.floor(mins / 1440), Math.floor((mins % 1440) / 60))
                    if (mins >= 60) return i18n("Resets in %1h %2m", Math.floor(mins / 60), mins % 60)
                    return i18n("Resets in %1m", mins)
                }
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }

            Item { Layout.fillWidth: true }

            PlasmaComponents.Label {
                text: card.estimateExhaustion(
                    service.details ? service.details.seven_day_usage || 0 : 0,
                    service.details ? service.details.seven_day_reset_minutes || 0 : 0,
                    10080)
                visible: text !== ""
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.neutralTextColor
            }
        }
    }

    // --- Launch buttons (Claude only) ---
    RowLayout {
        Layout.fillWidth: true
        visible: card.isClaude && !service.error
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Button {
            Layout.fillWidth: true
            icon.name: card.serviceId === "claude_work" ? "utilities-terminal" : "application-x-executable"
            text: card.serviceId === "claude_work" ? i18n("Open Claude Code") : i18n("Open Claude Desktop")
            onClicked: {
                if (card.serviceId === "claude_work")
                    root.launchWorkClaude(false)
                else
                    root.launchPrivateClaude()
            }
        }

        PlasmaComponents.Button {
            visible: card.serviceId === "claude_work"
            icon.name: "edit-undo"
            text: i18n("Resume")
            PlasmaComponents.ToolTip { text: i18n("Resume last Claude Code session") }
            onClicked: root.launchWorkClaude(true)
        }
    }

    // --- Bottom separator ---
    Kirigami.Separator {
        Layout.fillWidth: true
    }
}
