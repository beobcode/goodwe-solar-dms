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

DashCardComponent {
    id: root

    clickable: true
    opensTab: false
    tone: options.tone ?? ""

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
    property int lastTelemetryTimestamp: 0

    readonly property bool isCompact: height < 140

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

            if (data.history_pv) root.historyPv = data.history_pv;
            if (data.history_load) root.historyLoad = data.history_load;
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

    onClicked: Qt.openUrlExternally(root.semsPortalUrl)

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

    // Compact Layout (single-row or narrow cards)
    ColumnLayout {
        anchors.fill: parent
        visible: root.isCompact
        spacing: Theme.spacingXS

        RowLayout {
            Layout.fillWidth: true

            Row {
                spacing: Theme.spacingXS
                DIcon {
                    name: root.hasFault ? "error" : "solar_power"
                    size: Theme.iconSizeSmall
                    color: root.hasFault ? Theme.error : (root.isOnline ? Theme.warning : root.mutedColor)
                    anchors.verticalCenter: parent.verticalCenter
                }
                StyledText {
                    text: "GoodWe Solar"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                    color: root.contentColor
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                visible: root.isOnline
                height: Theme.iconSizeSmall + Theme.spacingXXS
                width: compactYieldRow.implicitWidth + Theme.spacingS * 2
                radius: Theme.cornerRadius / 2
                color: root.chipColor

                Row {
                    id: compactYieldRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingXXS
                    DIcon {
                        name: "wb_sunny"
                        size: Theme.iconSizeSmall - Theme.spacingXXS
                        color: Theme.warning
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    StyledText {
                        text: `${root.eDayPvKwh} kWh`
                        font.pixelSize: Theme.fontSizeXSmall
                        font.weight: Font.Bold
                        color: root.contentColor
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            StyledText {
                text: root.isOnline ? root.formatWatts(root.pvPowerW) : "Offline"
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                color: root.pvPowerW > 500 ? Theme.warning : root.contentColor
            }

            Item { Layout.fillWidth: true }

            Row {
                spacing: Theme.spacingXXS
                DIcon {
                    name: root.getBatteryIcon(root.batterySoc, root.batteryChargeW > 0)
                    size: Theme.iconSizeSmall
                    color: root.batteryChargeW > 0 ? Theme.success : (root.batteryDischargeW > 0 ? Theme.info : root.mutedColor)
                    anchors.verticalCenter: parent.verticalCenter
                }
                StyledText {
                    text: `${root.batterySoc}%`
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                    color: root.contentColor
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // Standard Layout (2x2 or larger overview cards)
    ColumnLayout {
        anchors.fill: parent
        visible: !root.isCompact
        spacing: Theme.spacingXS

        // 1. Top Header: Title & Today's Yield Badge
        RowLayout {
            Layout.fillWidth: true

            Row {
                spacing: Theme.spacingXS
                DIcon {
                    name: root.hasFault ? "error" : "solar_power"
                    size: Theme.iconSizeSmall
                    color: root.hasFault ? Theme.error : (root.isOnline ? Theme.warning : root.mutedColor)
                    anchors.verticalCenter: parent.verticalCenter
                }
                StyledText {
                    text: "GoodWe Solar"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Bold
                    color: root.hasFault ? Theme.error : root.contentColor
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                visible: root.isOnline
                height: Theme.iconSizeMedium + Theme.spacingXXS
                width: yieldRow.implicitWidth + Theme.spacingS * 2
                radius: Theme.cornerRadius / 2
                color: root.chipColor

                Row {
                    id: yieldRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingXXS
                    DIcon {
                        name: "wb_sunny"
                        size: Theme.iconSizeSmall - Theme.spacingXXS
                        color: Theme.warning
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    StyledText {
                        text: `${root.eDayPvKwh} kWh`
                        font.pixelSize: Theme.fontSizeXSmall
                        font.weight: Font.Bold
                        color: root.contentColor
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Rectangle {
                height: Theme.iconSizeMedium + Theme.spacingXXS
                width: Theme.iconSizeMedium + Theme.spacingXXS
                radius: Theme.cornerRadius / 2
                color: cardPortalMouse.containsMouse ? root.chipColor : "transparent"

                DIcon {
                    name: "open_in_new"
                    size: Theme.iconSizeSmall - Theme.spacingXXS
                    color: cardPortalMouse.containsMouse ? root.accentColor : root.mutedColor
                    anchors.centerIn: parent
                }

                MouseArea {
                    id: cardPortalMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Qt.openUrlExternally(root.semsPortalUrl)
                }
            }
        }

        // 2. Main Generation & Battery Row
        RowLayout {
            Layout.fillWidth: true

            Column {
                spacing: 0
                StyledText {
                    text: root.isOnline ? root.formatWatts(root.pvPowerW) : "Offline"
                    font.pixelSize: Theme.fontSizeXLarge
                    font.weight: Font.Bold
                    color: root.pvPowerW > 500 ? Theme.warning : root.contentColor
                }

                StyledText {
                    text: root.hasFault ? root.faultSummary : (root.isOnline ? (root.pvPowerW > 0 ? "Generating Power" : "Standby") : "Inverter Unreachable")
                    font.pixelSize: Theme.fontSizeXSmall
                    color: root.hasFault ? Theme.error : root.mutedColor
                }
            }

            Item { Layout.fillWidth: true }

            Row {
                spacing: Theme.spacingXS
                DIcon {
                    name: root.getBatteryIcon(root.batterySoc, root.batteryChargeW > 0)
                    size: Theme.iconSizeSmall
                    color: root.batteryChargeW > 0 ? Theme.success : (root.batteryDischargeW > 0 ? Theme.info : root.mutedColor)
                    anchors.verticalCenter: parent.verticalCenter
                }
                StyledText {
                    text: `${root.batterySoc}%`
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Bold
                    color: root.contentColor
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // 3. Mini Generation Curve Graph
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 44
            radius: Theme.cornerRadius / 2
            color: root.chipColor

            Canvas {
                id: miniCanvas
                anchors.fill: parent
                anchors.margins: Theme.spacingXXS
                renderStrategy: Canvas.Cooperative

                property var pvData: root.historyPv
                property var loadData: root.historyLoad
                property color themeWarning: Theme.warning
                property color themeSurfaceText: root.contentColor

                onPvDataChanged: requestPaint()
                onLoadDataChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onThemeWarningChanged: requestPaint()
                onThemeSurfaceTextChanged: requestPaint()

                Connections {
                    target: Theme
                    function onCurrentThemeChanged() {
                        miniCanvas.requestPaint();
                    }
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.clearRect(0, 0, width, height);

                    if (!pvData || pvData.length < 2) {
                        ctx.fillStyle = Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.35);
                        ctx.font = `${Theme.fontSizeXSmall}px ${Theme.fontFamily || "sans-serif"}`;
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
                        const py = height - (pvData[i] / maxVal) * (height - Theme.spacingXS);
                        ctx.lineTo(px, py);
                    }
                    ctx.lineTo(width, height);
                    ctx.closePath();
                    ctx.fill();

                    // Solar Line
                    ctx.strokeStyle = Theme.warning;
                    ctx.lineWidth = Theme.spacingXXS;
                    ctx.beginPath();
                    for (let i = 0; i < n; i++) {
                        const px = i * stepX;
                        const py = height - (pvData[i] / maxVal) * (height - Theme.spacingXS);
                        i === 0 ? ctx.moveTo(px, py) : ctx.lineTo(px, py);
                    }
                    ctx.stroke();
                }
            }
        }

        // 4. Power Flows Grid (3 Columns)
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingXS

            // Battery Flow Chip
            Rectangle {
                Layout.fillWidth: true
                height: Theme.iconSizeMedium + Theme.spacingS
                radius: Theme.cornerRadius / 2
                color: root.chipColor

                Column {
                    anchors.centerIn: parent
                    spacing: 1
                    StyledText {
                        text: "Battery"
                        font.pixelSize: Theme.fontSizeXSmall
                        color: root.mutedColor
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    StyledText {
                        text: root.batteryChargeW > 0 ? `+${root.formatWatts(root.batteryChargeW)}` : (root.batteryDischargeW > 0 ? `-${root.formatWatts(root.batteryDischargeW)}` : "Idle")
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Bold
                        color: root.batteryChargeW > 0 ? Theme.success : (root.batteryDischargeW > 0 ? Theme.info : root.contentColor)
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            // Home Load Chip
            Rectangle {
                Layout.fillWidth: true
                height: Theme.iconSizeMedium + Theme.spacingS
                radius: Theme.cornerRadius / 2
                color: root.chipColor

                Column {
                    anchors.centerIn: parent
                    spacing: 1
                    StyledText {
                        text: "Home Load"
                        font.pixelSize: Theme.fontSizeXSmall
                        color: root.mutedColor
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
            }

            // Grid Flow Chip
            Rectangle {
                Layout.fillWidth: true
                height: Theme.iconSizeMedium + Theme.spacingS
                radius: Theme.cornerRadius / 2
                color: root.chipColor

                Column {
                    anchors.centerIn: parent
                    spacing: 1
                    StyledText {
                        text: root.gridPowerW > 0 ? "Grid (Export)" : (root.gridPowerW < 0 ? "Grid (Import)" : "Grid Flow")
                        font.pixelSize: Theme.fontSizeXSmall
                        color: root.mutedColor
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    StyledText {
                        text: root.gridPowerW > 0 ? `+${root.formatWatts(root.gridPowerW)}` : (root.gridPowerW < 0 ? `-${root.formatWatts(root.gridPowerW)}` : "0 W")
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Bold
                        color: root.gridPowerW > 0 ? Theme.success : (root.gridPowerW < 0 ? Theme.error : root.contentColor)
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }
}
