import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support 2.0 as P5Support

PlasmoidItem {
    id: root

    property var sysInfo: ({})
    property bool hasData: false

    readonly property string helperPath: {
        var url = Qt.resolvedUrl("../tools/argon-sysinfo.py").toString()
        return url.replace("file://", "")
    }

    Plasmoid.status: PlasmaCore.Types.ActiveStatus

    switchWidth: Kirigami.Units.gridUnit * 16
    switchHeight: Kirigami.Units.gridUnit * 16

    toolTipMainText: "Argon Battery"
    toolTipSubText: {
        if (!hasData) return "Waiting..."
        var s = sysInfo.battery_status
        var p = sysInfo.battery_percent
        return s ? (s + ": " + p + "%") : "Unknown"
    }

    P5Support.DataSource {
        id: infoSource
        engine: "executable"
        connectedSources: ["python3 '" + root.helperPath + "'"]
        interval: 1000
        onNewData: function(source, data) {
            if (data["exit code"] == 0 && data["stdout"].length > 0) {
                try {
                    root.sysInfo = JSON.parse(data["stdout"])
                    root.hasData = true
                } catch(e) {}
            }
        }
    }

    function batteryIconPath() {
        if (!hasData) return "file:///etc/argon/ups/charge_0.png"
        var s = sysInfo.battery_status
        var p = Math.max(0, Math.min(100, sysInfo.battery_percent || 0))
        return (s === "Battery")
            ? "file:///etc/argon/ups/discharge_" + p + ".png"
            : "file:///etc/argon/ups/charge_" + p + ".png"
    }

    compactRepresentation: MouseArea {
        Image {
            anchors.fill: parent
            source: root.batteryIconPath()
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
        onClicked: root.expanded = !root.expanded
    }

    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.preferredWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: implicitHeight
        spacing: Kirigami.Units.smallSpacing

        // Header
        PlasmaExtras.Heading {
            level: 3
            text: "Argon System Monitor"
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // Battery
        PlasmaExtras.Heading {
            level: 4
            text: "Battery"
            Layout.leftMargin: Kirigami.Units.smallSpacing
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            PlasmaComponents.Label { text: "Status"; Layout.fillWidth: true }
            PlasmaComponents.Label {
                text: {
                    if (!root.hasData) return "..."
                    var s = root.sysInfo.battery_status
                    var p = root.sysInfo.battery_percent
                    return s ? (s + " " + p + "%") : "Unknown"
                }
                color: {
                    if (!root.hasData) return Kirigami.Theme.textColor
                    var s = root.sysInfo.battery_status
                    var p = root.sysInfo.battery_percent || 0
                    if (s === "Battery" && p <= 20) return Kirigami.Theme.negativeTextColor
                    if (s === "Battery" && p <= 50) return Kirigami.Theme.neutralTextColor
                    return Kirigami.Theme.textColor
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            PlasmaComponents.Label { text: "Current"; Layout.fillWidth: true }
            PlasmaComponents.Label {
                text: {
                    if (!root.hasData || root.sysInfo.battery_current == null) return "N/A"
                    var mA = root.sysInfo.battery_current
                    if (mA < 0) return Math.abs(mA) + " mA (drain)"
                    return mA + " mA (charge)"
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // Network
        PlasmaExtras.Heading {
            level: 4
            text: "Network"
            Layout.leftMargin: Kirigami.Units.smallSpacing
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            PlasmaComponents.Label { text: "IP Address"; Layout.fillWidth: true }
            PlasmaComponents.Label {
                text: root.hasData ? (root.sysInfo.ip || "N/A") : "..."
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // System
        PlasmaExtras.Heading {
            level: 4
            text: "System"
            Layout.leftMargin: Kirigami.Units.smallSpacing
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            PlasmaComponents.Label { text: "CPU Temp"; Layout.fillWidth: true }
            PlasmaComponents.Label {
                text: root.hasData && root.sysInfo.cpu_temp != null
                    ? (root.sysInfo.cpu_temp + "\u00b0C") : "N/A"
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            PlasmaComponents.Label { text: "RAM"; Layout.fillWidth: true }
            PlasmaComponents.Label {
                text: root.hasData && root.sysInfo.ram_percent != null
                    ? (root.sysInfo.ram_percent + "% of " + root.sysInfo.ram_total + "GB")
                    : "N/A"
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // CPU
        PlasmaExtras.Heading {
            level: 4
            text: "CPU"
            Layout.leftMargin: Kirigami.Units.smallSpacing
        }
        Repeater {
            model: root.hasData && root.sysInfo.cpu_usage
                ? Object.keys(root.sysInfo.cpu_usage).sort()
                : []
            delegate: RowLayout {
                required property string modelData
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                PlasmaComponents.Label {
                    text: modelData.toUpperCase()
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    text: (root.sysInfo.cpu_usage[modelData] || 0) + "%"
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // Storage
        PlasmaExtras.Heading {
            level: 4
            text: "Storage"
            Layout.leftMargin: Kirigami.Units.smallSpacing
        }
        Repeater {
            model: root.hasData ? (root.sysInfo.storage || []) : []
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                PlasmaComponents.Label {
                    text: modelData.device
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    text: modelData.percent + "% of " + modelData.total
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
