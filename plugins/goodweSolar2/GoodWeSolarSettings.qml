import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "goodweSolar2"

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
}
