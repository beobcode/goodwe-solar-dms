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

    // 4. Centered Dash / Popout Dialog
    // Sized generously with real-time curves & daily bar chart derived from Theme tokens
    popoutWidth: Theme.iconSizeLarge * 22 + Theme.spacingL
    popoutHeight: Theme.iconSizeLarge * 16 + Theme.spacingL

    popoutContent: Component {
        PopoutComponent {
            id: popoutComp
            headerText: root.isOnline ? "GoodWe Solar & Battery System" : "GoodWe Solar System (Offline)"
            detailsText: root.isOnline ? `${root.faultSummary} • Updated ${root.lastUpdated}` : "Inverter unreachable / Poller service inactive"
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // Top Info & Portal Link Bar
                RowLayout {
                    width: parent.width

                    Row {
                        spacing: Theme.spacingS
                        Layout.alignment: Qt.AlignVCenter
                        StyledText {
                            text: `Inverter: ${root.inverterModel} (${root.inverterSerial || "Online"})`
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Button to open GoodWe SEMS Portal website in browser
                    DButton {
                        Layout.alignment: Qt.AlignVCenter
                        text: "Open SEMS Portal"
                        iconName: "open_in_new"
                        buttonHeight: Theme.iconSizeSmall + Theme.spacingS
                        horizontalPadding: Theme.spacingM
                        backgroundColor: Theme.chipSurface
                        textColor: Theme.primary
                        onClicked: Qt.openUrlExternally(root.semsPortalUrl)
                    }
                }

                // Top 4 Flow Tiles
                Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    // Solar Tile
                    Rectangle {
                        width: (parent.width - Theme.spacingS * 3) / 4
                        height: Theme.iconSizeLarge * 2 + Theme.spacingS
                        radius: Theme.cornerRadius
                        color: Theme.chipSurface

                        Column {
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS / 2
                            Row {
                                spacing: Theme.spacingXS
                                anchors.horizontalCenter: parent.horizontalCenter
                                DIcon {
                                    name: "solar_power"
                                    color: Theme.warning
                                    size: Theme.iconSizeSmall
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
                                color: Theme.warning
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            StyledText {
                                text: `Day: ${root.eDayPvKwh} kWh`
                                font.pixelSize: Theme.fontSizeXSmall
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }

                    // Battery Tile
                    Rectangle {
                        width: (parent.width - Theme.spacingS * 3) / 4
                        height: Theme.iconSizeLarge * 2 + Theme.spacingS
                        radius: Theme.cornerRadius
                        color: Theme.chipSurface

                        Column {
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS / 2
                            Row {
                                spacing: Theme.spacingXS
                                anchors.horizontalCenter: parent.horizontalCenter
                                DIcon {
                                    name: root.getBatteryIcon(root.batterySoc, root.batteryChargeW > 0)
                                    color: root.batteryChargeW > 0 ? Theme.success : (root.batteryDischargeW > 0 ? Theme.info : Theme.surfaceVariantText)
                                    size: Theme.iconSizeSmall
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
                                color: root.batteryChargeW > 0 ? Theme.success : (root.batteryDischargeW > 0 ? Theme.info : Theme.surfaceText)
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            StyledText {
                                text: root.batteryMode
                                font.pixelSize: Theme.fontSizeXSmall
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }

                    // Home Load Tile
                    Rectangle {
                        width: (parent.width - Theme.spacingS * 3) / 4
                        height: Theme.iconSizeLarge * 2 + Theme.spacingS
                        radius: Theme.cornerRadius
                        color: Theme.chipSurface

                        Column {
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS / 2
                            Row {
                                spacing: Theme.spacingXS
                                anchors.horizontalCenter: parent.horizontalCenter
                                DIcon {
                                    name: "home"
                                    color: Theme.secondary
                                    size: Theme.iconSizeSmall
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
                                color: Theme.secondary
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            StyledText {
                                text: `Day: ${root.eDayLoadKwh} kWh`
                                font.pixelSize: Theme.fontSizeXSmall
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }

                    // Grid Flow Tile
                    Rectangle {
                        width: (parent.width - Theme.spacingS * 3) / 4
                        height: Theme.iconSizeLarge * 2 + Theme.spacingS
                        radius: Theme.cornerRadius
                        color: Theme.chipSurface

                        Column {
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS / 2
                            Row {
                                spacing: Theme.spacingXS
                                anchors.horizontalCenter: parent.horizontalCenter
                                DIcon {
                                    name: "electric_bolt"
                                    color: root.gridPowerW > 0 ? Theme.success : (root.gridPowerW < 0 ? Theme.error : Theme.surfaceVariantText)
                                    size: Theme.iconSizeSmall
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
                                color: root.gridPowerW > 0 ? Theme.success : (root.gridPowerW < 0 ? Theme.error : Theme.surfaceText)
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            StyledText {
                                text: `Export: ${root.eDayExpKwh} kWh`
                                font.pixelSize: Theme.fontSizeXSmall
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }
                }

                // Intra-day Solar Generation Graph
                Rectangle {
                    width: parent.width
                    height: Theme.iconSizeLarge * 6
                    radius: Theme.cornerRadius
                    color: Theme.chipSurface

                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        spacing: Theme.spacingXS

                        RowLayout {
                            width: parent.width
                            StyledText {
                                text: "Solar, Load, Grid & Battery %"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                                Layout.alignment: Qt.AlignVCenter
                            }
                            Item { Layout.fillWidth: true }
                            Row {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: Theme.spacingS
                                Row {
                                    spacing: Theme.spacingXS / 2
                                    Rectangle { width: Theme.spacingS; height: Theme.spacingS; radius: Theme.spacingS / 2; color: Theme.warning; anchors.verticalCenter: parent.verticalCenter }
                                    StyledText { text: "PV (W)"; font.pixelSize: Theme.fontSizeXSmall; color: Theme.surfaceVariantText }
                                }
                                Row {
                                    spacing: Theme.spacingXS / 2
                                    Rectangle { width: Theme.spacingS; height: Theme.spacingS; radius: Theme.spacingS / 2; color: Theme.secondary; anchors.verticalCenter: parent.verticalCenter }
                                    StyledText { text: "Load (W)"; font.pixelSize: Theme.fontSizeXSmall; color: Theme.surfaceVariantText }
                                }
                                Row {
                                    spacing: Theme.spacingXS / 2
                                    Rectangle { width: Theme.spacingS; height: Theme.spacingS; radius: Theme.spacingS / 2; color: Theme.info; anchors.verticalCenter: parent.verticalCenter }
                                    StyledText { text: "Grid (+/-)"; font.pixelSize: Theme.fontSizeXSmall; color: Theme.surfaceVariantText }
                                }
                                Row {
                                    spacing: Theme.spacingXS / 2
                                    Rectangle { width: Theme.spacingS; height: Theme.spacingS; radius: Theme.spacingS / 2; color: Theme.success; anchors.verticalCenter: parent.verticalCenter }
                                    StyledText { text: "Bat (%)"; font.pixelSize: Theme.fontSizeXSmall; color: Theme.success }
                                }
                            }
                        }

                        // Canvas Graph Area
                        Canvas {
                            id: solarCanvas
                            width: parent.width
                            height: parent.height - Theme.iconSizeMedium - Theme.spacingS
                            renderStrategy: Canvas.Cooperative

                            property var pvData: root.historyPv
                            property var loadData: root.historyLoad
                            property var gridData: root.historyGrid
                            property var socData: root.historySoc
                            property var batData: root.historyBattery
                            property color themeWarning: Theme.warning
                            property color themeSecondary: Theme.secondary
                            property color themeInfo: Theme.info
                            property color themeSuccess: Theme.success
                            property color themeSurfaceText: Theme.surfaceText

                            onPvDataChanged: requestPaint()
                            onLoadDataChanged: requestPaint()
                            onGridDataChanged: requestPaint()
                            onSocDataChanged: requestPaint()
                            onBatDataChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            onThemeWarningChanged: requestPaint()
                            onThemeSecondaryChanged: requestPaint()
                            onThemeInfoChanged: requestPaint()
                            onThemeSuccessChanged: requestPaint()
                            onThemeSurfaceTextChanged: requestPaint()

                            Connections {
                                target: Theme
                                function onCurrentThemeChanged() {
                                    solarCanvas.requestPaint();
                                }
                            }

                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                ctx.clearRect(0, 0, width, height);

                                if (!pvData || pvData.length < 2) {
                                    ctx.fillStyle = Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.4);
                                    ctx.font = `${Theme.fontSizeSmall}px ${Theme.fontFamily || "sans-serif"}`;
                                    ctx.textAlign = "center";
                                    ctx.fillText("Gathering day data points...", width / 2, height / 2);
                                    return;
                                }

                                const n = pvData.length;
                                const padLeft = Theme.spacingXS;
                                const padRight = Theme.iconSizeLarge + Theme.spacingXS; // leave margin for battery SoC right Y-axis
                                const padTop = Theme.spacingS;
                                const padBottom = Theme.spacingL;
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
                                    ctx.strokeStyle = Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.25);
                                    ctx.lineWidth = Math.max(1, Theme.spacingXXS / 2);
                                    ctx.setLineDash([Theme.spacingXXS, Theme.spacingXS]);
                                    ctx.beginPath();
                                    ctx.moveTo(padLeft, yZero);
                                    ctx.lineTo(padLeft + chartW, yZero);
                                    ctx.stroke();
                                    ctx.setLineDash([]);

                                    ctx.fillStyle = Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.5);
                                    ctx.font = `${Theme.fontSizeXSmall}px ${Theme.fontFamily || "sans-serif"}`;
                                    ctx.textAlign = "left";
                                    ctx.fillText("0 W", padLeft + Theme.spacingXXS, yZero - Theme.spacingXXS);
                                }

                                // 1. Draw Solar PV Area Gradient & Line
                                const gradPv = ctx.createLinearGradient(0, padTop, 0, padTop + chartH);
                                gradPv.addColorStop(0, Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.35));
                                gradPv.addColorStop(1, Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.02));

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

                                ctx.strokeStyle = Theme.warning;
                                ctx.lineWidth = Theme.spacingXXS;
                                ctx.beginPath();
                                for (let i = 0; i < n; i++) {
                                    const px = padLeft + (i * stepX);
                                    const py = getY(pvData[i] || 0);
                                    i === 0 ? ctx.moveTo(px, py) : ctx.lineTo(px, py);
                                }
                                ctx.stroke();

                                // 2. Draw House Load Line
                                if (loadData && loadData.length === n) {
                                    ctx.strokeStyle = Theme.secondary;
                                    ctx.lineWidth = Theme.spacingXXS;
                                    ctx.setLineDash([Theme.spacingXXS, Theme.spacingXXS]);
                                    ctx.beginPath();
                                    for (let j = 0; j < n; j++) {
                                        const px = padLeft + (j * stepX);
                                        const py = getY(loadData[j] || 0);
                                        j === 0 ? ctx.moveTo(px, py) : ctx.lineTo(px, py);
                                    }
                                    ctx.stroke();
                                    ctx.setLineDash([]);
                                }

                                // 3. Draw Grid Power Line
                                if (gridData && gridData.length === n) {
                                    ctx.strokeStyle = Theme.info;
                                    ctx.lineWidth = Theme.spacingXXS;
                                    ctx.beginPath();
                                    for (let k = 0; k < n; k++) {
                                        const px = padLeft + (k * stepX);
                                        const py = getY(gridData[k] || 0);
                                        k === 0 ? ctx.moveTo(px, py) : ctx.lineTo(px, py);
                                    }
                                    ctx.stroke();
                                }

                                // 4. Draw Battery SoC % Line & Right Y-Axis
                                if (socData && socData.length === n) {
                                    function getSocY(soc) {
                                        const clamped = Math.max(0, Math.min(100, soc));
                                        return padTop + chartH - ((clamped / 100.0) * chartH);
                                    }

                                    // Right Y-axis labels: 100%, 50%, 0%
                                    ctx.fillStyle = Qt.rgba(Theme.success.r, Theme.success.g, Theme.success.b, 0.85);
                                    ctx.font = `${Theme.fontSizeXSmall}px ${Theme.fontFamily || "sans-serif"}`;
                                    ctx.textAlign = "left";
                                    ctx.fillText("100%", padLeft + chartW + Theme.spacingXS, padTop + Theme.spacingS);
                                    ctx.fillText("50%", padLeft + chartW + Theme.spacingXS, padTop + (chartH / 2) + Theme.spacingXXS);
                                    ctx.fillText("0%", padLeft + chartW + Theme.spacingXS, padTop + chartH);

                                    // SoC curve
                                    ctx.strokeStyle = Theme.success;
                                    ctx.lineWidth = Theme.spacingXXS;
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
                    height: Theme.iconSizeLarge * 4
                    radius: Theme.cornerRadius
                    color: Theme.chipSurface

                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        spacing: Theme.spacingXS

                        RowLayout {
                            width: parent.width
                            StyledText {
                                text: "Daily Total Generation (kWh)"
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                                Layout.alignment: Qt.AlignVCenter
                            }
                            Item { Layout.fillWidth: true }
                            StyledText {
                                text: `Total PV: ${root.eTotalPvKwh} kWh`
                                font.pixelSize: Theme.fontSizeXSmall
                                color: Theme.surfaceVariantText
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }

                        // Bar representations
                        Row {
                            width: parent.width
                            height: parent.height - Theme.iconSizeSmall - Theme.spacingS
                            spacing: Theme.spacingS

                            Repeater {
                                model: root.recentDays.length > 0 ? root.recentDays : [{ day_name: "Today", pv_kwh: root.eDayPvKwh, exp_kwh: root.eDayExpKwh }]

                                Rectangle {
                                    width: (parent.width - (Theme.spacingS * 6)) / Math.max(1, (root.recentDays.length || 1))
                                    height: parent.height
                                    color: "transparent"

                                    Column {
                                        anchors.fill: parent
                                        spacing: Theme.spacingXS / 2

                                        StyledText {
                                            text: `${modelData.pv_kwh}k`
                                            font.pixelSize: Theme.fontSizeXSmall
                                            font.weight: Font.Bold
                                            color: Theme.warning
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }

                                        Item {
                                            width: parent.width
                                            height: parent.height - Theme.iconSizeMedium - Theme.spacingS

                                            Rectangle {
                                                width: Math.min(Theme.iconSize, parent.width * 0.7)
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.bottom: parent.bottom
                                                // Max day scale ~35 kWh
                                                height: Math.max(Theme.spacingXS, Math.min(parent.height, (modelData.pv_kwh / 35.0) * parent.height))
                                                radius: Theme.cornerRadius / 3
                                                color: Theme.warning
                                            }
                                        }

                                        StyledText {
                                            text: modelData.day_name || "Day"
                                            font.pixelSize: Theme.fontSizeXSmall
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
