import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

Item {
    id: fullRep

    Accessible.name: i18n("ApiSmith usage dashboard")
    Accessible.role: Accessible.Pane

    Layout.preferredWidth: Kirigami.Units.gridUnit * 24
    Layout.preferredHeight: Kirigami.Units.gridUnit * 28
    Layout.minimumWidth: Kirigami.Units.gridUnit * 20
    Layout.minimumHeight: Kirigami.Units.gridUnit * 18

    // Filter helpers
    function claudeServices() {
        var result = []
        for (var i = 0; i < root.services.length; i++) {
            if (root.isClaudeService(root.services[i]))
                result.push(root.services[i])
        }
        return result
    }

    function apiKeyServices() {
        var result = []
        for (var i = 0; i < root.services.length; i++) {
            if (!root.isClaudeService(root.services[i]))
                result.push(root.services[i])
        }
        return result
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        // --- Header ---
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Heading {
                text: i18n("ApiSmith")
                level: 4
                Layout.fillWidth: true
            }

            PlasmaComponents.ToolButton {
                icon.name: "view-refresh"
                onClicked: root.forceRefresh()
                PlasmaComponents.ToolTip { text: i18n("Refresh") }
                Accessible.name: i18n("Refresh usage data")
            }

            PlasmaComponents.ToolButton {
                icon.name: "configure"
                onClicked: Plasmoid.internalAction("configure").trigger()
                PlasmaComponents.ToolTip { text: i18n("Configure") }
                Accessible.name: i18n("Open settings")
            }
        }

        // --- Tab bar ---
        QQC2.TabBar {
            id: tabBar
            Layout.fillWidth: true

            QQC2.TabButton { text: i18n("Claude") }
            QQC2.TabButton { text: i18n("API Keys") }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // --- Tab content ---
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex

            // Tab 0: Claude accounts only
            Flickable {
                contentHeight: claudeColumn.implicitHeight
                clip: true

                ColumnLayout {
                    id: claudeColumn
                    width: parent.width
                    spacing: Kirigami.Units.smallSpacing

                    // Loading state
                    PlasmaComponents.BusyIndicator {
                        visible: root.loading && root.services.length === 0
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 2
                    }

                    // Error state
                    PlasmaComponents.Label {
                        visible: !!root.lastError && root.services.length === 0
                        text: root.lastError
                        color: Kirigami.Theme.negativeTextColor
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    PlasmaComponents.Label {
                        visible: !!root.lastError && root.services.length === 0
                        text: i18n("Is the backend service running?")
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Repeater {
                        model: fullRep.claudeServices()

                        ServiceCard {
                            Layout.fillWidth: true
                            service: modelData
                            isClaude: true
                            serviceId: modelData.id
                        }
                    }

                    // Empty state for Claude tab
                    PlasmaComponents.Label {
                        visible: !root.loading && fullRep.claudeServices().length === 0 && !root.lastError
                        text: i18n("No Claude accounts configured")
                        opacity: 0.7
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            // Tab 1: Firecrawl / SerpAPI only
            Flickable {
                contentHeight: apiColumn.implicitHeight
                clip: true

                ColumnLayout {
                    id: apiColumn
                    width: parent.width
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.BusyIndicator {
                        visible: root.loading && root.services.length === 0
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 2
                    }

                    Repeater {
                        model: fullRep.apiKeyServices()

                        ServiceCard {
                            Layout.fillWidth: true
                            service: modelData
                            isClaude: false
                            serviceId: modelData.id || ""
                        }
                    }

                    PlasmaComponents.Label {
                        visible: !root.loading && fullRep.apiKeyServices().length === 0 && !root.lastError
                        text: i18n("No API services configured")
                        opacity: 0.7
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }

        // --- Footer ---
        PlasmaComponents.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: i18n("Updated %1", Qt.formatTime(root.lastUpdated, "HH:mm:ss"))
            font: Kirigami.Theme.smallFont
            opacity: 0.5
        }
    }
}
