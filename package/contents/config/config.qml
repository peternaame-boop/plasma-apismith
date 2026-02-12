import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "preferences-system"
        source: "configGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Services")
        icon: "network-server"
        source: "configServices.qml"
    }
}
