# GoodWe Solar & Battery Monitor for DankMaterialShell / Quickshell

Real-time local monitoring for GoodWe inverters with battery storage, designed for DankMaterialShell (DMS) on Quickshell.

## Features
- **Direct LAN Connection**: Polls the inverter locally via Modbus TCP (port 502) every 3 seconds. Zero cloud delay, no reliance on SEMS+ portal downtime or tokens.
- **DankBar Status Bar Pill**: Compact display of solar generation (`☀️ 1.2 kW`) and battery SOC (`🔋 60%`).
- **Interactive Popout**: Click the status bar pill to view real-time power flows (PV, Battery, House, Grid) and temperatures.
- **Control Center Tile**: Integrated tile with expandable detail panel and fault alarms.
- **Desktop Widget Card**: A resizable desktop card (matching the `dankDesktopWeather` style) showing generation gauges, power flows, and daily yield.
- **Fault & Health Alarms**: Instant visual indicators for any inverter faults, battery errors, or connection dropouts.

## Architecture
1. **Collector Daemon (`poller.py`)**:
   Runs as a `systemd --user` background service (`goodwe-solar.service`), querying `192.168.1.102:502` and writing an atomic JSON state file to `~/.cache/goodwe_solar.json`.
2. **DMS Plugin (`plugins/goodweSolar`)**:
   Provides the DankBar pill, popout dialog, and Control Center widget.
3. **Desktop Plugin (`plugins/goodweSolarDesktop`)**:
   Provides the desktop overlay widget card.

## Systemd Service
```bash
systemctl --user status goodwe-solar.service
```
Restart / logs:
```bash
systemctl --user restart goodwe-solar.service
journalctl --user -u goodwe-solar.service -f
```
