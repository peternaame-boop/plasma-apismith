import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.notification

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation

    toolTipMainText: i18n("ApiSmith")
    toolTipSubText: {
        if (services.length === 0) return i18n("Loading...")
        var lines = []
        for (var i = 0; i < services.length; i++) {
            var s = services[i]
            if (isClaudeService(s) && s.details && s.details.five_hour_usage !== undefined) {
                lines.push(i18n("%1: 5h %2% · 7d %3%", s.name,
                    Math.round(s.details.five_hour_usage),
                    Math.round(s.details.seven_day_usage || 0)))
            } else {
                var pct = Math.round(Math.min(s.percentage || 0, 100))
                lines.push(i18n("%1: %2%", s.name, pct))
            }
        }
        return lines.join("\n")
    }

    compactRepresentation: CompactRepresentation {}
    fullRepresentation: FullRepresentation {}

    // --- Data model: list of service results from backend ---
    property var services: []
    property bool loading: true
    property string lastError: ""
    property date lastUpdated: new Date()

    readonly property int backendPort: Plasmoid.configuration.backendPort
    readonly property string backendUrl: "http://127.0.0.1:" + backendPort

    StatusColors { id: statusColors }

    // --- Notification ---
    Notification {
        id: notification
        componentName: "plasma_workspace"
        eventId: "notification"
        iconName: "dialog-warning"
    }

    // --- Backend communication ---
    function fetchUsage() {
        loading = true
        var xhr = new XMLHttpRequest()
        xhr.open("GET", backendUrl + "/usage")
        xhr.timeout = 10000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            loading = false
            if (xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText)
                    var arr = data.services || []
                    arr.sort(function(a, b) {
                        return serviceOrderIndex(a.id) - serviceOrderIndex(b.id)
                    })
                    services = arr
                    lastError = ""
                    lastUpdated = new Date()
                    checkThresholds()
                } catch (e) {
                    lastError = i18n("Parse error: %1", e)
                }
            } else {
                lastError = xhr.status === 0 ? i18n("Backend unreachable") : i18n("HTTP %1", xhr.status)
            }
        }
        xhr.send()
    }

    function pushConfig() {
        var cfg = {
            refresh_interval: Plasmoid.configuration.refreshInterval * 60,
            services: {}
        }
        if (Plasmoid.configuration.firecrawlEnabled) {
            cfg.services.firecrawl = {
                enabled: true,
                api_key: Plasmoid.configuration.firecrawlApiKey,
                reset_day: Plasmoid.configuration.firecrawlResetDay
            }
        }
        if (Plasmoid.configuration.serpApiEnabled) {
            cfg.services.serpapi = {
                enabled: true,
                api_key: Plasmoid.configuration.serpApiKey,
                reset_day: Plasmoid.configuration.serpApiResetDay
            }
        }
        if (Plasmoid.configuration.claudeWorkEnabled) {
            cfg.services.claude_work = {
                enabled: true,
                browser: Plasmoid.configuration.claudeWorkBrowser,
                label: Plasmoid.configuration.claudeWorkLabel
            }
        }
        if (Plasmoid.configuration.claudePrivateEnabled) {
            cfg.services.claude_private = {
                enabled: true,
                browser: Plasmoid.configuration.claudePrivateBrowser,
                label: Plasmoid.configuration.claudePrivateLabel
            }
        }

        var xhr = new XMLHttpRequest()
        xhr.open("POST", backendUrl + "/config")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.send(JSON.stringify(cfg))
    }

    function forceRefresh() {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", backendUrl + "/refresh")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                Qt.callLater(fetchUsage)
            }
        }
        xhr.send()
    }

    // --- Threshold notifications ---
    function checkThresholds() {
        if (!Plasmoid.configuration.notificationsEnabled) return
        for (var i = 0; i < services.length; i++) {
            var svc = services[i]
            if (svc.error) continue
            var pct = svc.percentage
            if (pct >= Plasmoid.configuration.criticalThreshold) {
                notification.title = i18n("%1 Critical", svc.name)
                notification.text = i18n("Usage at %1% - approaching limit!", Math.round(pct))
                notification.sendEvent()
            } else if (pct >= Plasmoid.configuration.warningThreshold) {
                notification.title = i18n("%1 Warning", svc.name)
                notification.text = i18n("Usage at %1%", Math.round(pct))
                notification.sendEvent()
            }
        }
    }

    // --- Command runner ---
    Plasma5Support.DataSource {
        id: commandRunner
        engine: "executable"
        onNewData: function(source, data) { disconnectSource(source) }
    }

    function runCommand(cmd) {
        commandRunner.connectSource(cmd)
    }

    function shellEscape(s) {
        return "'" + s.replace(/'/g, "'\\''") + "'"
    }

    function launchWorkClaude(resume) {
        var shellCmd = "cd " + shellEscape(Qt.resolvedUrl("").toString().replace("file://", "").replace(/\/package\/.*/, "") || "~/AI/LLM") + " && claude"
        // Use the home directory directly
        shellCmd = "cd ~/AI/LLM && claude"
        if (resume) shellCmd += " --resume"
        var fullCmd = "setsid kitty -e bash -c " + shellEscape(shellCmd) + " & #" + Date.now()
        runCommand(fullCmd)
    }

    function launchPrivateClaude() {
        runCommand("claude-desktop-native & #" + Date.now())
    }

    function isClaudeService(svc) {
        return svc && svc.id && svc.id.indexOf("claude") === 0
    }

    // --- Service display helpers ---
    function serviceLabel(svc) {
        if (!svc || !svc.id) return "?"
        switch (svc.id) {
            case "claude_work":    return "CWo"
            case "claude_private": return "CPr"
            case "firecrawl":      return "Fc"
            case "serpapi":        return "SA"
            default:               return svc.id.substring(0, 2).toUpperCase()
        }
    }

    function serviceOrderIndex(id) {
        switch (id) {
            case "claude_work":    return 0
            case "claude_private": return 1
            case "firecrawl":      return 2
            case "serpapi":        return 3
            default:               return 99
        }
    }

    // --- Helpers ---
    function usageStatus(pct) {
        if (pct >= Plasmoid.configuration.criticalThreshold) return "error"
        if (pct >= Plasmoid.configuration.warningThreshold) return "warn"
        return "ok"
    }

    // --- Lifecycle ---
    Timer {
        id: refreshTimer
        interval: Plasmoid.configuration.refreshInterval * 60 * 1000
        running: true
        repeat: true
        onTriggered: {
            pushConfig()
            fetchUsage()
        }
    }

    // Debounce config pushes — any config change triggers a push after 1s
    Timer {
        id: configPushTimer
        interval: 1000
        onTriggered: {
            pushConfig()
            fetchUsage()
        }
    }

    Component.onCompleted: {
        pushConfig()
        Qt.callLater(fetchUsage)
    }

    // Watch all service-related config properties for changes
    Connections {
        target: Plasmoid.configuration
        function onFirecrawlEnabledChanged() { configPushTimer.restart() }
        function onFirecrawlApiKeyChanged() { configPushTimer.restart() }
        function onSerpApiEnabledChanged() { configPushTimer.restart() }
        function onSerpApiKeyChanged() { configPushTimer.restart() }
        function onClaudeWorkEnabledChanged() { configPushTimer.restart() }
        function onClaudePrivateEnabledChanged() { configPushTimer.restart() }
        function onRefreshIntervalChanged() { configPushTimer.restart() }
    }
}
