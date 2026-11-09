import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "goodweSolar2"

    function updateDashCard(enabled) {
        if (typeof SettingsData === "undefined" || !SettingsData.dashCards) return;
        const cardId = "plugin_goodweSolar2";
        let cards = SettingsData.dashCards.slice();
        const exists = cards.some(c => c.id === cardId);
        if (enabled && !exists) {
            cards.push({ "id": cardId, "w": 2, "h": 2 });
            SettingsData.set("dashCards", cards);
        } else if (!enabled && exists) {
            cards = cards.filter(c => c.id !== cardId);
            SettingsData.set("dashCards", cards);
        }
    }

    StyledText {
        width: parent.width
        text: "GoodWe Solar Monitor Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Monitors your GoodWe solar inverter locally via Modbus TCP (port 502). Requires the companion background poller daemon (poller.py)."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "portalUrl"
        label: "SEMS Portal URL"
        description: "URL opened by the SEMS Portal button (e.g. global, AU, or EU portal)"
        placeholder: "https://au-semsplus.goodwe.com/"
        defaultValue: "https://au-semsplus.goodwe.com/"
    }

    ToggleSetting {
        id: dashCardToggle
        settingKey: "enableDashCard"
        label: "Dashboard Overview Card (Dash Card)"
        description: "Add a live GoodWe solar card to the Dashboard Overview (DankDash) grid"
        defaultValue: false

        onValueChanged: {
            if (isInitialized) {
                root.updateDashCard(value);
            }
        }
    }

    ToggleSetting {
        settingKey: "showBatteryInBar"
        label: "Show Battery in Status Bar"
        description: "Display battery percentage alongside solar generation in DankBar"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showDailyEnergy"
        label: "Show Daily Generation"
        description: "Display today's total kWh generated in the bar pill"
        defaultValue: true
    }

    StringSetting {
        settingKey: "cacheFilePath"
        label: "Telemetry Cache File Path"
        description: "Custom path to goodwe_solar.json if changed via GOODWE_OUTPUT_FILE or --output in poller"
        placeholder: "Leave empty for default (~/.cache/goodwe_solar.json)"
        defaultValue: ""
    }

    Connections {
        target: typeof SettingsData !== "undefined" ? SettingsData : null
        function onDashCardsChanged() {
            if (!SettingsData.dashCards) return;
            const isPlaced = SettingsData.dashCards.some(c => c.id === "plugin_goodweSolar2");
            if (dashCardToggle.isInitialized && dashCardToggle.value !== isPlaced) {
                dashCardToggle.value = isPlaced;
            }
        }
    }

    Component.onCompleted: {
        Qt.callLater(() => {
            if (typeof SettingsData !== "undefined" && SettingsData.dashCards) {
                const isPlaced = SettingsData.dashCards.some(c => c.id === "plugin_goodweSolar2");
                if (isPlaced) {
                    dashCardToggle.value = true;
                }
            }
        });
    }
}
