import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: svcConfig

    property alias cfg_firecrawlEnabled: fcEnable.checked
    property alias cfg_firecrawlApiKey: fcKey.text
    property alias cfg_firecrawlResetDay: fcReset.value
    property alias cfg_serpApiEnabled: serpEnable.checked
    property alias cfg_serpApiKey: serpKey.text
    property alias cfg_serpApiResetDay: serpReset.value
    property alias cfg_claudeWorkEnabled: cwEnable.checked
    property string cfg_claudeWorkBrowser
    property alias cfg_claudeWorkLabel: cwLabel.text
    property alias cfg_claudePrivateEnabled: cpEnable.checked
    property string cfg_claudePrivateBrowser
    property alias cfg_claudePrivateLabel: cpLabel.text

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        // --- Firecrawl ---
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Firecrawl")
        }

        QQC2.CheckBox {
            id: fcEnable
            Kirigami.FormData.label: i18n("Enabled:")
        }

        QQC2.TextField {
            id: fcKey
            Kirigami.FormData.label: i18n("API Key:")
            echoMode: TextInput.Password
            placeholderText: i18n("(uses keyring if empty)")
            enabled: fcEnable.checked
        }

        QQC2.SpinBox {
            id: fcReset
            Kirigami.FormData.label: i18n("Billing reset day:")
            from: 1; to: 31
            enabled: fcEnable.checked
        }

        // --- SerpAPI ---
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("SerpAPI")
        }

        QQC2.CheckBox {
            id: serpEnable
            Kirigami.FormData.label: i18n("Enabled:")
        }

        QQC2.TextField {
            id: serpKey
            Kirigami.FormData.label: i18n("API Key:")
            echoMode: TextInput.Password
            placeholderText: i18n("(uses keyring if empty)")
            enabled: serpEnable.checked
        }

        QQC2.SpinBox {
            id: serpReset
            Kirigami.FormData.label: i18n("Billing reset day:")
            from: 1; to: 31
            enabled: serpEnable.checked
        }

        // --- Claude (Work) ---
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Claude (Work)")
        }

        QQC2.CheckBox {
            id: cwEnable
            Kirigami.FormData.label: i18n("Enabled:")
        }

        QQC2.TextField {
            id: cwLabel
            Kirigami.FormData.label: i18n("Label:")
            enabled: cwEnable.checked
        }

        QQC2.ComboBox {
            id: cwBrowser
            Kirigami.FormData.label: i18n("Browser:")
            model: ["chrome", "brave", "helium", "chromium", "firefox"]
            currentIndex: model.indexOf(cfg_claudeWorkBrowser)
            onActivated: cfg_claudeWorkBrowser = model[currentIndex]
            enabled: cwEnable.checked
        }

        // --- Claude (Private) ---
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Claude (Private)")
        }

        QQC2.CheckBox {
            id: cpEnable
            Kirigami.FormData.label: i18n("Enabled:")
        }

        QQC2.TextField {
            id: cpLabel
            Kirigami.FormData.label: i18n("Label:")
            enabled: cpEnable.checked
        }

        QQC2.ComboBox {
            id: cpBrowser
            Kirigami.FormData.label: i18n("Browser:")
            model: ["chrome", "brave", "helium", "chromium", "firefox"]
            currentIndex: model.indexOf(cfg_claudePrivateBrowser)
            onActivated: cfg_claudePrivateBrowser = model[currentIndex]
            enabled: cpEnable.checked
        }
    }
}
