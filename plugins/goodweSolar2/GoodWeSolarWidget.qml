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

    // Historical graphs data
    property var historyPv: []
    property var historyLoad: []
    property var historyGrid: []
    property var historySoc: []
    property var historyBattery: []
    property var recentDays: []

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

                    root.historyPv = data.history_pv ?? [];
                    root.historyLoad = data.history_load ?? [];
                    root.historyGrid = data.history_grid ?? [];
                    root.historySoc = data.history_soc ?? [];
                    root.historyBattery = data.history_battery ?? [];
                    root.recentDays = data.recent_days ?? [];
                } catch (e) {
                }
            }
        }
    }

    layerNamespacePlugin: "goodwe-solar"

    // 1. Horizontal Status Bar Pill
    horizontalBarPill: Component {
        Item {
            id: horizPillRoot
            implicitWidth: horizRow.implicitWidth
            implicitHeight: horizRow.implicitHeight

            Row {
                id: horizRow
                spacing: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter

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
    }

    // 2. Vertical Bar Pill
    verticalBarPill: Component {
        Item {
            id: vertPillRoot
            implicitWidth: vertCol.implicitWidth
            implicitHeight: vertCol.implicitHeight

            Column {
                id: vertCol
                spacing: Theme.spacingXS
                anchors.centerIn: parent

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
                                color: root.gridPowerW > 0 ? "#10b981" : (root.gridPowerW < 0 ? "#ef4444" : Theme.surfaceVariantText)
                                size: Theme.iconSize
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                StyledText {
                                    text: root.gridPowerW > 0 ? "Grid (Export)" : (root.gridPowerW < 0 ? "Grid (Import)" : "Grid Flow")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                                StyledText {
                                    text: root.gridPowerW > 0 ? `+${root.formatWatts(root.gridPowerW)}` : (root.gridPowerW < 0 ? `-${root.formatWatts(root.gridPowerW)}` : "0 W")
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Bold
                                    color: root.gridPowerW > 0 ? "#10b981" : (root.gridPowerW < 0 ? "#ef4444" : Theme.surfaceText)
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

    // 4. Centered Dash / Popout Dialog
    // Sized generously (720x520) with real-time curves & daily bar chart
    popoutWidth: 720
    popoutHeight: 520

    popoutContent: Component {
        PopoutComponent {
            id: popoutComp
            headerText: "GoodWe Solar & Battery System"
            detailsText: `${root.faultSummary} • Updated ${root.lastUpdated}`
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // Top 4 Flow Tiles
                Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    // Solar Tile
                    Rectangle {
                        width: (parent.width - Theme.spacingS * 3) / 4
                        height: 70
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHighest

                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Row {
                                spacing: 4
                                anchors.horizontalCenter: parent.horizontalCenter
                                DankIcon {
                                    name: "solar_power"
                                    color: "#f59e0b"
                                    size: Theme.iconSize - 6
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: "Solar PV"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            StyledText {
                                text: root.formatWatts(root.pvPowerW)
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                                color: "#f59e0b"
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            StyledText {
                                text: `Day: ${root.eDayPvKwh} kWh`
                                font.pixelSize: Theme.fontSizeSmall - 2
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }

                    // Battery Tile
                    Rectangle {
                        width: (parent.width - Theme.spacingS * 3) / 4
                        height: 70
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHighest

                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Row {
                                spacing: 4
                                anchors.horizontalCenter: parent.horizontalCenter
                                DankIcon {
                                    name: root.getBatteryIcon(root.batterySoc, root.batteryChargeW > 0)
                                    color: root.batteryChargeW > 0 ? "#10b981" : (root.batteryDischargeW > 0 ? "#3b82f6" : Theme.surfaceVariantText)
                                    size: Theme.iconSize - 6
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: `Bat ${root.batterySoc}%`
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            StyledText {
                                text: root.batteryChargeW > 0 ? `+${root.formatWatts(root.batteryChargeW)}` : (root.batteryDischargeW > 0 ? `-${root.formatWatts(root.batteryDischargeW)}` : "0 W")
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                                color: root.batteryChargeW > 0 ? "#10b981" : (root.batteryDischargeW > 0 ? "#3b82f6" : Theme.surfaceText)
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            StyledText {
                                text: root.batteryMode
                                font.pixelSize: Theme.fontSizeSmall - 2
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }

                    // Home Load Tile
                    Rectangle {
                        width: (parent.width - Theme.spacingS * 3) / 4
                        height: 70
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHighest

                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Row {
                                spacing: 4
                                anchors.horizontalCenter: parent.horizontalCenter
                                DankIcon {
                                    name: "home"
                                    color: "#8b5cf6"
                                    size: Theme.iconSize - 6
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: "Home Load"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            StyledText {
                                text: root.formatWatts(root.houseConsumptionW)
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                                color: "#8b5cf6"
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            StyledText {
                                text: `Day: ${root.eDayLoadKwh} kWh`
                                font.pixelSize: Theme.fontSizeSmall - 2
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }

                    // Grid Flow Tile
                    Rectangle {
                        width: (parent.width - Theme.spacingS * 3) / 4
                        height: 70
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHighest

                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Row {
                                spacing: 4
                                anchors.horizontalCenter: parent.horizontalCenter
                                DankIcon {
                                    name: "electric_bolt"
                                    color: root.gridPowerW > 0 ? "#10b981" : (root.gridPowerW < 0 ? "#ef4444" : Theme.surfaceVariantText)
                                    size: Theme.iconSize - 6
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: root.gridPowerW > 0 ? "Grid (Export)" : (root.gridPowerW < 0 ? "Grid (Import)" : "Grid Flow")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            StyledText {
                                text: root.gridPowerW > 0 ? `+${root.formatWatts(root.gridPowerW)}` : (root.gridPowerW < 0 ? `-${root.formatWatts(root.gridPowerW)}` : "0 W")
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                                color: root.gridPowerW > 0 ? "#10b981" : (root.gridPowerW < 0 ? "#ef4444" : Theme.surfaceText)
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            StyledText {
                                text: `Export: ${root.eDayExpKwh} kWh`
                                font.pixelSize: Theme.fontSizeSmall - 2
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }
                }

                // Intra-day Solar Generation Graph
                Rectangle {
                    width: parent.width
                    height: 200
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHighest

                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        spacing: 4

                        Row {
                            width: parent.width
                            StyledText {
                                text: "Solar, Load, Grid & Battery %"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                            }
                            Item { Layout.fillWidth: true; width: 10 }
                            Row {
                                spacing: Theme.spacingS
                                Row {
                                    spacing: 3
                                    Rectangle { width: 8; height: 8; radius: 4; color: "#f59e0b"; anchors.verticalCenter: parent.verticalCenter }
                                    StyledText { text: "PV (W)"; font.pixelSize: Theme.fontSizeSmall - 3; color: Theme.surfaceVariantText }
                                }
                                Row {
                                    spacing: 3
                                    Rectangle { width: 8; height: 8; radius: 4; color: "#8b5cf6"; anchors.verticalCenter: parent.verticalCenter }
                                    StyledText { text: "Load (W)"; font.pixelSize: Theme.fontSizeSmall - 3; color: Theme.surfaceVariantText }
                                }
                                Row {
                                    spacing: 3
                                    Rectangle { width: 8; height: 8; radius: 4; color: "#0284c7"; anchors.verticalCenter: parent.verticalCenter }
                                    StyledText { text: "Grid (+/-)"; font.pixelSize: Theme.fontSizeSmall - 3; color: Theme.surfaceVariantText }
                                }
                                Row {
                                    spacing: 3
                                    Rectangle { width: 8; height: 8; radius: 4; color: "#10b981"; anchors.verticalCenter: parent.verticalCenter }
                                    StyledText { text: "Bat (%)"; font.pixelSize: Theme.fontSizeSmall - 3; color: "#10b981" }
                                }
                            }
                        }

                        // Canvas Graph Area
                        Canvas {
                            id: solarCanvas
                            width: parent.width
                            height: parent.height - 30
                            renderStrategy: Canvas.Cooperative

                            property var pvData: root.historyPv
                            property var loadData: root.historyLoad
                            property var gridData: root.historyGrid
                            property var socData: root.historySoc
                            property var batData: root.historyBattery

                            onPvDataChanged: requestPaint()
                            onLoadDataChanged: requestPaint()
                            onGridDataChanged: requestPaint()
                            onSocDataChanged: requestPaint()
                            onBatDataChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()

                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                ctx.clearRect(0, 0, width, height);

                                if (!pvData || pvData.length < 2) {
                                    ctx.fillStyle = Qt.rgba(1, 1, 1, 0.4);
                                    ctx.font = "12px sans-serif";
                                    ctx.textAlign = "center";
                                    ctx.fillText("Gathering day data points...", width / 2, height / 2);
                                    return;
                                }

                                const n = pvData.length;
                                const padLeft = 4;
                                const padRight = 36; // leave margin for battery SoC right Y-axis
                                const padTop = 10;
                                const padBottom = 16;
                                const chartW = width - padLeft - padRight;
                                const chartH = height - padTop - padBottom;
                                const stepX = chartW / Math.max(1, n - 1);

                                // Find max and min power across all series (Watts)
                                let maxVal = 1000;
                                let minVal = 0;

                                for (let i = 0; i < n; i++) {
                                    maxVal = Math.max(maxVal, pvData[i] || 0);
                                    if (loadData && loadData.length > i) maxVal = Math.max(maxVal, loadData[i] || 0);
                                    if (gridData && gridData.length > i) {
                                        maxVal = Math.max(maxVal, gridData[i] || 0);
                                        minVal = Math.min(minVal, gridData[i] || 0);
                                    }
                                    if (batData && batData.length > i) {
                                        maxVal = Math.max(maxVal, batData[i] || 0);
                                        minVal = Math.min(minVal, batData[i] || 0);
                                    }
                                }

                                // Pad power range
                                maxVal = Math.ceil(maxVal * 1.1 / 500) * 500;
                                if (minVal < 0) {
                                    minVal = Math.floor(minVal * 1.1 / 500) * 500;
                                } else {
                                    minVal = 0;
                                }
                                const rangeVal = Math.max(1, maxVal - minVal);

                                function getY(val) {
                                    const norm = (val - minVal) / rangeVal;
                                    return padTop + chartH - (norm * chartH);
                                }

                                // Draw Zero Baseline if minVal < 0
                                if (minVal < 0) {
                                    const yZero = getY(0);
                                    ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.2);
                                    ctx.lineWidth = 1;
                                    ctx.setLineDash([2, 4]);
                                    ctx.beginPath();
                                    ctx.moveTo(padLeft, yZero);
                                    ctx.lineTo(padLeft + chartW, yZero);
                                    ctx.stroke();
                                    ctx.setLineDash([]);

                                    ctx.fillStyle = Qt.rgba(1, 1, 1, 0.4);
                                    ctx.font = "9px sans-serif";
                                    ctx.textAlign = "left";
                                    ctx.fillText("0 W", padLeft + 2, yZero - 2);
                                }

                                // 1. Draw Solar PV Area Gradient & Line
                                const gradPv = ctx.createLinearGradient(0, padTop, 0, padTop + chartH);
                                gradPv.addColorStop(0, Qt.rgba(0.96, 0.62, 0.04, 0.35));
                                gradPv.addColorStop(1, Qt.rgba(0.96, 0.62, 0.04, 0.02));

                                ctx.fillStyle = gradPv;
                                ctx.beginPath();
                                ctx.moveTo(padLeft, getY(0));
                                for (let i = 0; i < n; i++) {
                                    const px = padLeft + (i * stepX);
                                    const py = getY(pvData[i] || 0);
                                    ctx.lineTo(px, py);
                                }
                                ctx.lineTo(padLeft + chartW, getY(0));
                                ctx.closePath();
                                ctx.fill();

                                ctx.strokeStyle = "#f59e0b";
                                ctx.lineWidth = 2.0;
                                ctx.beginPath();
                                for (let i = 0; i < n; i++) {
                                    const px = padLeft + (i * stepX);
                                    const py = getY(pvData[i] || 0);
                                    i === 0 ? ctx.moveTo(px, py) : ctx.lineTo(px, py);
                                }
                                ctx.stroke();

                                // 2. Draw House Load Line (Purple)
                                if (loadData && loadData.length === n) {
                                    ctx.strokeStyle = "#8b5cf6";
                                    ctx.lineWidth = 1.6;
                                    ctx.setLineDash([3, 3]);
                                    ctx.beginPath();
                                    for (let j = 0; j < n; j++) {
                                        const px = padLeft + (j * stepX);
                                        const py = getY(loadData[j] || 0);
                                        j === 0 ? ctx.moveTo(px, py) : ctx.lineTo(px, py);
                                    }
                                    ctx.stroke();
                                    ctx.setLineDash([]);
                                }

                                // 3. Draw Grid Power Line (Sky Blue #0284c7)
                                // Positive = Exporting to grid; Negative = Importing from grid
                                if (gridData && gridData.length === n) {
                                    ctx.strokeStyle = "#0284c7";
                                    ctx.lineWidth = 1.6;
                                    ctx.beginPath();
                                    for (let k = 0; k < n; k++) {
                                        const px = padLeft + (k * stepX);
                                        const py = getY(gridData[k] || 0);
                                        k === 0 ? ctx.moveTo(px, py) : ctx.lineTo(px, py);
                                    }
                                    ctx.stroke();
                                }

                                // 4. Draw Battery SoC % Line & Right Y-Axis (Emerald #10b981)
                                // Scaled 0 to 100% on the right margin
                                if (socData && socData.length === n) {
                                    function getSocY(soc) {
                                        const clamped = Math.max(0, Math.min(100, soc));
                                        return padTop + chartH - ((clamped / 100.0) * chartH);
                                    }

                                    // Right Y-axis labels: 100%, 50%, 0%
                                    ctx.fillStyle = Qt.rgba(0.06, 0.72, 0.50, 0.8);
                                    ctx.font = "9px sans-serif";
                                    ctx.textAlign = "left";
                                    ctx.fillText("100%", padLeft + chartW + 4, padTop + 8);
                                    ctx.fillText("50%", padLeft + chartW + 4, padTop + (chartH / 2) + 3);
                                    ctx.fillText("0%", padLeft + chartW + 4, padTop + chartH);

                                    // SoC curve
                                    ctx.strokeStyle = "#10b981";
                                    ctx.lineWidth = 1.8;
                                    ctx.beginPath();
                                    for (let m = 0; m < n; m++) {
                                        const px = padLeft + (m * stepX);
                                        const py = getSocY(socData[m] || 0);
                                        m === 0 ? ctx.moveTo(px, py) : ctx.lineTo(px, py);
                                    }
                                    ctx.stroke();
                                }
                            }
                        }
                    }
                }

                // Daily Yield Summary Bars (Past Days)
                Rectangle {
                    width: parent.width
                    height: 120
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHighest

                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        spacing: 4

                        Row {
                            width: parent.width
                            StyledText {
                                text: "Daily Total Generation (kWh)"
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                            }
                            Item { Layout.fillWidth: true; width: 10 }
                            StyledText {
                                text: `Total PV: ${root.eTotalPvKwh} kWh`
                                font.pixelSize: Theme.fontSizeSmall - 2
                                color: Theme.surfaceVariantText
                            }
                        }

                        // Bar representations
                        Row {
                            width: parent.width
                            height: parent.height - 28
                            spacing: Theme.spacingS

                            Repeater {
                                model: root.recentDays.length > 0 ? root.recentDays : [{ day_name: "Today", pv_kwh: root.eDayPvKwh, exp_kwh: root.eDayExpKwh }]

                                Rectangle {
                                    width: (parent.width - (Theme.spacingS * 6)) / Math.max(1, (root.recentDays.length || 1))
                                    height: parent.height
                                    color: "transparent"

                                    Column {
                                        anchors.fill: parent
                                        spacing: 2

                                        StyledText {
                                            text: `${modelData.pv_kwh}k`
                                            font.pixelSize: Theme.fontSizeSmall - 3
                                            font.weight: Font.Bold
                                            color: "#f59e0b"
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }

                                        Item {
                                            width: parent.width
                                            height: parent.height - 30

                                            Rectangle {
                                                width: Math.min(24, parent.width * 0.7)
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.bottom: parent.bottom
                                                // Max day scale ~35 kWh
                                                height: Math.max(4, Math.min(parent.height, (modelData.pv_kwh / 35.0) * parent.height))
                                                radius: 4
                                                color: "#f59e0b"
                                            }
                                        }

                                        StyledText {
                                            text: modelData.day_name || "Day"
                                            font.pixelSize: Theme.fontSizeSmall - 3
                                            color: Theme.surfaceVariantText
                                            anchors.horizontalCenter: parent.horizontalCenter
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
