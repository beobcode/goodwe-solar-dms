pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Modules.DDash

DashTabComponent {
    id: root

    // Telemetry state
    property bool isOnline: false
    property string lastUpdated: ""
    property string inverterModel: "GoodWe Hybrid"
    property string inverterSerial: ""
    property string workMode: "Normal"

    property int pvPowerW: 0
    property int pv1PowerW: 0
    property int pv2PowerW: 0
    property int batteryPowerW: 0
    property int batteryChargeW: 0
    property int batteryDischargeW: 0
    property int batterySoc: 0
    property int batterySoh: 100
    property string batteryMode: "Idle"
    property real batteryVoltage: 0.0
    property real batteryCurrent: 0.0
    property real batteryTemp: 0.0

    property int houseConsumptionW: 0
    property int gridPowerW: 0
    property int gridExportW: 0
    property int gridImportW: 0
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

    // Historical intra-day curves & recent day history
    property var historyPv: []
    property var historyLoad: []
    property var historyGrid: []
    property var historySoc: []
    property var historyBattery: []
    property var recentDays: []

    property string semsPortalUrl: pluginData.portalUrl || "https://au-semsplus.goodwe.com/"
    property int lastTelemetryTimestamp: 0

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

    // Top action menu inside DankDash panel
    menuActions: [
        {
            label: I18n.tr("Open SEMS Portal"),
            iconName: "open_in_new",
            action: () => Qt.openUrlExternally(root.semsPortalUrl)
        },
        {
            label: I18n.tr("Settings"),
            iconName: "settings",
            action: () => {
                PopoutService.closeDankDash();
                PopoutService.openSettingsWithTab("plugins");
            }
        }
    ]

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
            root.isOnline = (data.online ?? true) && ((nowSec - ts) < 30);
            root.lastUpdated = data.last_updated ?? "";
            root.inverterModel = data.model && data.model.length > 0 && data.model !== "Unknown" && !data.model.startsWith("\u4757") ? data.model : "GoodWe Hybrid";
            root.inverterSerial = data.serial ?? "";
            root.workMode = data.work_mode ?? "Normal";

            root.pvPowerW = data.pv_power_w ?? 0;
            root.pv1PowerW = data.pv1_power_w ?? 0;
            root.pv2PowerW = data.pv2_power_w ?? 0;
            root.batteryPowerW = data.battery_power_w ?? 0;
            root.batteryChargeW = data.battery_charge_w ?? 0;
            root.batteryDischargeW = data.battery_discharge_w ?? 0;
            root.batterySoc = data.battery_soc ?? 0;
            root.batterySoh = data.battery_soh ?? 100;
            root.batteryMode = data.battery_mode ?? "Idle";
            root.batteryVoltage = data.battery_voltage ?? 0.0;
            root.batteryCurrent = data.battery_current ?? 0.0;
            root.batteryTemp = data.battery_temp ?? 0.0;

            root.houseConsumptionW = data.house_consumption_w ?? 0;
            root.gridPowerW = data.grid_power_w ?? 0;
            root.gridExportW = data.grid_export_w ?? 0;
            root.gridImportW = data.grid_import_w ?? 0;
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

    function checkStaleness() {
        if (!root.isOnline && root.lastTelemetryTimestamp === 0) return;
        const nowSec = Math.floor(Date.now() / 1000);
        if (root.lastTelemetryTimestamp > 0 && (nowSec - root.lastTelemetryTimestamp) >= 30) {
            root.isOnline = false;
        }
    }

    onLiveChanged: {
        if (live) {
            cacheFileView.reload();
            historyFileView.reload();
            root.checkStaleness();
        }
    }

    Timer {
        id: stalenessTimer
        interval: 15000
        repeat: true
        running: root.live
        onTriggered: root.checkStaleness()
    }

    FileView {
        id: cacheFileView
        path: root.cacheFilePath
        watchChanges: root.live
        onLoaded: root.parseTelemetry()
        onFileChanged: if (root.live) cacheFileView.reload()
    }

    FileView {
        id: historyFileView
        path: root.historyFilePath
        watchChanges: root.live
        onLoaded: root.parseHistory()
        onFileChanged: if (root.live) historyFileView.reload()
    }

    Flickable {
        id: flickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentCol.implicitHeight + Theme.spacingXL
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: contentCol
            width: parent.width
            spacing: Theme.spacingM

            // 1. Header Hero Card
            Rectangle {
                width: parent.width
                height: Theme.iconSizeLarge * 2 + Theme.spacingM
                radius: Theme.cornerRadiusXL
                color: Theme.cardSurface
                border.width: Theme.layerOutlineWidth
                border.color: Theme.outlineMedium

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingL
                    anchors.rightMargin: Theme.spacingL
                    spacing: Theme.spacingM

                    // Status Indicator Icon
                    Rectangle {
                        width: Theme.iconSizeLarge + Theme.spacingM
                        height: Theme.iconSizeLarge + Theme.spacingM
                        radius: (Theme.iconSizeLarge + Theme.spacingM) / 2
                        color: root.hasFault ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.15) : (root.isOnline ? Qt.rgba(Theme.success.r, Theme.success.g, Theme.success.b, 0.15) : Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.08))
                        Layout.alignment: Qt.AlignVCenter

                        DIcon {
                            anchors.centerIn: parent
                            name: root.hasFault ? "error" : (root.isOnline ? "solar_power" : "cloud_off")
                            size: Theme.iconSizeLarge
                            color: root.hasFault ? Theme.error : (root.isOnline ? Theme.warning : Theme.surfaceVariantText)
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Theme.spacingXXS

                        RowLayout {
                            spacing: Theme.spacingS
                            StyledText {
                                text: root.hasFault ? "GoodWe Fault Active" : (root.isOnline ? "GoodWe Solar & Battery System" : "GoodWe Solar (Offline)")
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                                color: root.hasFault ? Theme.error : Theme.surfaceText
                            }

                            Rectangle {
                                height: Theme.iconSizeSmall + Theme.spacingXXS
                                width: statusText.implicitWidth + Theme.spacingS * 2
                                radius: height / 2
                                color: root.isOnline ? Qt.rgba(Theme.success.r, Theme.success.g, Theme.success.b, 0.15) : Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.1)
                                Layout.alignment: Qt.AlignVCenter

                                StyledText {
                                    id: statusText
                                    anchors.centerIn: parent
                                    text: root.isOnline ? "ONLINE" : "OFFLINE"
                                    font.pixelSize: Theme.fontSizeXSmall
                                    font.weight: Font.Bold
                                    color: root.isOnline ? Theme.success : Theme.surfaceVariantText
                                }
                            }
                        }

                        StyledText {
                            text: {
                                if (!root.isOnline) return "Telemetry unreachable • poller daemon inactive";
                                const parts = [];
                                if (root.inverterModel) parts.push(root.inverterModel);
                                if (root.inverterSerial) parts.push(`S/N: ${root.inverterSerial}`);
                                if (root.lastUpdated) parts.push(`Updated ${root.lastUpdated}`);
                                return parts.join(" • ");
                            }
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    // Button to open SEMS Portal
                    DButton {
                        Layout.alignment: Qt.AlignVCenter
                        text: "SEMS Portal"
                        iconName: "open_in_new"
                        backgroundColor: Theme.chipSurface
                        textColor: Theme.primary
                        onClicked: Qt.openUrlExternally(root.semsPortalUrl)
                    }
                }
            }

            // 2. Real-Time 4-Tile Power Grid
            Row {
                width: parent.width
                spacing: Theme.spacingM

                // Solar Tile
                Rectangle {
                    width: (parent.width - (Theme.spacingM * 3)) / 4
                    height: Theme.iconSizeLarge * 3
                    radius: Theme.cornerRadiusXL
                    color: Theme.cardSurface
                    border.width: Theme.layerOutlineWidth
                    border.color: Theme.outlineMedium

                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingXS

                        RowLayout {
                            width: parent.width
                            Row {
                                spacing: Theme.spacingXS
                                DIcon {
                                    name: "solar_power"
                                    color: Theme.warning
                                    size: Theme.iconSizeMedium
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: "Solar PV"
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.DemiBold
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            Item { Layout.fillWidth: true }
                            StyledText {
                                text: `${root.eDayPvKwh} kWh`
                                font.pixelSize: Theme.fontSizeXSmall
                                color: Theme.warning
                                font.weight: Font.Bold
                            }
                        }

                        Item { Layout.fillHeight: true; height: Theme.spacingXS }

                        StyledText {
                            text: root.formatWatts(root.pvPowerW)
                            font.pixelSize: Theme.fontSizeXLarge * 1.1
                            font.weight: Font.Bold
                            color: root.pvPowerW > 500 ? Theme.warning : Theme.surfaceText
                        }

                        StyledText {
                            text: {
                                if (root.pv1PowerW > 0 || root.pv2PowerW > 0) {
                                    return `PV1: ${root.pv1PowerW}W • PV2: ${root.pv2PowerW}W`;
                                }
                                return root.isOnline ? "Generating clean solar energy" : "Offline";
                            }
                            font.pixelSize: Theme.fontSizeXSmall
                            color: Theme.surfaceVariantText
                        }
                    }
                }

                // Battery Tile
                Rectangle {
                    width: (parent.width - (Theme.spacingM * 3)) / 4
                    height: Theme.iconSizeLarge * 3
                    radius: Theme.cornerRadiusXL
                    color: Theme.cardSurface
                    border.width: Theme.layerOutlineWidth
                    border.color: Theme.outlineMedium

                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingXS

                        RowLayout {
                            width: parent.width
                            Row {
                                spacing: Theme.spacingXS
                                DIcon {
                                    name: root.getBatteryIcon(root.batterySoc, root.batteryChargeW > 0)
                                    color: root.batteryChargeW > 0 ? Theme.success : (root.batteryDischargeW > 0 ? Theme.info : Theme.surfaceVariantText)
                                    size: Theme.iconSizeMedium
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: `Battery (${root.batterySoc}%)`
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.DemiBold
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            Item { Layout.fillWidth: true }
                            StyledText {
                                text: `${root.batteryTemp}°C`
                                font.pixelSize: Theme.fontSizeXSmall
                                color: Theme.surfaceVariantText
                            }
                        }

                        Item { Layout.fillHeight: true; height: Theme.spacingXS }

                        StyledText {
                            text: root.batteryChargeW > 0 ? `+${root.formatWatts(root.batteryChargeW)}` : (root.batteryDischargeW > 0 ? `-${root.formatWatts(root.batteryDischargeW)}` : "Idle")
                            font.pixelSize: Theme.fontSizeXLarge * 1.1
                            font.weight: Font.Bold
                            color: root.batteryChargeW > 0 ? Theme.success : (root.batteryDischargeW > 0 ? Theme.info : Theme.surfaceText)
                        }

                        StyledText {
                            text: `Mode: ${root.batteryMode} • SoH: ${root.batterySoh}%`
                            font.pixelSize: Theme.fontSizeXSmall
                            color: Theme.surfaceVariantText
                        }
                    }
                }

                // Home Load Tile
                Rectangle {
                    width: (parent.width - (Theme.spacingM * 3)) / 4
                    height: Theme.iconSizeLarge * 3
                    radius: Theme.cornerRadiusXL
                    color: Theme.cardSurface
                    border.width: Theme.layerOutlineWidth
                    border.color: Theme.outlineMedium

                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingXS

                        RowLayout {
                            width: parent.width
                            Row {
                                spacing: Theme.spacingXS
                                DIcon {
                                    name: "home"
                                    color: Theme.secondary
                                    size: Theme.iconSizeMedium
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: "Home Load"
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.DemiBold
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            Item { Layout.fillWidth: true }
                            StyledText {
                                text: `${root.eDayLoadKwh} kWh`
                                font.pixelSize: Theme.fontSizeXSmall
                                color: Theme.secondary
                                font.weight: Font.Bold
                            }
                        }

                        Item { Layout.fillHeight: true; height: Theme.spacingXS }

                        StyledText {
                            text: root.formatWatts(root.houseConsumptionW)
                            font.pixelSize: Theme.fontSizeXLarge * 1.1
                            font.weight: Font.Bold
                            color: Theme.secondary
                        }

                        StyledText {
                            text: `Inverter: ${root.tempInverter}°C • Air: ${root.tempAir}°C`
                            font.pixelSize: Theme.fontSizeXSmall
                            color: Theme.surfaceVariantText
                        }
                    }
                }

                // Grid Connection Tile
                Rectangle {
                    width: (parent.width - (Theme.spacingM * 3)) / 4
                    height: Theme.iconSizeLarge * 3
                    radius: Theme.cornerRadiusXL
                    color: Theme.cardSurface
                    border.width: Theme.layerOutlineWidth
                    border.color: Theme.outlineMedium

                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingXS

                        RowLayout {
                            width: parent.width
                            Row {
                                spacing: Theme.spacingXS
                                DIcon {
                                    name: "electric_bolt"
                                    color: root.gridPowerW > 0 ? Theme.success : (root.gridPowerW < 0 ? Theme.error : Theme.surfaceVariantText)
                                    size: Theme.iconSizeMedium
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: root.gridPowerW > 0 ? "Grid (Export)" : (root.gridPowerW < 0 ? "Grid (Import)" : "Grid Flow")
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.DemiBold
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            Item { Layout.fillWidth: true }
                            StyledText {
                                text: `Exp: ${root.eDayExpKwh}k`
                                font.pixelSize: Theme.fontSizeXSmall
                                color: Theme.success
                                font.weight: Font.Bold
                            }
                        }

                        Item { Layout.fillHeight: true; height: Theme.spacingXS }

                        StyledText {
                            text: root.gridPowerW > 0 ? `+${root.formatWatts(root.gridPowerW)}` : (root.gridPowerW < 0 ? `-${root.formatWatts(root.gridPowerW)}` : "0 W")
                            font.pixelSize: Theme.fontSizeXLarge * 1.1
                            font.weight: Font.Bold
                            color: root.gridPowerW > 0 ? Theme.success : (root.gridPowerW < 0 ? Theme.error : Theme.surfaceText)
                        }

                        StyledText {
                            text: `${root.gridVoltage.toFixed(1)}V • ${root.gridFrequency.toFixed(1)}Hz`
                            font.pixelSize: Theme.fontSizeXSmall
                            color: Theme.surfaceVariantText
                        }
                    }
                }
            }

            // 3. Intra-day Power & SoC Chart
            Rectangle {
                width: parent.width
                height: Theme.iconSizeLarge * 9
                radius: Theme.cornerRadiusXL
                color: Theme.cardSurface
                border.width: Theme.layerOutlineWidth
                border.color: Theme.outlineMedium

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingL
                    spacing: Theme.spacingS

                    RowLayout {
                        width: parent.width
                        Column {
                            StyledText {
                                text: "Intra-Day Generation, Load & Battery Curve"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                            }
                            StyledText {
                                text: "Continuous telemetry sampled throughout the day"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Row {
                            spacing: Theme.spacingM
                            Layout.alignment: Qt.AlignVCenter

                            Row {
                                spacing: Theme.spacingXS
                                Rectangle { width: Theme.spacingS; height: Theme.spacingS; radius: Theme.spacingS / 2; color: Theme.warning; anchors.verticalCenter: parent.verticalCenter }
                                StyledText { text: "PV (W)"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText }
                            }
                            Row {
                                spacing: Theme.spacingXS
                                Rectangle { width: Theme.spacingS; height: Theme.spacingS; radius: Theme.spacingS / 2; color: Theme.secondary; anchors.verticalCenter: parent.verticalCenter }
                                StyledText { text: "Load (W)"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText }
                            }
                            Row {
                                spacing: Theme.spacingXS
                                Rectangle { width: Theme.spacingS; height: Theme.spacingS; radius: Theme.spacingS / 2; color: Theme.info; anchors.verticalCenter: parent.verticalCenter }
                                StyledText { text: "Grid (W)"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText }
                            }
                            Row {
                                spacing: Theme.spacingXS
                                Rectangle { width: Theme.spacingS; height: Theme.spacingS; radius: Theme.spacingS / 2; color: Theme.success; anchors.verticalCenter: parent.verticalCenter }
                                StyledText { text: "Bat (%)"; font.pixelSize: Theme.fontSizeSmall; color: Theme.success; font.weight: Font.Bold }
                            }
                        }
                    }

                    Canvas {
                        id: panelCanvas
                        width: parent.width
                        height: parent.height - Theme.iconSizeMedium - Theme.spacingL
                        renderStrategy: Canvas.Cooperative

                        property var pvData: root.historyPv
                        property var loadData: root.historyLoad
                        property var gridData: root.historyGrid
                        property var socData: root.historySoc
                        property var batData: root.historyBattery

                        property color colWarning: Theme.warning
                        property color colSecondary: Theme.secondary
                        property color colInfo: Theme.info
                        property color colSuccess: Theme.success
                        property color colSurfaceText: Theme.surfaceText
                        property color colOutline: Theme.outline

                        onPvDataChanged: requestPaint()
                        onLoadDataChanged: requestPaint()
                        onGridDataChanged: requestPaint()
                        onSocDataChanged: requestPaint()
                        onBatDataChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        onColWarningChanged: requestPaint()
                        onColSecondaryChanged: requestPaint()
                        onColInfoChanged: requestPaint()
                        onColSuccessChanged: requestPaint()
                        onColSurfaceTextChanged: requestPaint()
                        onColOutlineChanged: requestPaint()

                        Connections {
                            target: Theme
                            function onCurrentThemeChanged() {
                                panelCanvas.requestPaint();
                            }
                        }

                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            ctx.clearRect(0, 0, width, height);

                            if (!pvData || pvData.length < 2) {
                                ctx.fillStyle = Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.4);
                                ctx.font = `${Theme.fontSizeMedium}px ${Theme.fontFamily || "sans-serif"}`;
                                ctx.textAlign = "center";
                                ctx.fillText("Collecting continuous intra-day telemetry points...", width / 2, height / 2);
                                return;
                            }

                            const n = pvData.length;
                            const padLeft = Theme.spacingM;
                            const padRight = Theme.iconSizeLarge + Theme.spacingM;
                            const padTop = Theme.spacingM;
                            const padBottom = Theme.spacingL;
                            const chartW = width - padLeft - padRight;
                            const chartH = height - padTop - padBottom;
                            const stepX = chartW / Math.max(1, n - 1);

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

                            // Zero line
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

                            // 1. Solar PV Area Gradient & Line
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
                            ctx.lineWidth = Theme.spacingXXS * 1.2;
                            ctx.beginPath();
                            for (let i = 0; i < n; i++) {
                                const px = padLeft + (i * stepX);
                                const py = getY(pvData[i] || 0);
                                i === 0 ? ctx.moveTo(px, py) : ctx.lineTo(px, py);
                            }
                            ctx.stroke();

                            // 2. House Load Line
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

                            // 3. Grid Line
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

                            // 4. Battery SoC Line & Labels
                            if (socData && socData.length === n) {
                                function getSocY(soc) {
                                    const clamped = Math.max(0, Math.min(100, soc));
                                    return padTop + chartH - ((clamped / 100.0) * chartH);
                                }

                                ctx.fillStyle = Qt.rgba(Theme.success.r, Theme.success.g, Theme.success.b, 0.9);
                                ctx.font = `${Theme.fontSizeXSmall}px ${Theme.fontFamily || "sans-serif"}`;
                                ctx.textAlign = "left";
                                ctx.fillText("100%", padLeft + chartW + Theme.spacingXS, padTop + Theme.spacingS);
                                ctx.fillText("50%", padLeft + chartW + Theme.spacingXS, padTop + (chartH / 2) + Theme.spacingXXS);
                                ctx.fillText("0%", padLeft + chartW + Theme.spacingXS, padTop + chartH);

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

            // 4. Daily Yield History (Bar Chart)
            Rectangle {
                width: parent.width
                height: Theme.iconSizeLarge * 5
                radius: Theme.cornerRadiusXL
                color: Theme.cardSurface
                border.width: Theme.layerOutlineWidth
                border.color: Theme.outlineMedium

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingL
                    spacing: Theme.spacingS

                    RowLayout {
                        width: parent.width
                        StyledText {
                            text: "Recent Daily Generation History"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                        }

                        Item { Layout.fillWidth: true }

                        StyledText {
                            text: `Lifetime Total: ${root.eTotalPvKwh} kWh`
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    Row {
                        width: parent.width
                        height: parent.height - Theme.iconSizeMedium - Theme.spacingL
                        spacing: Theme.spacingM

                        Repeater {
                            model: root.recentDays.length > 0 ? root.recentDays : [{ day_name: "Today", pv_kwh: root.eDayPvKwh, exp_kwh: root.eDayExpKwh }]

                            Rectangle {
                                required property var modelData
                                width: (parent.width - (Theme.spacingM * (root.recentDays.length ? root.recentDays.length - 1 : 1))) / Math.max(1, (root.recentDays.length || 1))
                                height: parent.height
                                color: "transparent"

                                Column {
                                    anchors.fill: parent
                                    spacing: Theme.spacingXS

                                    StyledText {
                                        text: `${modelData.pv_kwh} kWh`
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Bold
                                        color: Theme.warning
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }

                                    Item {
                                        width: parent.width
                                        height: parent.height - Theme.iconSizeMedium - Theme.spacingS

                                        Rectangle {
                                            width: Math.min(Theme.iconSizeLarge, parent.width * 0.5)
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.bottom: parent.bottom
                                            height: Math.max(Theme.spacingXS, Math.min(parent.height, (modelData.pv_kwh / 35.0) * parent.height))
                                            radius: Theme.cornerRadius / 2
                                            color: Theme.warning

                                            // Export portion overlay
                                            Rectangle {
                                                width: parent.width
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.bottom: parent.bottom
                                                height: Math.max(0, Math.min(parent.height, ((modelData.exp_kwh || 0) / Math.max(0.1, modelData.pv_kwh)) * parent.height))
                                                radius: Theme.cornerRadius / 2
                                                color: Theme.success
                                            }
                                        }
                                    }

                                    StyledText {
                                        text: modelData.day_name || modelData.date || "Day"
                                        font.pixelSize: Theme.fontSizeSmall
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
