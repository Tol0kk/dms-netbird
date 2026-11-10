import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

Column {
    id: contentRoot

    property var widget
    property int peersListMaxHeight: 250
    property bool compactHeader: false

    spacing: Theme.spacingM

    StyledRect {
        width: parent.width
        height: statusCol.implicitHeight + (contentRoot.compactHeader ? Theme.spacingM * 2 : Theme.spacingL * 2)
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: statusCol
            anchors.fill: parent
            anchors.margins: contentRoot.compactHeader ? Theme.spacingM : Theme.spacingL
            spacing: contentRoot.compactHeader ? Theme.spacingXS : Theme.spacingS

            Row {
                width: parent.width
                spacing: contentRoot.compactHeader ? Theme.spacingS : Theme.spacingM

                NetBirdIcon {
                    size: contentRoot.compactHeader ? 24 : 32
                    color: contentRoot.widget.netbirdRunning ? Theme.primary : Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                    crossed: !contentRoot.widget.netbirdRunning
                    colorize: contentRoot.widget.colorizeIcon
                }

                Column {
                    spacing: 2
                    anchors.verticalCenter: parent.verticalCenter

                    StyledText {
                        text: "NetBird Network"
                        font.pixelSize: contentRoot.compactHeader ? Theme.fontSizeSmall : Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                    }

                    StyledText {
                        text: contentRoot.widget.netbirdRunning ? (contentRoot.widget.peerConnected + "/" + contentRoot.widget.peerCount + " peers") : contentRoot.widget.netbirdStatus
                        font.pixelSize: contentRoot.compactHeader ? 12 : Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }
            }

            Item {
                width: 1
                height: contentRoot.compactHeader ? Theme.spacingXS : Theme.spacingS
            }

            StyledText {
                text: contentRoot.widget.netbirdIp
                font.pixelSize: contentRoot.compactHeader ? 12 : Theme.fontSizeSmall
                color: Theme.primary
                visible: contentRoot.widget.showIpAddress && contentRoot.widget.netbirdRunning && contentRoot.widget.netbirdIp !== ""
                width: parent.width

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: contentRoot.widget.copyToClipboard(contentRoot.widget.netbirdIp)
                }
            }

            StyledText {
                text: contentRoot.widget.netbirdFqdn
                font.pixelSize: 12
                color: Theme.surfaceVariantText
                visible: !contentRoot.compactHeader && contentRoot.widget.netbirdRunning && contentRoot.widget.netbirdFqdn !== ""
                width: parent.width
                elide: Text.ElideRight
            }

            Item {
                width: 1
                height: contentRoot.compactHeader ? Theme.spacingXS : Theme.spacingS
                visible: contentRoot.widget.netbirdRunning
            }

            RowLayout {
                id: compactStatusRow
                width: parent.width
                spacing: contentRoot.compactHeader ? Theme.spacingM : Theme.spacingM
                visible: contentRoot.widget.netbirdRunning

                Row {
                    spacing: 4
                    Layout.alignment: Qt.AlignVCenter
                    DankIcon {
                        name: "dns"
                        size: contentRoot.compactHeader ? 14 : 16
                        color: contentRoot.widget.managementConnected ? Theme.primary : Theme.error
                    }
                    StyledText {
                        text: "Management"
                        font.pixelSize: 12
                        color: Theme.surfaceVariantText
                    }
                }

                Row {
                    spacing: 4
                    Layout.alignment: Qt.AlignVCenter
                    DankIcon {
                        name: "wifi"
                        size: contentRoot.compactHeader ? 14 : 16
                        color: contentRoot.widget.signalConnected ? Theme.primary : Theme.error
                    }
                    StyledText {
                        text: "Signal"
                        font.pixelSize: 12
                        color: Theme.surfaceVariantText
                    }
                }

                RowLayout {
                    visible: contentRoot.compactHeader && contentRoot.widget.netbirdFqdn !== ""
                    spacing: 4
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter

                    DankIcon {
                        name: "language"
                        size: 14
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        text: contentRoot.widget.netbirdFqdn
                        font.pixelSize: 12
                        color: Theme.surfaceVariantText
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineVariant
        visible: contentRoot.widget.netbirdRunning && contentRoot.widget.sortedPeerList.length > 0
    }

    Item {
        width: parent.width
        height: Math.min(peersCol.implicitHeight, contentRoot.peersListMaxHeight)
        clip: true
        visible: contentRoot.widget.netbirdRunning && contentRoot.widget.sortedPeerList.length > 0

        Flickable {
            anchors.fill: parent
            contentHeight: peersCol.implicitHeight
            contentWidth: width
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
                id: vScrollBar
                policy: ScrollBar.AsNeeded
                visible: size < 1.0
                width: 6
                minimumSize: 0.1
                contentItem: Rectangle {
                    radius: width / 2
                    color: Theme.primary
                    opacity: parent.pressed ? 0.9 : (parent.hovered ? 0.75 : 0.5)
                }
                background: Rectangle {
                    radius: width / 2
                    color: Theme.surfaceContainerHighest
                    opacity: 0.4
                    visible: vScrollBar.size < 1.0
                }
            }

            Column {
                id: peersCol
                width: parent.width
                spacing: Theme.spacingXS

                Repeater {
                    model: contentRoot.widget.sortedPeerList
                    delegate: Item {
                        width: peersCol.width
                        height: peerRow.height + (actionsCol.visible ? actionsCol.implicitHeight + Theme.spacingXS : 0)

                        readonly property var peerData: modelData
                        readonly property bool peerConnected: peerData.status === "Connected"
                        property bool actionsOpen: contentRoot.widget.isPeerOpen(peerData)

                        onPeerConnectedChanged: {
                            if (!peerConnected) {
                                contentRoot.widget.setPeerOpen(peerData, false);
                            }
                        }

                        Column {
                            anchors.fill: parent
                            spacing: Theme.spacingXS

                            Rectangle {
                                id: peerRow
                                width: parent.width
                                height: 56
                                color: peerMouseArea.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                                radius: Theme.cornerRadius

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingM
                                    spacing: Theme.spacingM

                                    DankIcon {
                                        name: contentRoot.widget.getConnectionIcon(peerData.connectionType)
                                        size: 20
                                        color: peerConnected ? Theme.primary : Theme.surfaceVariantText
                                    }

                                    Column {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        StyledText {
                                            text: contentRoot.widget.getHostname(peerData)
                                            color: Theme.surfaceText
                                            font.weight: Font.Medium
                                            elide: Text.ElideRight
                                            width: parent.width
                                        }
                                        StyledText {
                                            visible: peerData.connectionType !== ""
                                            text: peerData.connectionType
                                            font.pixelSize: 12
                                            color: Theme.surfaceVariantText
                                        }
                                    }

                                    Column {
                                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                        spacing: 2
                                        StyledText {
                                            text: peerData.netbirdIp
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            anchors.right: parent.right
                                        }
                                        StyledText {
                                            visible: contentRoot.widget.showPing && peerConnected
                                            text: {
                                                var pingVal = contentRoot.widget.peerPings[peerData.netbirdIp] ?? "";
                                                if (pingVal === "")
                                                    return "...";
                                                if (pingVal === "timeout")
                                                    return "timeout";
                                                return pingVal + " ms";
                                            }
                                            font.pixelSize: 12
                                            anchors.right: parent.right
                                            color: {
                                                var pingVal = contentRoot.widget.peerPings[peerData.netbirdIp] ?? "";
                                                if (pingVal === "" || pingVal === "timeout")
                                                    return Theme.error;
                                                var ms = parseFloat(pingVal);
                                                if (ms < 50)
                                                    return Theme.primary;
                                                if (ms < 150)
                                                    return "#FF9800";
                                                return Theme.error;
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: peerMouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                                    onClicked: function (mouse) {
                                        if (mouse.button === Qt.LeftButton) {
                                            contentRoot.widget.setPeerOpen(peerData, false);
                                            if (!peerConnected && contentRoot.widget.defaultPeerAction !== "copy-ip") {
                                                return;
                                            }
                                            contentRoot.widget.executePeerAction(contentRoot.widget.defaultPeerAction, peerData);
                                        } else if (mouse.button === Qt.RightButton) {
                                            if (peerConnected) {
                                                contentRoot.widget.setPeerOpen(peerData, !contentRoot.widget.isPeerOpen(peerData));
                                            }
                                        }
                                    }
                                }
                            }

                            Column {
                                id: actionsCol
                                width: parent.width
                                spacing: 2
                                visible: peerConnected && actionsOpen

                                Repeater {
                                    model: [
                                        {
                                            action: "copy-ip",
                                            label: "Copy IP",
                                            icon: "content_copy"
                                        },
                                        {
                                            action: "ssh",
                                            label: "SSH to host",
                                            icon: "terminal"
                                        },
                                        {
                                            action: "ping",
                                            label: "Ping host",
                                            icon: "network_ping"
                                        }
                                    ]

                                    delegate: Rectangle {
                                        width: parent.width
                                        height: 32
                                        radius: Theme.cornerRadius - 2
                                        color: actionArea.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: Theme.spacingM
                                            anchors.rightMargin: Theme.spacingM
                                            spacing: Theme.spacingM

                                            DankIcon {
                                                name: modelData.icon
                                                size: 16
                                                color: Theme.surfaceText
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            StyledText {
                                                text: modelData.label
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.surfaceText
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        MouseArea {
                                            id: actionArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                contentRoot.widget.executePeerAction(modelData.action, peerData);
                                                contentRoot.widget.setPeerOpen(peerData, false);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    StyledText {
        width: parent.width
        text: "No connected peers"
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceVariantText
        horizontalAlignment: Text.AlignHCenter
        visible: contentRoot.widget.netbirdRunning && contentRoot.widget.sortedPeerList.length === 0
    }

    RowLayout {
        width: parent.width
        spacing: Theme.spacingS
        visible: contentRoot.widget.netbirdInstalled

        Button {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            text: contentRoot.widget.netbirdRunning ? "Disconnect" : "Connect"

            contentItem: StyledText {
                text: parent.text
                color: parent.hovered ? Theme.surface : Theme.onPrimary
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.weight: Font.Bold
            }

            background: Rectangle {
                color: contentRoot.widget.netbirdRunning ? Theme.error : Theme.primary
                radius: 24
                opacity: parent.hovered ? 0.8 : 1.0
            }

            onClicked: contentRoot.widget.toggleNetbird()
        }

        Button {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            text: "Admin Console"
            visible: contentRoot.widget.netbirdRunning

            contentItem: StyledText {
                text: parent.text
                color: Theme.primary
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.weight: Font.Medium
            }

            background: Rectangle {
                color: Theme.surfaceContainerHighest
                radius: 24
                opacity: parent.hovered ? 0.8 : 1.0
            }

            onClicked: Qt.openUrlExternally(contentRoot.widget.adminConsoleUrl)
        }
    }
}
