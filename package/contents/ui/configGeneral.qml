import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: configRoot

    property alias cfg_refreshInterval: refreshSpin.value
    property alias cfg_backendPort: portSpin.value
    property alias cfg_notificationsEnabled: notifCheck.checked
    property alias cfg_warningThreshold: warnSpin.value
    property alias cfg_criticalThreshold: critSpin.value

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        // --- Refresh ---
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Refresh")
        }

        QQC2.SpinBox {
            id: refreshSpin
            Kirigami.FormData.label: i18n("Refresh interval (minutes):")
            from: 1; to: 60
        }

        // --- Notifications ---
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Notifications")
        }

        QQC2.CheckBox {
            id: notifCheck
            Kirigami.FormData.label: i18n("Enable notifications:")
        }

        QQC2.SpinBox {
            id: warnSpin
            Kirigami.FormData.label: i18n("Warning threshold (%):")
            from: 50; to: 95
            enabled: notifCheck.checked
        }

        QQC2.SpinBox {
            id: critSpin
            Kirigami.FormData.label: i18n("Critical threshold (%):")
            from: 60; to: 100
            enabled: notifCheck.checked
        }

        // --- Backend ---
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Backend")
        }

        QQC2.SpinBox {
            id: portSpin
            Kirigami.FormData.label: i18n("Backend port:")
            from: 1024; to: 65535
        }

        QQC2.Label {
            text: i18n("Manage the backend service:")
            opacity: 0.7
        }

        QQC2.Label {
            text: "systemctl --user status api-dashboard"
            font.family: "monospace"
            opacity: 0.5
        }
    }
}
