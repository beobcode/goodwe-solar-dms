import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

DesktopPluginComponent {
    id: root

    minWidth: 160
    minHeight: 160

    property real backgroundOpacity: (pluginData.backgroundOpacity ?? 80) / 100
    readonly property color tileBg: Theme.withAlpha(Theme.surfaceContainerHigh, backgroundOpacity)

    // Telemetry state
    property bool isOnline: false
    property string lastUpdated: ""
    property int pvPowerW: 0
    property int batteryPowerW: 0
    property int batteryChargeW: 0
    property int batteryDischargeW: 0
    property int batterySoc: 0
    property string batteryMode: "Idle"
    property int houseConsumptionW: 0
    property int gridPowerW: 0
    property int gridExportW: 0
    property int gridImportW: 0
    property real eDayPvKwh: 0.0
    property real eDayExpKwh: 0.0
    property real eDayLoadKwh: 0.0
    property bool hasFault: false
    property string faultSummary: "Normal"

    function formatWatts(w) {
        const absW = Math.abs(w);
        if (absW >= 1000) {
            return (absW / 1000).toFixed(2) + " kW";
        }
        return absW + " W";
    }

    function getBatteryIcon(soc, isCharging) {
        if (isCharging) return "battery_charging_full";
        if (soc >= 90) return "battery_full";
        if (soc >= 80) return "battery_6_bar";
        if (soc >= 60) return "battery_5_bar";
        if (soc >= 50) return "battery_4_bar";
        if (soc >= 30) return "battery_3_bar";
        if (soc >= 20) return "battery_2_bar";
        return "battery_alert";
    }

    // Polling process
    Timer {
        id: pollTimer
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!fetchProcess.running) {
                fetchProcess.running = true;
            }
        }
    }

    Process {
        id: fetchProcess
        command: ["cat", "/home/dradic/.cache/goodwe_solar.json"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const str = text.trim();
                if (!str) return;
                try {
                    const data = JSON.parse(str);
                    root.isOnline = data.online ?? true;
                    root.lastUpdated = data.last_updated ?? "";
                    root.pvPowerW = data.pv_power_w ?? 0;
                    root.batteryPowerW = data.battery_power_w ?? 0;
                    root.batteryChargeW = data.battery_charge_w ?? 0;
                    root.batteryDischargeW = data.battery_discharge_w ?? 0;
                    root.batterySoc = data.battery_soc ?? 0;
                    root.batteryMode = data.battery_mode ?? "Idle";
                    root.houseConsumptionW = data.house_consumption_w ?? 0;
                    root.gridPowerW = data.grid_power_w ?? 0;
                    root.gridExportW = data.grid_export_w ?? 0;
                    root.gridImportW = data.grid_import_w ?? 0;
                    root.eDayPvKwh = data.e_day_pv_kwh ?? 0.0;
                    root.eDayExpKwh = data.e_day_exp_kwh ?? 0.0;
                    root.eDayLoadKwh = data.e_day_load_kwh ?? 0.0;
                    root.hasFault = data.has_fault ?? false;
                    root.faultSummary = data.fault_summary ?? "Normal";
                } catch (e) {
                }
            }
        }
    }

    // Card background
    Rectangle {
        id: cardBg
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: root.tileBg
        border.width: root.hasFault ? 2 : 0
        border.color: Theme.error

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            // Top Header: Title & Fault / Status
            RowLayout {
                Layout.fillWidth: true

                Row {
                    spacing: Theme.spacingXS
                    DankIcon {
                        name: root.hasFault ? "error" : "solar_power"
                        size: Theme.iconSize - 2
                        color: root.hasFault ? Theme.error : (root.isOnline ? "#f59e0b" : Theme.surfaceVariantText)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    StyledText {
                        text: "GoodWe Solar"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: root.hasFault ? Theme.error : Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Item { Layout.fillWidth: true }

                // Today's kWh Badge
                Rectangle {
                    height: 22
                    width: todayYieldText.implicitWidth + 12
                    radius: 11
                    color: Theme.surfaceContainerHighest

                    StyledText {
                        id: todayYieldText
                        anchors.centerIn: parent
                        text: `${root.eDayPvKwh} kWh`
                        font.pixelSize: Theme.fontSizeSmall - 2
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }
                }
            }

            // Main Solar Generation Display
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Column {
                    anchors.centerIn: parent
                    spacing: 2

                    StyledText {
                        text: root.isOnline ? root.formatWatts(root.pvPowerW) : "Offline"
                        font.pixelSize: Theme.fontSizeLarge + 8
                        font.weight: Font.Bold
                        color: root.pvPowerW > 500 ? "#f59e0b" : Theme.surfaceText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    StyledText {
                        text: root.hasFault ? root.faultSummary : (root.isOnline ? (root.pvPowerW > 0 ? "Generating Power" : "Standby (Night/Cloud)") : "Inverter Unreachable")
                        font.pixelSize: Theme.fontSizeSmall
                        color: root.hasFault ? Theme.error : Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            // Power Flows Grid
            GridLayout {
                Layout.fillWidth: true
                columns: 3
                rowSpacing: Theme.spacingXS
                columnSpacing: Theme.spacingS

                // 1. Battery
                Column {
                    Layout.fillWidth: true
                    spacing: 2
                    Row {
                        spacing: 4
                        anchors.horizontalCenter: parent.horizontalCenter
                        DankIcon {
                            name: root.getBatteryIcon(root.batterySoc, root.batteryChargeW > 0)
                            size: Theme.iconSize - 6
                            color: root.batteryChargeW > 0 ? "#10b981" : (root.batteryDischargeW > 0 ? "#3b82f6" : Theme.surfaceVariantText)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        StyledText {
                            text: `${root.batterySoc}%`
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    StyledText {
                        text: root.batteryChargeW > 0 ? `+${root.formatWatts(root.batteryChargeW)}` : (root.batteryDischargeW > 0 ? `-${root.formatWatts(root.batteryDischargeW)}` : "Idle")
                        font.pixelSize: Theme.fontSizeSmall - 2
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                // 2. House Load
                Column {
                    Layout.fillWidth: true
                    spacing: 2
                    Row {
                        spacing: 4
                        anchors.horizontalCenter: parent.horizontalCenter
                        DankIcon {
                            name: "home"
                            size: Theme.iconSize - 6
                            color: "#8b5cf6"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        StyledText {
                            text: "Load"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    StyledText {
                        text: root.formatWatts(root.houseConsumptionW)
                        font.pixelSize: Theme.fontSizeSmall - 2
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                // 3. Grid Export/Import
                Column {
                    Layout.fillWidth: true
                    spacing: 2
                    Row {
                        spacing: 4
                        anchors.horizontalCenter: parent.horizontalCenter
                        DankIcon {
                            name: "electric_bolt"
                            size: Theme.iconSize - 6
                            color: root.gridExportW > 0 ? "#10b981" : (root.gridImportW > 0 ? "#ef4444" : Theme.surfaceVariantText)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        StyledText {
                            text: root.gridExportW > 0 ? "Export" : "Import"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: root.gridExportW > 0 ? "#10b981" : Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    StyledText {
                        text: root.formatWatts(root.gridExportW > 0 ? root.gridExportW : root.gridImportW)
                        font.pixelSize: Theme.fontSizeSmall - 2
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }
}
