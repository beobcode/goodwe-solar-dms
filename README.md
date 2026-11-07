# GoodWe Solar & Battery Monitor for DankMaterialShell / Quickshell

Real-time local monitoring for GoodWe inverters with battery storage, designed for [DankMaterialShell (DMS)](https://github.com/AvengeMedia/DankMaterialShell) on Quickshell.

---

## Features

- **Direct LAN Connection**: Polls your GoodWe hybrid/string inverter locally via Modbus TCP (port 502) every 3 seconds. Zero cloud delay, no tokens, and immune to SEMS+ portal outages.
- **DankBar Status Bar Pill**: Compact display of solar generation (`☀️ 1.2 kW`) and battery SOC (`🔋 60%`).
- **Interactive Popout**: Click the status bar pill to view live power flows (PV, Battery, House, Grid) with signed values (`+` charging / export, `-` discharging / import), inverter and battery temperatures, and a past 7 days generation bar chart.
- **4-Series Intra-day Canvas Graph**:
  - Solar PV generation (Amber area fill)
  - Home consumption / load (Purple dashed line)
  - Grid power (Sky Blue line with dynamic zero datum for import vs export)
  - Battery SoC % (Emerald green curve mapped to a dedicated 0–100% right Y-axis)
- **Control Center Integration**: Expandable detail tile in the DMS Control Center with power flow matrix, daily yield breakdown, and one-click launcher to your SEMS Portal account.
- **Desktop Widget Card**: A customizable desktop card (matching the `dankDesktopWeather` visual language) showing generation gauges, power flows, and daily yield.
- **Fault & Health Alarms**: Instant visual indicators for any inverter faults, battery errors, or connection dropouts.

---

## Architecture

1. **Collector Daemon (`poller.py`)**:
   A lightweight Python service that queries the inverter over LAN via Modbus TCP (port 502) and writes an atomic JSON snapshot to `${XDG_CACHE_HOME:-~/.cache}/goodwe_solar.json`.
2. **DMS Plugin (`plugins/goodweSolar2`)**:
   Provides the DankBar pill, popout dialog, and Control Center dropdown tile.
3. **Desktop Plugin (`plugins/goodweSolarDesktop`)**:
   Provides the desktop overlay widget card.

---

## Prerequisites

- Python 3.10+
- `goodwe` Python library
- DankMaterialShell (Quickshell) `>= 1.0.0`

---

## Installation & Setup

### 1. Clone the Repository

```bash
git clone https://github.com/<your-username>/goodwe-solar-dms.git ~/Projects/goodwe-solar-dms
cd ~/Projects/goodwe-solar-dms
```

### 2. Set Up Python Environment

```bash
python3 -m venv .venv
./.venv/bin/pip install --upgrade pip
./.venv/bin/pip install goodwe
```

### 3. Verify Local Inverter Connectivity

Test fetching a single telemetry snapshot by providing your inverter's local IP address:

```bash
./.venv/bin/python3 poller.py --host <INVERTER_IP> --once
```

*(You should see a formatted JSON dump containing live generation, battery status, and sensor readings.)*

### 4. Install Background Service (`systemd --user`)

Create a systemd user unit to keep telemetry running automatically in the background:

```bash
mkdir -p ~/.config/systemd/user
cat << 'EOF' > ~/.config/systemd/user/goodwe-solar.service
[Unit]
Description=GoodWe Solar Inverter Local Poller Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=%h/Projects/goodwe-solar-dms
Environment=GOODWE_INVERTER_IP=192.168.1.100
ExecStart=%h/Projects/goodwe-solar-dms/.venv/bin/python3 %h/Projects/goodwe-solar-dms/poller.py
Restart=always
RestartSec=5s

[Install]
WantedBy=default.target
EOF
```

> **Note:** Replace `192.168.1.100` above with your inverter's actual local IP address.

Enable and start the service:

```bash
systemctl --user daemon-reload
systemctl --user enable --now goodwe-solar.service
```

Check service status and logs:

```bash
systemctl --user status goodwe-solar.service
journalctl --user -u goodwe-solar.service -f
```

---

## Installing into DankMaterialShell

Copy the plugins into your DMS plugins directory:

```bash
mkdir -p ~/.config/DankMaterialShell/plugins/
cp -r plugins/goodweSolar2 ~/.config/DankMaterialShell/plugins/
cp -r plugins/goodweSolarDesktop ~/.config/DankMaterialShell/plugins/
```

Reload plugins via DMS IPC:

```bash
dms ipc plugins reload goodweSolar2
dms ipc plugins reload goodweSolarDesktop
```

### Adding to Control Center & Desktop

1. Open **DMS Settings** (`Mod + ,` or click Settings in DankBar).
2. Under **Control Center**, add `plugin_goodweSolar2` to your active widgets.
3. Under **Desktop Widgets**, add `goodweSolarDesktop` to place the solar card onto your desktop.

---

## Configuration & Environment Variables

The poller daemon supports the following environment variables (or CLI arguments):

| Environment Variable | CLI Argument | Default | Description |
| :--- | :--- | :--- | :--- |
| `GOODWE_INVERTER_IP` | `--host` | `192.168.1.100` | Inverter local IP address |
| `GOODWE_INVERTER_PORT` | `--port` | `502` | Modbus TCP port |
| `GOODWE_POLL_INTERVAL` | `--interval` | `3.0` | Poll interval in seconds |
| `GOODWE_OUTPUT_FILE` | `--output` | `~/.cache/goodwe_solar.json` | Telemetry JSON snapshot path |

---

## Submitting to the DMS Plugin Registry

The official DankMaterialShell plugin repository index is maintained at [AvengeMedia/dms-plugin-registry](https://github.com/AvengeMedia/dms-plugin-registry).

To publish this plugin to the registry so any DMS user can install it via `dms plugins install`:

1. Push your repository to your public GitHub account (e.g. `https://github.com/<your-username>/goodwe-solar-dms`).
2. Fork [AvengeMedia/dms-plugin-registry](https://github.com/AvengeMedia/dms-plugin-registry).
3. In your fork, add your plugin entry under `plugins/<your-username>-goodwe-solar.json`:
   ```json
   {
     "id": "goodweSolar2",
     "name": "GoodWe Solar & Battery",
     "category": "monitoring",
     "author": "<Your Name or Handle>",
     "description": "Real-time local GoodWe inverter telemetry, battery status, 4-series power curve, and fault monitor via Modbus TCP",
     "repo": "https://github.com/<your-username>/goodwe-solar-dms",
     "capabilities": ["dankbar-widget", "control-center", "monitoring"],
     "dependencies": ["python3"]
   }
   ```
4. Open a Pull Request on `AvengeMedia/dms-plugin-registry`. Once merged, it will automatically show up in `dms plugins browse`!

---

## License

MIT
