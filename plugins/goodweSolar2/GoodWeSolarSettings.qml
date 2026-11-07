import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "goodweSolar"

    StyledText {
        width: parent.width
        text: "GoodWe Solar Monitor Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Monitors your GoodWe solar inverter locally via Modbus TCP (port 502) without cloud dependency."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "inverterHost"
        label: "Inverter IP Address"
        description: "Local IP address of the inverter"
        placeholder: "192.168.1.102"
        defaultValue: "192.168.1.102"
    }

    SelectionSetting {
        settingKey: "pollInterval"
        label: "Update Interval"
        description: "How frequently to refresh telemetry"
        options: [
            { label: "2 Seconds", value: "2000" },
            { label: "3 Seconds", value: "3000" },
            { label: "5 Seconds", value: "5000" },
            { label: "10 Seconds", value: "10000" }
        ]
        defaultValue: "3000"
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
        description: "Display today's total kWh generated"
        defaultValue: true
    }
}
