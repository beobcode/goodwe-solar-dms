import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var popoutService: null

    pillClickAction: () => {
        const tabId = "plugin_" + pluginId;
        const host = root.surfaceContext?.host;
        if (host && typeof host.triggerDashTab === "function") {
            host.triggerDashTab(tabId);
            return;
        }
        if (typeof PopoutService !== "undefined" && PopoutService.toggleDankDash) {
            PopoutService.toggleDankDash(tabId);
        } else if (popoutService && popoutService.toggleDankDash) {
            popoutService.toggleDankDash(tabId);
        }
    }

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

    property string semsPortalUrl: pluginData.portalUrl || "https://au-semsplus.goodwe.com/"

    // Configuration / settings
    property bool showBatteryInBar: pluginData.showBatteryInBar ?? true
    property bool showDailyEnergy: pluginData.showDailyEnergy ?? true

    readonly property string cacheFilePath: {
        if (pluginData.cacheFilePath && pluginData.cacheFilePath.trim().length > 0) {
            return pluginData.cacheFilePath.trim();
        }
        const xdg = Quickshell.env("XDG_CACHE_HOME");
        const home = Quickshell.env("HOME") || "";
        const base = (xdg && xdg.length > 0) ? xdg : (home + "/.cache");
        return base + "/goodwe_solar.json";
    }

    readonly property string historyFilePath: {
        if (pluginData.cacheFilePath && pluginData.cacheFilePath.trim().length > 0) {
            const custom = pluginData.cacheFilePath.trim();
            const lastSlash = custom.lastIndexOf("/");
            const dir = lastSlash >= 0 ? custom.substring(0, lastSlash) : "";
            return (dir ? dir + "/" : "") + "goodwe_solar_history.json";
        }
        const xdg = Quickshell.env("XDG_CACHE_HOME");
        const home = Quickshell.env("HOME") || "";
        const base = (xdg && xdg.length > 0) ? xdg : (home + "/.cache");
        return base + "/goodwe_solar_history.json";
    }

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
    ccDetailHeight: Theme.iconSizeLarge * 10 + Theme.spacingXL

    onCcWidgetToggled: {
        cacheFileView.reload();
        historyFileView.reload();
        ToastService.showInfo("GoodWe Solar", "Refreshing telemetry...");
    }

    function parseTelemetry() {
        try {
            const str = cacheFileView.text();
            if (!str || !str.trim()) {
                root.isOnline = false;
                return;
            }
            const data = JSON.parse(str);
            const nowSec = Math.floor(Date.now() / 1000);
            const ts = data.timestamp || 0;
            root.lastTelemetryTimestamp = ts;
            // Mark offline if telemetry is older than 30 seconds or poller flagged offline
            root.isOnline = (data.online ?? true) && ((nowSec - ts) < 30);
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

            // If history data is present in live snapshot (e.g. from older poller), keep backwards compatibility
            if (data.history_pv) root.historyPv = data.history_pv;
            if (data.history_load) root.historyLoad = data.history_load;
            if (data.history_grid) root.historyGrid = data.history_grid;
            if (data.history_soc) root.historySoc = data.history_soc;
            if (data.history_battery) root.historyBattery = data.history_battery;
            if (data.recent_days) root.recentDays = data.recent_days;
        } catch (e) {
            root.isOnline = false;
        }
    }

    function parseHistory() {
        try {
            const str = historyFileView.text();
            if (!str || !str.trim()) return;
            const hData = JSON.parse(str);
            if (hData.history_pv) root.historyPv = hData.history_pv;
            if (hData.history_load) root.historyLoad = hData.history_load;
            if (hData.history_grid) root.historyGrid = hData.history_grid;
            if (hData.history_soc) root.historySoc = hData.history_soc;
            if (hData.history_battery) root.historyBattery = hData.history_battery;
            if (hData.recent_days) root.recentDays = hData.recent_days;
        } catch (e) {
            // Ignore parse errors on partial writes
        }
    }

    property int lastTelemetryTimestamp: 0

    function checkStaleness() {
        if (!root.isOnline && root.lastTelemetryTimestamp === 0) return;
        const nowSec = Math.floor(Date.now() / 1000);
        if (root.lastTelemetryTimestamp > 0 && (nowSec - root.lastTelemetryTimestamp) >= 30) {
            root.isOnline = false;
        }
    }

    // Periodic staleness check every 15s in case poller stops or disconnects without rewriting file
    Timer {
        id: stalenessTimer
        interval: 15000
        repeat: true
        running: true
        onTriggered: root.checkStaleness()
    }

    // Reactively watch 3s live cache file changes without continuous polling
    FileView {
        id: cacheFileView
        path: root.cacheFilePath
        watchChanges: true
        onLoaded: root.parseTelemetry()
        onFileChanged: cacheFileView.reload()
    }

    // Reactively watch 60s history cache file changes
    FileView {
        id: historyFileView
        path: root.historyFilePath
        watchChanges: true
        onLoaded: root.parseHistory()
        onFileChanged: historyFileView.reload()
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
                DIcon {
                    name: root.hasFault ? "error" : "solar_power"
                    color: {
                        if (root.hasFault) return Theme.error;
                        if (!root.isOnline) return Theme.surfaceVariantText;
                        return root.pvPowerW > 500 ? Theme.warning : Theme.primary;
                    }
                    size: Theme.iconSizeSmall
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.isOnline ? root.formatWatts(root.pvPowerW) : "Offline"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: root.hasFault ? Theme.error : Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Daily kWh (if enabled)
                StyledText {
                    visible: root.showDailyEnergy && root.isOnline && root.eDayPvKwh > 0
                    text: `(${root.eDayPvKwh}k)`
                    font.pixelSize: Theme.fontSizeXSmall
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Battery (if enabled)
                Row {
                    spacing: Theme.spacingXS
                    visible: root.showBatteryInBar && root.isOnline
                    anchors.verticalCenter: parent.verticalCenter

                    DIcon {
                        name: root.getBatteryIcon(root.batterySoc, root.batteryChargeW > 0)
                        color: {
                            if (root.batteryChargeW > 0) return Theme.success;
                            if (root.batterySoc <= 20) return Theme.error;
                            return Theme.surfaceVariantText;
                        }
                        size: Theme.iconSizeSmall
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

                DIcon {
                    name: root.hasFault ? "error" : "solar_power"
                    color: root.hasFault ? Theme.error : Theme.warning
                    size: Theme.iconSizeSmall
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
            implicitHeight: Theme.iconSizeLarge * 10 + Theme.spacingM
            radius: Theme.cornerRadius
            color: Theme.cardSurface

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                // Header / Status row with SEMS Portal button
                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingS

                    DIcon {
                        name: root.hasFault ? "error" : (root.isOnline ? "check_circle" : "cloud_off")
                        color: root.hasFault ? Theme.error : (root.isOnline ? Theme.success : Theme.surfaceVariantText)
                        size: Theme.iconSize
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Column {
                        Layout.alignment: Qt.AlignVCenter
                        StyledText {
                            text: root.hasFault ? "FAULT ACTIVE" : (root.isOnline ? "GoodWe Inverter Online" : "GoodWe Inverter Offline")
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                            color: root.hasFault ? Theme.error : (root.isOnline ? Theme.surfaceText : Theme.surfaceVariantText)
                        }
                        StyledText {
                            text: {
                                if (!root.isOnline) return "Telemetry Unreachable / Service Inactive";
                                return root.faultSummary + (root.lastUpdated ? ` • ${root.lastUpdated}` : "");
                            }
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Button to open GoodWe SEMS Portal in browser
                    DButton {
                        Layout.alignment: Qt.AlignVCenter
                        text: "SEMS Portal"
                        iconName: "open_in_new"
                        buttonHeight: Theme.iconSizeSmall + Theme.spacingS
                        horizontalPadding: Theme.spacingM
                        backgroundColor: Theme.chipSurface
                        textColor: Theme.primary
                        onClicked: Qt.openUrlExternally(root.semsPortalUrl)
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
                        height: Theme.iconSizeLarge * 2
                        radius: Theme.cornerRadius
                        color: Theme.chipSurface

                        Row {
                            anchors.centerIn: parent
                            spacing: Theme.spacingS
                            DIcon {
                                name: "solar_power"
                                color: Theme.warning
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
                        height: Theme.iconSizeLarge * 2
                        radius: Theme.cornerRadius
                        color: Theme.chipSurface

                        Row {
                            anchors.centerIn: parent
                            spacing: Theme.spacingS
                            DIcon {
                                name: root.getBatteryIcon(root.batterySoc, root.batteryChargeW > 0)
                                color: root.batteryChargeW > 0 ? Theme.success : (root.batteryDischargeW > 0 ? Theme.info : Theme.surfaceVariantText)
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
                        height: Theme.iconSizeLarge * 2
                        radius: Theme.cornerRadius
                        color: Theme.chipSurface

                        Row {
                            anchors.centerIn: parent
                            spacing: Theme.spacingS
                            DIcon {
                                name: "home"
                                color: Theme.secondary
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
                        height: Theme.iconSizeLarge * 2
                        radius: Theme.cornerRadius
                        color: Theme.chipSurface

                        Row {
                            anchors.centerIn: parent
                            spacing: Theme.spacingS
                            DIcon {
                                name: "electric_bolt"
                                color: root.gridPowerW > 0 ? Theme.success : (root.gridPowerW < 0 ? Theme.error : Theme.surfaceVariantText)
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
                                    color: root.gridPowerW > 0 ? Theme.success : (root.gridPowerW < 0 ? Theme.error : Theme.surfaceText)
                                }
                            }
                        }
                    }
                }

                // Daily Energy Statistics Row
                Rectangle {
                    width: parent.width
                    height: Theme.iconSizeLarge + Theme.spacingXL
                    radius: Theme.cornerRadius
                    color: Theme.chipSurface

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
                                color: Theme.success
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
                        font.pixelSize: Theme.fontSizeXSmall
                        color: Theme.surfaceVariantText
                    }
                    StyledText {
                        text: `• Inverter Temp: ${root.tempInverter}°C`
                        font.pixelSize: Theme.fontSizeXSmall
                        color: Theme.surfaceVariantText
                    }
                    StyledText {
                        text: `• Bat Temp: ${root.batteryTemp}°C`
                        font.pixelSize: Theme.fontSizeXSmall
                        color: Theme.surfaceVariantText
                    }
                }
            }
        }
    }

}
