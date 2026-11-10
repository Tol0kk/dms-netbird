import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "netbird-control"

    // ── Settings from pluginData ──
    property int refreshInterval: pluginData.refreshInterval !== undefined ? pluginData.refreshInterval : 30000
    property bool showIpAddress: pluginData.showIpAddress !== undefined ? pluginData.showIpAddress : true
    property bool hideDisconnected: pluginData.hideDisconnected !== undefined ? pluginData.hideDisconnected : false
    property bool showPing: pluginData.showPing !== undefined ? pluginData.showPing : false
    property int pingCount: pluginData.pingCount !== undefined ? pluginData.pingCount : 5
    property string customTerminal: pluginData.terminalCommand || ""
    property bool colorizeIcon: pluginData.colorizeIcon !== undefined ? pluginData.colorizeIcon : true
    property string adminConsoleUrl: pluginData.adminConsoleUrl || "https://app.netbird.io/"
    property string clientNamesSetting: (pluginData.clientNames || "").trim()

    function normalizePeerAction(value) {
        if (value === "Copy IP")
            return "copy-ip";
        if (value === "SSH to host")
            return "ssh";
        if (value === "Ping host")
            return "ping";
        return value || "copy-ip";
    }

    property string defaultPeerAction: normalizePeerAction(pluginData.defaultPeerAction)

    // ── Clients (one per `netbird` / `netbird-<name>` binary) ──
    property var clientBins: []
    property var clientItems: []
    property int runningCount: 0
    property var runningIps: []
    property bool anyRefreshing: false
    property bool allChecking: true
    property var _cache: null

    function _validBin(name) {
        return /^netbird(-[A-Za-z0-9_-]+)?$/.test(name) && name.indexOf("netbird-ui") !== 0;
    }

    function _setBins(bins) {
        if (bins.join(",") !== clientBins.join(","))
            clientBins = bins;
    }

    // Manual list from settings ("default, pro" or "netbird-default"), else the auto-detected list
    function applyDetected(detected) {
        if (clientNamesSetting === "") {
            _setBins(detected);
            return;
        }
        var bins = [];
        var parts = clientNamesSetting.split(/[\s,]+/);
        for (var i = 0; i < parts.length; i++) {
            var n = parts[i];
            if (n === "")
                continue;
            if (n !== "netbird" && n.indexOf("netbird-") !== 0)
                n = "netbird-" + n;
            if (_validBin(n) && bins.indexOf(n) < 0)
                bins.push(n);
        }
        _setBins(bins);
    }

    onClientNamesSettingChanged: detectClients()

    function rebuildClientItems() {
        var arr = [];
        for (var i = 0; i < clientRepeater.count; i++) {
            var it = clientRepeater.itemAt(i);
            if (it)
                arr.push(it);
        }
        clientItems = arr;
        recount();
    }

    function recount() {
        var n = 0, ips = [], refreshing = false, checking = true;
        for (var i = 0; i < clientRepeater.count; i++) {
            var c = clientRepeater.itemAt(i);
            if (!c)
                continue;
            if (c.netbirdRunning) {
                n++;
                if (c.netbirdIp)
                    ips.push(c.netbirdIp);
            }
            if (c.isRefreshing)
                refreshing = true;
            if (c.netbirdStatus !== "Checking...")
                checking = false;
        }
        runningCount = n;
        runningIps = ips;
        anyRefreshing = refreshing;
        allChecking = checking;
    }

    function refreshAll() {
        for (var i = 0; i < clientRepeater.count; i++) {
            var c = clientRepeater.itemAt(i);
            if (c)
                c.refresh();
        }
    }

    // Disconnect every connected client; if none is connected, connect all
    function toggleAll() {
        var disconnecting = runningCount > 0;
        for (var i = 0; i < clientRepeater.count; i++) {
            var c = clientRepeater.itemAt(i);
            if (c && c.netbirdRunning === disconnecting)
                c.toggle();
        }
    }

    function saveClientState(bin, entry) {
        if (!pluginService)
            return;
        if (_cache === null) {
            try {
                _cache = JSON.parse(pluginData.clientCache || "{}");
            } catch (e) {
                _cache = {};
            }
        }
        _cache[bin] = entry;
        pluginService.savePluginData("netbirdStatus", "clientCache", JSON.stringify(_cache));
    }

    function notify(title, message) {
        ToastService.showInfo(title, message);
    }

    Repeater {
        id: clientRepeater
        model: root.clientBins
        delegate: NetbirdClient {
            host: root
            bin: modelData
            onNetbirdRunningChanged: root.recount()
            onNetbirdIpChanged: root.recount()
            onIsRefreshingChanged: root.recount()
            onNetbirdStatusChanged: root.recount()
        }
        onItemAdded: root.rebuildClientItems()
        onItemRemoved: root.rebuildClientItems()
    }

    Process {
        id: detectProcess
        stdout: StdioCollector {}
        command: ["sh", "-c", "IFS=:; for d in $PATH; do [ -x \"$d/netbird\" ] && echo netbird; for f in \"$d\"/netbird-*; do [ -x \"$f\" ] && basename \"$f\"; done; done 2>/dev/null | sort -u"]

        onExited: function (exitCode, exitStatus) {
            var lines = String(detectProcess.stdout.text || "").split("\n");
            var bins = [];
            for (var i = 0; i < lines.length; i++) {
                var n = lines[i].trim();
                if (root._validBin(n) && bins.indexOf(n) < 0)
                    bins.push(n);
            }
            root.applyDetected(bins);
        }
    }

    function detectClients() {
        if (!detectProcess.running)
            detectProcess.running = true;
    }

    // ── Terminal / peer actions ──
    property string detectedTerminal: ""
    property string activeTerminal: customTerminal !== "" ? customTerminal : detectedTerminal
    property bool terminalDetected: activeTerminal !== ""
    property var terminalCandidates: ["ghostty", "alacritty", "kitty", "foot", "wezterm", "konsole", "gnome-terminal", "xfce4-terminal", "xterm"]
    property int terminalCheckIndex: 0

    function parseIp(ip) {
        if (!ip)
            return "";
        var idx = ip.indexOf("/");
        if (idx > 0)
            return ip.substring(0, idx);
        return ip;
    }

    function getHostname(peer) {
        if (!peer)
            return "Unknown";
        if (peer.fqdn) {
            var parts = peer.fqdn.split(".");
            if (parts.length > 0)
                return parts[0];
        }
        return peer.netbirdIp || "Unknown";
    }

    function getConnectionIcon(connType) {
        if (!connType)
            return "signal_disconnected";
        switch (connType.toLowerCase()) {
        case "p2p":
            return "compare_arrows";
        case "relayed":
            return "cloud";
        default:
            return "signal_disconnected";
        }
    }

    function requireTerminal() {
        if (!terminalDetected) {
            ToastService.showError("NetBird Terminal Not Configured", "Please install a supported terminal emulator to use SSH and Ping features");
            return false;
        }
        return true;
    }

    function copyToClipboard(text) {
        var escaped = text.replace(/'/g, "'\\''");
        Quickshell.execDetached(["sh", "-c", "printf '%s' '" + escaped + "' | wl-copy"]);
    }

    function executePeerAction(action, peer) {
        if (action === "copy-ip") {
            if (peer && peer.netbirdIp) {
                copyToClipboard(peer.netbirdIp);
                ToastService.showInfo("IP Copied", "IP of " + getHostname(peer) + " copied to clipboard");
            }
        } else if (action === "ssh") {
            if (!requireTerminal())
                return;
            if (peer && peer.netbirdIp)
                Quickshell.execDetached([root.activeTerminal, "-e", "ssh", peer.netbirdIp]);
        } else if (action === "ping") {
            if (!requireTerminal())
                return;
            if (peer && peer.netbirdIp)
                Quickshell.execDetached([root.activeTerminal, "-e", "ping", "-c", root.pingCount.toString(), peer.netbirdIp]);
        }
    }

    Process {
        id: terminalDetectProcess
        stdout: StdioCollector {}

        onExited: function (exitCode, exitStatus) {
            if (exitCode === 0) {
                root.detectedTerminal = root.terminalCandidates[root.terminalCheckIndex];
            } else {
                root.terminalCheckIndex++;
                if (root.terminalCheckIndex < root.terminalCandidates.length) {
                    terminalDetectProcess.command = ["which", root.terminalCandidates[root.terminalCheckIndex]];
                    terminalDetectProcess.running = true;
                }
            }
        }
    }

    function detectTerminal() {
        root.terminalCheckIndex = 0;
        root.detectedTerminal = "";
        if (root.terminalCandidates.length > 0) {
            terminalDetectProcess.command = ["which", root.terminalCandidates[0]];
            terminalDetectProcess.running = true;
        }
    }

    // ── Refresh loop ──
    Timer {
        id: updateTimer
        interval: refreshInterval
        repeat: true
        running: true
        triggeredOnStart: true

        onTriggered: {
            root.detectClients();
            root.refreshAll();
        }
    }

    Component.onCompleted: detectTerminal()

    // ── Bar Widget (Pill) ──
    horizontalBarPill: Component {
        Item {
            implicitWidth: hBarRow.implicitWidth
            implicitHeight: hBarRow.implicitHeight

            Row {
                id: hBarRow
                spacing: Theme.spacingXS

                NetBirdIcon {
                    size: root.iconSize
                    color: root.runningCount > 0 ? Theme.primary : Theme.surfaceVariantText
                    opacity: root.anyRefreshing ? 0.5 : 1.0
                    anchors.verticalCenter: parent.verticalCenter
                    crossed: root.runningCount === 0
                    colorize: root.colorizeIcon
                }

                StyledText {
                    text: root.runningIps.join(" · ")
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.showIpAddress && root.runningIps.length > 0
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (typeof root.triggerPopout === "function")
                        root.triggerPopout();
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: vBarCol.implicitWidth
            implicitHeight: vBarCol.implicitHeight

            Column {
                id: vBarCol
                spacing: Theme.spacingXS

                NetBirdIcon {
                    size: root.iconSize
                    color: root.runningCount > 0 ? Theme.primary : Theme.surfaceVariantText
                    opacity: root.anyRefreshing ? 0.5 : 1.0
                    anchors.horizontalCenter: parent.horizontalCenter
                    crossed: root.runningCount === 0
                    colorize: root.colorizeIcon
                }

                Repeater {
                    model: root.showIpAddress ? root.runningIps : []
                    delegate: StyledText {
                        text: modelData
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (typeof root.triggerPopout === "function")
                        root.triggerPopout();
                }
            }
        }
    }

    // ── Control Center Tile ──
    ccWidgetIcon: root.allChecking && root.clientBins.length > 0 ? "sync" : (root.runningCount > 0 ? "vpn_lock" : "vpn_key_off")
    ccWidgetPrimaryText: "NetBird"
    ccWidgetSecondaryText: {
        if (root.clientBins.length === 0)
            return "Not installed";
        if (root.allChecking)
            return "Checking...";
        if (root.runningCount === 0)
            return "Disconnected";
        if (root.clientBins.length > 1)
            return root.runningCount + "/" + root.clientBins.length + " connected";
        return root.runningIps.length > 0 ? root.runningIps[0] : "Connected";
    }
    ccWidgetIsActive: !root.allChecking && root.runningCount > 0
    ccWidgetIsToggle: true

    property real _ccContentHeight: 250
    ccDetailHeight: _ccContentHeight

    onCcWidgetToggled: root.toggleAll()

    ccDetailContent: Component {
        Rectangle {
            id: ccDetailRoot
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)

            Column {
                id: ccDetailCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                StyledText {
                    width: parent.width
                    visible: root.clientItems.length === 0
                    text: "No NetBird client found in PATH"
                    color: Theme.surfaceVariantText
                    horizontalAlignment: Text.AlignHCenter
                }

                Repeater {
                    model: root.clientItems
                    delegate: NetbirdContent {
                        width: ccDetailCol.width
                        widget: modelData
                        compactHeader: true
                        peersListMaxHeight: root.clientItems.length > 1 ? 90 : 130
                    }
                }
            }

            Component.onCompleted: {
                root._ccContentHeight = Qt.binding(() => ccDetailCol.implicitHeight + Theme.spacingM * 2);
                if (!root.pluginService) {
                    root.pluginService = PluginService;
                }
                if (!root.pluginId) {
                    root.pluginId = "netbirdStatus";
                }
            }
        }
    }

    // ── Popout Content ──
    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "NetBird"
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingL

                StyledText {
                    width: parent.width
                    visible: root.clientItems.length === 0
                    text: "No NetBird client found in PATH (looked for netbird and netbird-<name>)"
                    wrapMode: Text.WordWrap
                    color: Theme.surfaceVariantText
                    horizontalAlignment: Text.AlignHCenter
                }

                Repeater {
                    model: root.clientItems
                    delegate: NetbirdContent {
                        width: parent.width
                        widget: modelData
                    }
                }
            }
        }
    }
}
