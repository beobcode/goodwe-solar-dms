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

    minWidth: 200
    minHeight: 220

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

    property var historyPv: []
    property var historyLoad: []
    property string semsPortalUrl: pluginData.portalUrl || "https://au-semsplus.goodwe.com/"

    readonly property string cacheFilePath: {
        const xdg = Quickshell.env("XDG_CACHE_HOME");
        const home = Quickshell.env("HOME") || "";
        const base = (xdg && xdg.length > 0) ? xdg : (home + "/.cache");
        return base + "/goodwe_solar.json";
    }

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
            root.isOnline = (data.online ?? true) && ((nowSec - ts) < 30);
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

            root.historyPv = data.history_pv ?? [];
            root.historyLoad = data.history_load ?? [];
        } catch (e) {
            root.isOnline = false;
        }
    }

    FileView {
        id: cacheFileView
        path: root.cacheFilePath
        watchChanges: true
        onLoaded: root.parseTelemetry()
        onFileChanged: cacheFileView.reload()
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
            spacing: Theme.spacingXS

            // Top Header: Title & Today's Yield Badge
            RowLayout {
                Layout.fillWidth: true

                Row {
                    spacing: Theme.spacingXS
                    DankIcon {
                        name: root.hasFault ? "error" : "solar_power"
                        size: Theme.iconSize - 2
                        color: root.hasFault ? Theme.error : (root.isOnline ? Theme.warning : Theme.surfaceVariantText)
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

                Rectangle {
                    visible: root.isOnline
                    height: 22
                    width: yieldRow.implicitWidth + Theme.spacingS * 2
                    radius: Theme.cornerRadius / 2
                    color: Theme.surfaceContainerHighest

                    Row {
                        id: yieldRow
                        anchors.centerIn: parent
                        spacing: 3
                        DankIcon {
                            name: "wb_sunny"
                            size: 14
                            color: Theme.warning
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        StyledText {
                            text: `${root.eDayPvKwh} kWh`
                            font.pixelSize: Theme.fontSizeSmall - 2
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                // External Link to GoodWe SEMS Portal
                Rectangle {
                    height: 22
                    width: 22
                    radius: Theme.cornerRadius / 2
                    color: desktopPortalMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                    DankIcon {
                        name: "open_in_new"
                        size: 14
                        color: desktopPortalMouse.containsMouse ? Theme.primary : Theme.surfaceVariantText
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        id: desktopPortalMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Qt.openUrlExternally(root.semsPortalUrl)
                    }
                }
            }

            // Main Solar Generation Display
            RowLayout {
                Layout.fillWidth: true

                Column {
                    spacing: 0
                    StyledText {
                        text: root.isOnline ? root.formatWatts(root.pvPowerW) : "Offline"
                        font.pixelSize: Theme.fontSizeLarge + 6
                        font.weight: Font.Bold
                        color: root.pvPowerW > 500 ? Theme.warning : Theme.surfaceText
                    }

                    StyledText {
                        text: root.hasFault ? root.faultSummary : (root.isOnline ? (root.pvPowerW > 0 ? "Generating Power" : "Standby") : "Inverter Unreachable")
                        font.pixelSize: Theme.fontSizeSmall - 2
                        color: root.hasFault ? Theme.error : Theme.surfaceVariantText
                    }
                }

                Item { Layout.fillWidth: true }

                // Battery Badge
                Row {
                    spacing: Theme.spacingXS
                    DankIcon {
                        name: root.getBatteryIcon(root.batterySoc, root.batteryChargeW > 0)
                        size: Theme.iconSize - 4
                        color: root.batteryChargeW > 0 ? Theme.success : (root.batteryDischargeW > 0 ? Theme.info : Theme.surfaceVariantText)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    StyledText {
                        text: `${root.batterySoc}%`
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // Mini Generation Curve
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 48

                Canvas {
                    id: miniCanvas
                    anchors.fill: parent
                    renderStrategy: Canvas.Cooperative

                    property var pvData: root.historyPv
                    property var loadData: root.historyLoad

                    onPvDataChanged: requestPaint()
                    onLoadDataChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        ctx.clearRect(0, 0, width, height);

                        if (!pvData || pvData.length < 2) {
                            ctx.fillStyle = Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.35);
                            ctx.font = `${Theme.fontSizeSmall - 1}px ${Theme.fontFamily || "sans-serif"}`;
                            ctx.textAlign = "center";
                            ctx.fillText("Tracking daily curve...", width / 2, height / 2);
                            return;
                        }

                        let maxVal = 1000;
                        for (let i = 0; i < pvData.length; i++) maxVal = Math.max(maxVal, pvData[i]);
                        maxVal *= 1.15;

                        const n = pvData.length;
                        const stepX = width / Math.max(1, n - 1);

                        // Gradient fill
                        const grad = ctx.createLinearGradient(0, 0, 0, height);
                        grad.addColorStop(0, Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.35));
                        grad.addColorStop(1, Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.02));

                        ctx.fillStyle = grad;
                        ctx.beginPath();
                        ctx.moveTo(0, height);
                        for (let i = 0; i < n; i++) {
                            const px = i * stepX;
                            const py = height - (pvData[i] / maxVal) * (height - 4);
                            ctx.lineTo(px, py);
                        }
                        ctx.lineTo(width, height);
                        ctx.closePath();
                        ctx.fill();

                        // Solar Line
                        ctx.strokeStyle = Theme.warning;
                        ctx.lineWidth = 2.0;
                        ctx.beginPath();
                        for (let i = 0; i < n; i++) {
                            const px = i * stepX;
                            const py = height - (pvData[i] / maxVal) * (height - 4);
                            i === 0 ? ctx.moveTo(px, py) : ctx.lineTo(px, py);
                        }
                        ctx.stroke();
                    }
                }
            }

            // Power Flows Grid
            GridLayout {
                Layout.fillWidth: true
                columns: 3
                rowSpacing: 2
                columnSpacing: Theme.spacingS

                // 1. Battery Flow
                Column {
                    Layout.fillWidth: true
                    spacing: 1
                    StyledText {
                        text: "Battery"
                        font.pixelSize: Theme.fontSizeSmall - 2
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    StyledText {
                        text: root.batteryChargeW > 0 ? `+${root.formatWatts(root.batteryChargeW)}` : (root.batteryDischargeW > 0 ? `-${root.formatWatts(root.batteryDischargeW)}` : "Idle")
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Bold
                        color: root.batteryChargeW > 0 ? Theme.success : (root.batteryDischargeW > 0 ? Theme.info : Theme.surfaceText)
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                // 2. House Load
                Column {
                    Layout.fillWidth: true
                    spacing: 1
                    StyledText {
                        text: "Home Load"
                        font.pixelSize: Theme.fontSizeSmall - 2
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    StyledText {
                        text: root.formatWatts(root.houseConsumptionW)
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Bold
                        color: Theme.secondary
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                // 3. Grid Export/Import
                Column {
                    Layout.fillWidth: true
                    spacing: 1
                    StyledText {
                        text: root.gridPowerW > 0 ? "Grid (Export)" : (root.gridPowerW < 0 ? "Grid (Import)" : "Grid Flow")
                        font.pixelSize: Theme.fontSizeSmall - 2
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    StyledText {
                        text: root.gridPowerW > 0 ? `+${root.formatWatts(root.gridPowerW)}` : (root.gridPowerW < 0 ? `-${root.formatWatts(root.gridPowerW)}` : "0 W")
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Bold
                        color: root.gridPowerW > 0 ? Theme.success : (root.gridPowerW < 0 ? Theme.error : Theme.surfaceText)
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }
}
