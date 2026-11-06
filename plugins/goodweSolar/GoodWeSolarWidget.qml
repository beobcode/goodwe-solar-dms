import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // Solar Telemetry Properties
    property bool isOnline: false
    property string lastUpdated: ""
    property string inverterModel: "GoodWe"
    property string inverterSerial: ""
    property string workMode: "Normal"

    property int pvPowerW: 0
    property int pv1PowerW: 0
    property int pv2PowerW: 0
    property int batteryPowerW: 0
    property int batteryChargeW: 0
    property int batteryDischargeW: 0
    property int houseConsumptionW: 0
    property int gridPowerW: 0
    property int gridExportW: 0
    property int gridImportW: 0
    property int backupPowerW: 0

    property int batterySoc: 0
    property int batterySoh: 100
    property string batteryMode: "Idle"
    property real batteryVoltage: 0.0
    property real batteryCurrent: 0.0
    property real batteryTemp: 0.0

    property real gridVoltage: 0.0
    property real gridFrequency: 50.0
    property string gridMode: "Connected"

    property real tempAir: 0.0
    property real tempInverter: 0.0

    property real eDayPvKwh: 0.0
    property real eTotalPvKwh: 0.0
    property real eDayExpKwh: 0.0
    property real eDayImpKwh: 0.0
    property real eDayLoadKwh: 0.0
    property real eDayChargeKwh: 0.0
    property real eDayDischargeKwh: 0.0

    property bool hasFault: false
    property bool hasWarning: false
    property string faultSummary: "System Normal"
    property var faultMessages: []

    // Configuration / settings
    property bool showBatteryInBar: pluginData.showBatteryInBar ?? true
    property int pollInterval: parseInt(pluginData.pollInterval || "3000")

    // Formatting helpers
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

    // Control Center Integration
    ccWidgetIcon: hasFault ? "warning" : "solar_power"
    ccWidgetPrimaryText: "Solar: " + formatWatts(pvPowerW)
    ccWidgetSecondaryText: {
        if (!isOnline) return "Offline";
        if (hasFault) return "FAULT: " + faultSummary;
        let bStr = "Bat: " + batterySoc + "%";
        if (batteryChargeW > 0) bStr += " (+" + formatWatts(batteryChargeW) + ")";
        else if (batteryDischargeW > 0) bStr += " (-" + formatWatts(batteryDischargeW) + ")";
        return bStr;
    }
    ccWidgetIsActive: isOnline && (pvPowerW > 0 || batteryPowerW !== 0)
    ccDetailHeight: 340

    onCcWidgetToggled: {
        // Force refresh telemetry when toggled
        fetchStatsProcess.running = true;
        ToastService.showInfo("GoodWe Solar", "Refreshing telemetry...");
    }

    // Background Poll Timer
    Timer {
        id: pollTimer
        interval: root.pollInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!fetchStatsProcess.running) {
                fetchStatsProcess.running = true;
            }
        }
    }

    // Read cache file written by local poller
    Process {
        id: fetchStatsProcess
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
                    root.inverterModel = data.model ?? "GoodWe";
                    root.inverterSerial = data.serial ?? "";
                    root.workMode = data.work_mode ?? "Normal";

                    root.pvPowerW = data.pv_power_w ?? 0;
                    root.pv1PowerW = data.pv1_power_w ?? 0;
                    root.pv2PowerW = data.pv2_power_w ?? 0;
                    root.batteryPowerW = data.battery_power_w ?? 0;
                    root.batteryChargeW = data.battery_charge_w ?? 0;
                    root.batteryDischargeW = data.battery_discharge_w ?? 0;
                    root.houseConsumptionW = data.house_consumption_w ?? 0;
                    root.gridPowerW = data.grid_power_w ?? 0;
                    root.gridExportW = data.grid_export_w ?? 0;
                    root.gridImportW = data.grid_import_w ?? 0;
                    root.backupPowerW = data.backup_power_w ?? 0;

                    root.batterySoc = data.battery_soc ?? 0;
                    root.batterySoh = data.battery_soh ?? 100;
                    root.batteryMode = data.battery_mode ?? "Idle";
                    root.batteryVoltage = data.battery_voltage ?? 0.0;
                    root.batteryCurrent = data.battery_current ?? 0.0;
                    root.batteryTemp = data.battery_temp ?? 0.0;

                    root.gridVoltage = data.grid_voltage ?? 0.0;
                    root.gridFrequency = data.grid_frequency ?? 50.0;
                    root.gridMode = data.grid_mode ?? "Connected";

                    root.tempAir = data.temp_air ?? 0.0;
                    root.tempInverter = data.temp_inverter ?? 0.0;

                    root.eDayPvKwh = data.e_day_pv_kwh ?? 0.0;
                    root.eTotalPvKwh = data.e_total_pv_kwh ?? 0.0;
                    root.eDayExpKwh = data.e_day_exp_kwh ?? 0.0;
                    root.eDayImpKwh = data.e_day_imp_kwh ?? 0.0;
                    root.eDayLoadKwh = data.e_day_load_kwh ?? 0.0;
                    root.eDayChargeKwh = data.e_day_charge_kwh ?? 0.0;
                    root.eDayDischargeKwh = data.e_day_discharge_kwh ?? 0.0;

                    root.hasFault = data.has_fault ?? false;
                    root.hasWarning = data.has_warning ?? false;
                    root.faultSummary = data.fault_summary ?? "System Normal";
                    root.faultMessages = data.fault_messages ?? [];
                } catch (e) {
                    // Ignore parse error while file is being swapped
                }
            }
        }
    }

    // 1. Horizontal Status Bar Pill
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            // Solar Icon & Value
            DankIcon {
                name: root.hasFault ? "error" : "solar_power"
                color: {
                    if (root.hasFault) return Theme.error;
                    if (!root.isOnline) return Theme.surfaceVariantText;
                    return root.pvPowerW > 500 ? "#f59e0b" : Theme.primary;
                }
                size: Theme.iconSize - 4
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.isOnline ? root.formatWatts(root.pvPowerW) : "Offline"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: root.hasFault ? Theme.error : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }

            // Battery (if enabled)
            Row {
                spacing: Theme.spacingXS
                visible: root.showBatteryInBar && root.isOnline
                anchors.verticalCenter: parent.verticalCenter

                DankIcon {
                    name: root.getBatteryIcon(root.batterySoc, root.batteryChargeW > 0)
                    color: {
                        if (root.batteryChargeW > 0) return "#10b981";
                        if (root.batterySoc <= 20) return Theme.error;
                        return Theme.surfaceVariantText;
                    }
                    size: Theme.iconSize - 4
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: `${root.batterySoc}%`
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // 2. Vertical Bar Pill
    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.hasFault ? "error" : "solar_power"
                color: root.hasFault ? Theme.error : "#f59e0b"
                size: Theme.iconSize - 4
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.isOnline ? `${(root.pvPowerW / 1000).toFixed(1)}k` : "Off"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // 3. Control Center Detail Content Dropdown
    ccDetailContent: Component {
        Rectangle {
            id: detailRoot
            implicitHeight: 330
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                // Header / Status row
                Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    DankIcon {
                        name: root.hasFault ? "error" : (root.isOnline ? "check_circle" : "cloud_off")
                        color: root.hasFault ? Theme.error : (root.isOnline ? "#10b981" : Theme.surfaceVariantText)
                        size: Theme.iconSize
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        StyledText {
                            text: root.hasFault ? "FAULT ACTIVE" : "GoodWe Inverter Online"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                            color: root.hasFault ? Theme.error : Theme.surfaceText
                        }
                        StyledText {
                            text: root.faultSummary + (root.lastUpdated ? ` • ${root.lastUpdated}` : "")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }
                }

                // 2x2 Grid of Power Flows
                Grid {
                    width: parent.width
                    columns: 2
                    spacing: Theme.spacingS

                    // Solar Tile
                    Rectangle {
                        width: (parent.width - Theme.spacingS) / 2
                        height: 60
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHighest

                        Row {
                            anchors.centerIn: parent
                            spacing: Theme.spacingS
                            DankIcon {
                                name: "solar_power"
                                color: "#f59e0b"
                                size: Theme.iconSize
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                StyledText {
                                    text: "Solar PV"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                                StyledText {
                                    text: root.formatWatts(root.pvPowerW)
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Bold
                                    color: Theme.surfaceText
                                }
                            }
                        }
                    }

                    // Battery Tile
                    Rectangle {
                        width: (parent.width - Theme.spacingS) / 2
                        height: 60
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHighest

                        Row {
                            anchors.centerIn: parent
                            spacing: Theme.spacingS
                            DankIcon {
                                name: root.getBatteryIcon(root.batterySoc, root.batteryChargeW > 0)
                                color: root.batteryChargeW > 0 ? "#10b981" : (root.batteryDischargeW > 0 ? "#3b82f6" : Theme.surfaceVariantText)
                                size: Theme.iconSize
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                StyledText {
                                    text: `Battery (${root.batterySoc}%)`
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                                StyledText {
                                    text: root.batteryChargeW > 0 ? `+${root.formatWatts(root.batteryChargeW)}` : (root.batteryDischargeW > 0 ? `-${root.formatWatts(root.batteryDischargeW)}` : "Idle")
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Bold
                                    color: Theme.surfaceText
                                }
                            }
                        }
                    }

                    // House Consumption Tile
                    Rectangle {
                        width: (parent.width - Theme.spacingS) / 2
                        height: 60
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHighest

                        Row {
                            anchors.centerIn: parent
                            spacing: Theme.spacingS
                            DankIcon {
                                name: "home"
                                color: "#8b5cf6"
                                size: Theme.iconSize
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                StyledText {
                                    text: "House Load"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                                StyledText {
                                    text: root.formatWatts(root.houseConsumptionW)
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Bold
                                    color: Theme.surfaceText
                                }
                            }
                        }
                    }

                    // Grid Flow Tile
                    Rectangle {
                        width: (parent.width - Theme.spacingS) / 2
                        height: 60
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHighest

                        Row {
                            anchors.centerIn: parent
                            spacing: Theme.spacingS
                            DankIcon {
                                name: "electric_bolt"
                                color: root.gridExportW > 0 ? "#10b981" : (root.gridImportW > 0 ? "#ef4444" : Theme.surfaceVariantText)
                                size: Theme.iconSize
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                StyledText {
                                    text: root.gridExportW > 0 ? "Grid Export" : "Grid Import"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                                StyledText {
                                    text: root.formatWatts(root.gridExportW > 0 ? root.gridExportW : root.gridImportW)
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Bold
                                    color: Theme.surfaceText
                                }
                            }
                        }
                    }
                }

                // Daily Energy Statistics Row
                Rectangle {
                    width: parent.width
                    height: 54
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHighest

                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.spacingL

                        Column {
                            StyledText {
                                text: "Today's Yield"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            StyledText {
                                text: `${root.eDayPvKwh} kWh`
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }

                        Column {
                            StyledText {
                                text: "Exported"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            StyledText {
                                text: `${root.eDayExpKwh} kWh`
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Bold
                                color: "#10b981"
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }

                        Column {
                            StyledText {
                                text: "House Used"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            StyledText {
                                text: `${root.eDayLoadKwh} kWh`
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }
                }

                // Inverter & Battery Hardware info footer
                Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    StyledText {
                        text: `Serial: ${root.inverterSerial || "N/A"}`
                        font.pixelSize: Theme.fontSizeSmall - 1
                        color: Theme.surfaceVariantText
                    }
                    StyledText {
                        text: `• Inverter Temp: ${root.tempInverter}°C`
                        font.pixelSize: Theme.fontSizeSmall - 1
                        color: Theme.surfaceVariantText
                    }
                    StyledText {
                        text: `• Bat Temp: ${root.batteryTemp}°C`
                        font.pixelSize: Theme.fontSizeSmall - 1
                        color: Theme.surfaceVariantText
                    }
                }
            }
        }
    }

    // 4. Popout Dialog (When user clicks on DankBar pill)
    popoutWidth: 420
    popoutHeight: 400
    popoutContent: Component {
        PopoutComponent {
            headerText: "GoodWe Solar Monitor"
            detailsText: root.faultSummary
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // Quick Overview Badges
                Row {
                    width: parent.width
                    spacing: Theme.spacingM

                    Rectangle {
                        width: (parent.width - Theme.spacingM) / 2
                        height: 80
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHighest

                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            DankIcon {
                                name: "solar_power"
                                color: "#f59e0b"
                                size: Theme.iconSize
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            StyledText {
                                text: root.formatWatts(root.pvPowerW)
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            StyledText {
                                text: `Today: ${root.eDayPvKwh} kWh`
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }

                    Rectangle {
                        width: (parent.width - Theme.spacingM) / 2
                        height: 80
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHighest

                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            DankIcon {
                                name: root.getBatteryIcon(root.batterySoc, root.batteryChargeW > 0)
                                color: root.batteryChargeW > 0 ? "#10b981" : (root.batteryDischargeW > 0 ? "#3b82f6" : Theme.surfaceVariantText)
                                size: Theme.iconSize
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            StyledText {
                                text: `${root.batterySoc}%`
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            StyledText {
                                text: root.batteryMode + (root.batteryChargeW > 0 ? ` (${root.formatWatts(root.batteryChargeW)})` : "")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }
                }

                // Grid and House Metrics List
                Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    Rectangle {
                        width: parent.width
                        height: 38
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingM
                            anchors.rightMargin: Theme.spacingM
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "home"
                                color: "#8b5cf6"
                                size: Theme.iconSize - 4
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: "House Consumption"
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Item { Layout.fillWidth: true; width: 10 }
                            StyledText {
                                text: root.formatWatts(root.houseConsumptionW)
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 38
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingM
                            anchors.rightMargin: Theme.spacingM
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "electric_bolt"
                                color: root.gridExportW > 0 ? "#10b981" : (root.gridImportW > 0 ? "#ef4444" : Theme.surfaceVariantText)
                                size: Theme.iconSize - 4
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: root.gridExportW > 0 ? "Grid Export" : "Grid Import"
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Item { Layout.fillWidth: true; width: 10 }
                            StyledText {
                                text: root.formatWatts(root.gridExportW > 0 ? root.gridExportW : root.gridImportW)
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 38
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingM
                            anchors.rightMargin: Theme.spacingM
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "thermostat"
                                color: Theme.surfaceVariantText
                                size: Theme.iconSize - 4
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: "Inverter Temperature"
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Item { Layout.fillWidth: true; width: 10 }
                            StyledText {
                                text: `${root.tempInverter}°C (Air: ${root.tempAir}°C)`
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }
    }
}
