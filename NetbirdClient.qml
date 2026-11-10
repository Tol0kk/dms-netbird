import QtQuick
import Quickshell.Io

// State and CLI handling for ONE NetBird client binary (e.g. "netbird-default").
// Exposes the same property/function names NetbirdContent expects from its `widget`.
Item {
    id: client

    property var host
    property string bin: "netbird"
    // Name shown in the UI: "default" for netbird-default, "" for plain netbird
    readonly property string clientLabel: bin.indexOf("netbird-") === 0 ? bin.substring(8) : ""
    readonly property string displayName: clientLabel !== "" ? clientLabel : bin

    visible: false
    width: 0
    height: 0

    // ── Forwarded settings / helpers ──
    readonly property bool showIpAddress: host ? host.showIpAddress : true
    readonly property bool colorizeIcon: host ? host.colorizeIcon : true
    readonly property bool showPing: host ? host.showPing : false
    readonly property bool hideDisconnected: host ? host.hideDisconnected : false
    readonly property string defaultPeerAction: host ? host.defaultPeerAction : "copy-ip"

    function copyToClipboard(text) {
        host.copyToClipboard(text);
    }
    function copyText(text, what) {
        if (!text)
            return;
        host.copyToClipboard(text);
        host.notify(what + " copied", text);
    }
    function executePeerAction(action, peer) {
        host.executePeerAction(action, peer);
    }
    function getHostname(peer) {
        return host.getHostname(peer);
    }
    function getConnectionIcon(t) {
        return host.getConnectionIcon(t);
    }

    // ── State ──
    property bool netbirdInstalled: true
    property bool netbirdRunning: false
    property string netbirdIp: ""
    property string netbirdFqdn: ""
    property string netbirdStatus: "Checking..."
    property int peerCount: 0
    property int peerConnected: 0
    property bool isRefreshing: false
    property string lastToggleAction: ""
    property var peerList: []
    property bool managementConnected: false
    property bool signalConnected: false
    property bool _restored: false

    // Management URL reported by the daemon (e.g. https://api.netbird.example.org:443)
    property string managementUrl: ""
    // Dashboard = management host without port/path; NetBird cloud's API lives on api.netbird.io, its dashboard on app.netbird.io
    readonly property string adminConsoleUrl: {
        var m = managementUrl.match(/^(https?:\/\/)?([^\/:?#]+)/);
        if (!m || !m[2])
            return "";
        if (m[2] === "api.netbird.io")
            return "https://app.netbird.io/";
        return (m[1] || "https://") + m[2];
    }

    // "checking" | "connected" | "disconnected" | "error"
    readonly property string statusKind: {
        if (netbirdStatus === "Checking...")
            return "checking";
        if (netbirdRunning)
            return "connected";
        if (netbirdStatus === "Disconnected")
            return "disconnected";
        return "error";
    }

    property var peerPings: ({})
    property var pingQueue: []
    property string currentPingIp: ""
    property var peerActionOpenMap: ({})

    // ── Cache (so the bar shows last known state right after a shell restart) ──
    function restoreCache() {
        if (_restored || !host || !host.pluginData || !host.pluginData.clientCache)
            return;
        var cache;
        try {
            cache = JSON.parse(host.pluginData.clientCache);
        } catch (e) {
            return;
        }
        var c = cache[bin];
        if (!c)
            return;
        netbirdRunning = c.running === true;
        netbirdIp = c.ip || "";
        netbirdFqdn = c.fqdn || "";
        peerCount = c.peerCount || 0;
        peerConnected = c.peerConnected || 0;
        managementUrl = c.managementUrl || "";
        netbirdStatus = netbirdRunning ? "Connected" : "Disconnected";
        _restored = true;
    }

    function _cacheEntry() {
        return {
            "running": netbirdRunning,
            "ip": netbirdIp,
            "fqdn": netbirdFqdn,
            "peerCount": peerCount,
            "peerConnected": peerConnected,
            "managementUrl": managementUrl
        };
    }

    Connections {
        target: client.host
        function onPluginDataChanged() {
            client.restoreCache();
        }
    }

    Component.onCompleted: {
        restoreCache();
        refresh();
    }

    // ── Peer open/close (per client) ──
    function getPeerKey(peer) {
        return peer ? (peer.netbirdIp || peer.fqdn || "") : "";
    }
    function isPeerOpen(peer) {
        var key = getPeerKey(peer);
        return key !== "" && peerActionOpenMap[key] === true;
    }
    function setPeerOpen(peer, open) {
        var key = getPeerKey(peer);
        if (!key)
            return;
        var updated = Object.assign({}, peerActionOpenMap);
        if (open)
            updated[key] = true;
        else
            delete updated[key];
        peerActionOpenMap = updated;
    }
    function prunePeerOpenMap() {
        var updated = {};
        var list = sortedPeerList || [];
        var open = peerActionOpenMap || {};
        for (var i = 0; i < list.length; i++) {
            var key = getPeerKey(list[i]);
            if (key && open[key])
                updated[key] = true;
        }
        peerActionOpenMap = updated;
    }

    property var sortedPeerList: {
        if (!peerList)
            return [];
        var peers = peerList.slice();
        if (hideDisconnected) {
            peers = peers.filter(function (p) {
                return p.status === "Connected";
            });
        }
        peers.sort(function (a, b) {
            var ac = a.status === "Connected";
            var bc = b.status === "Connected";
            if (ac && !bc)
                return -1;
            if (!ac && bc)
                return 1;
            return getHostname(a).toLowerCase().localeCompare(getHostname(b).toLowerCase());
        });
        return peers;
    }
    onPeerListChanged: prunePeerOpenMap()
    onHideDisconnectedChanged: prunePeerOpenMap()

    // ── Status ──
    function refresh() {
        if (statusProcess.running)
            return;
        isRefreshing = true;
        statusProcess.command = [bin, "status", "--json"];
        statusProcess.running = true;
    }

    function _setDisconnected(status) {
        netbirdRunning = false;
        netbirdStatus = status;
        netbirdIp = "";
        netbirdFqdn = "";
        peerCount = 0;
        peerConnected = 0;
        peerList = [];
    }

    Process {
        id: statusProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {}

        onExited: function (exitCode, exitStatus) {
            client.isRefreshing = false;
            var out = String(statusProcess.stdout.text || "").trim();

            if (exitCode === 0 && out.length > 0) {
                try {
                    var data = JSON.parse(out);
                    client.managementConnected = data.management?.connected ?? false;
                    client.signalConnected = data.signal?.connected ?? false;
                    client.netbirdRunning = client.managementConnected;
                    if (data.management?.url)
                        client.managementUrl = data.management.url;

                    if (client.netbirdRunning) {
                        client.netbirdIp = client.host.parseIp(data.netbirdIp || "");
                        client.netbirdFqdn = data.fqdn || "";
                        client.netbirdStatus = "Connected";

                        var peers = [];
                        var details = data.peers?.details || [];
                        for (var i = 0; i < details.length; i++) {
                            var p = details[i];
                            peers.push({
                                "fqdn": p.fqdn || "",
                                "netbirdIp": client.host.parseIp(p.netbirdIp || ""),
                                "status": p.status || "Disconnected",
                                "connectionType": p.connectionType || "",
                                "lastStatusUpdate": p.lastStatusUpdate || "",
                                "latency": p.latency || 0,
                                "transferReceived": p.transferReceived || 0,
                                "transferSent": p.transferSent || 0,
                                "networks": p.networks || [],
                                "quantumResistance": p.quantumResistance || false
                            });
                        }
                        client.peerList = peers;
                        client.peerCount = data.peers?.total ?? peers.length;
                        client.peerConnected = data.peers?.connected ?? 0;
                        if (client.showPing)
                            client.startPingQueue();
                    } else {
                        client._setDisconnected("Disconnected");
                    }
                } catch (e) {
                    client._setDisconnected("Error");
                }
            } else {
                var err = String(statusProcess.stderr.text || "");
                if (/permission denied/i.test(err))
                    client._setDisconnected("Permission denied");
                else if (/failed to connect to daemon/i.test(err))
                    client._setDisconnected("Daemon not running");
                else
                    client._setDisconnected("Disconnected");
            }
            client._restored = true;
            client.host.saveClientState(client.bin, client._cacheEntry());
        }
    }

    // ── Toggle ──
    function toggle() {
        isRefreshing = true;
        if (netbirdRunning) {
            lastToggleAction = "disconnect";
            toggleProcess.command = [bin, "down"];
        } else {
            lastToggleAction = "connect";
            toggleProcess.command = [bin, "up"];
        }
        toggleProcess.running = true;
    }
    function toggleNetbird() {
        toggle();
    }

    Process {
        id: toggleProcess
        onExited: function (exitCode, exitStatus) {
            if (exitCode === 0) {
                var name = client.clientLabel !== "" ? "NetBird (" + client.clientLabel + ")" : "NetBird";
                client.host.notify(name, client.lastToggleAction === "connect" ? "Connected" : "Disconnected");
            }
            delayTimer.start();
        }
    }

    Timer {
        id: delayTimer
        interval: 500
        repeat: false
        onTriggered: client.refresh()
    }

    // ── Ping ──
    Process {
        id: pingProcess
        stdout: StdioCollector {}

        onExited: function (exitCode, exitStatus) {
            var out = String(pingProcess.stdout.text || "").trim();
            var ip = client.currentPingIp;
            var pings = Object.assign({}, client.peerPings);
            var match = exitCode === 0 ? out.match(/time=([\d.]+)/) : null;
            pings[ip] = match ? parseFloat(match[1]).toFixed(1) : "timeout";
            client.peerPings = pings;
            client.processNextPing();
        }
    }

    function startPingQueue() {
        var queue = [];
        for (var i = 0; i < peerList.length; i++) {
            if (peerList[i].status === "Connected" && peerList[i].netbirdIp)
                queue.push(peerList[i].netbirdIp);
        }
        pingQueue = queue;
        processNextPing();
    }

    function processNextPing() {
        if (pingQueue.length === 0) {
            currentPingIp = "";
            return;
        }
        var ip = pingQueue[0];
        pingQueue = pingQueue.slice(1);
        currentPingIp = ip;
        pingProcess.command = ["ping", "-c", "1", "-W", "2", ip];
        pingProcess.running = true;
    }
}
