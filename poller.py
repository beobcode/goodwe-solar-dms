#!/usr/bin/env python3
"""
GoodWe Inverter Poller Daemon
Reads telemetry directly via Modbus TCP (port 502) and writes atomic status JSON.
"""

import argparse
import asyncio
import json
import logging
import os
import sys
import tempfile
import time
from pathlib import Path

try:
    import goodwe
except ImportError:
    print("Error: 'goodwe' library is required. Install via 'pip install goodwe' or run inside project venv.", file=sys.stderr)
    sys.exit(1)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
logger = logging.getLogger("goodwe_poller")

DEFAULT_HOST = "192.168.1.102"
DEFAULT_PORT = 502
DEFAULT_INTERVAL = 3.0
DEFAULT_OUTPUT_FILE = str(Path.home() / ".cache" / "goodwe_solar.json")


def clean_val(val, default=0):
    if val is None or val == "":
        return default
    return val


def parse_inverter_data(inv, runtime):
    """Normalize raw sensor dictionary into a clean, UI-ready payload."""
    ppv = clean_val(runtime.get("ppv") or runtime.get("ppv_total") or runtime.get("ppv1"), 0)
    ppv1 = clean_val(runtime.get("ppv1"), 0)
    ppv2 = clean_val(runtime.get("ppv2"), 0)

    # Battery metrics
    battery_soc = clean_val(runtime.get("battery_soc"), 0)
    battery_soh = clean_val(runtime.get("battery_soh"), 100)
    pbattery = clean_val(runtime.get("pbattery1"), 0)  # negative = charging, positive = discharging
    battery_mode_code = clean_val(runtime.get("battery_mode"), 0)
    battery_mode_label = str(runtime.get("battery_mode_label") or "Idle").strip()
    battery_temp = clean_val(runtime.get("battery_temperature"), 0.0)
    vbattery = clean_val(runtime.get("vbattery1"), 0.0)
    ibattery = clean_val(runtime.get("ibattery1"), 0.0)

    # Grid metrics
    pgrid = clean_val(runtime.get("pgrid") or runtime.get("active_power") or runtime.get("active_power_total"), 0)
    grid_mode_label = str(runtime.get("grid_mode_label") or "Connected to grid").strip()
    vgrid = clean_val(runtime.get("vgrid"), 0.0)
    fgrid = clean_val(runtime.get("fgrid"), 50.0)

    # Load / House consumption
    house_consumption = clean_val(runtime.get("house_consumption") or runtime.get("load_ptotal") or runtime.get("load_p1"), 0)
    backup_ptotal = clean_val(runtime.get("backup_ptotal"), 0)

    # Energy counters (kWh)
    e_day = clean_val(runtime.get("e_day"), 0.0)
    e_total = clean_val(runtime.get("e_total"), 0.0)
    e_day_exp = clean_val(runtime.get("e_day_exp"), 0.0)
    e_day_imp = clean_val(runtime.get("e_day_imp"), 0.0)
    e_bat_charge_day = clean_val(runtime.get("e_bat_charge_day"), 0.0)
    e_bat_discharge_day = clean_val(runtime.get("e_bat_discharge_day"), 0.0)
    e_load_day = clean_val(runtime.get("e_load_day"), 0.0)

    # Faults and Warnings
    error_codes = clean_val(runtime.get("error_codes"), 0)
    errors_str = str(runtime.get("errors") or "").strip()
    warning_code = clean_val(runtime.get("warning_code"), 0)
    battery_error = str(runtime.get("battery_error") or "").strip()
    battery_warning = str(runtime.get("battery_warning") or "").strip()

    has_fault = bool(error_codes != 0 or errors_str or battery_error)
    has_warning = bool(warning_code != 0 or battery_warning)

    fault_messages = []
    if errors_str:
        fault_messages.append(errors_str)
    if error_codes != 0 and not errors_str:
        fault_messages.append(f"Inverter Error Code: {error_codes}")
    if battery_error:
        fault_messages.append(f"Battery: {battery_error}")
    if battery_warning:
        fault_messages.append(f"Battery Warn: {battery_warning}")

    work_mode_label = str(runtime.get("work_mode_label") or "Normal").strip()
    temp_air = clean_val(runtime.get("temperature_air"), 0.0)
    temp_inverter = clean_val(runtime.get("temperature"), 0.0)

    status_data = {
        "online": True,
        "timestamp": int(time.time()),
        "last_updated": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": str(inv.model_name or "GoodWe Inverter").replace("\u4d57", "GoodWe"),
        "serial": str(inv.serial_number or ""),
        "firmware": str(inv.firmware or ""),
        "work_mode": work_mode_label,

        # Power flows (Watts)
        "pv_power_w": int(ppv),
        "pv1_power_w": int(ppv1),
        "pv2_power_w": int(ppv2),
        "battery_power_w": int(pbattery),
        "battery_charge_w": int(abs(pbattery)) if pbattery < 0 else 0,
        "battery_discharge_w": int(pbattery) if pbattery > 0 else 0,
        "house_consumption_w": int(house_consumption),
        "grid_power_w": int(pgrid),  # positive = export or inverter active, depending on sign
        "grid_export_w": int(pgrid) if pgrid > 0 else 0,
        "grid_import_w": int(abs(pgrid)) if pgrid < 0 else 0,
        "backup_power_w": int(backup_ptotal),

        # Battery details
        "battery_soc": int(battery_soc),
        "battery_soh": int(battery_soh),
        "battery_mode": battery_mode_label,
        "battery_voltage": round(float(vbattery), 1),
        "battery_current": round(float(ibattery), 1),
        "battery_temp": round(float(battery_temp), 1),

        # Grid details
        "grid_voltage": round(float(vgrid), 1),
        "grid_frequency": round(float(fgrid), 2),
        "grid_mode": grid_mode_label,

        # Inverter temperatures
        "temp_air": round(float(temp_air), 1),
        "temp_inverter": round(float(temp_inverter), 1),

        # Daily Energy (kWh)
        "e_day_pv_kwh": round(float(e_day), 2),
        "e_total_pv_kwh": round(float(e_total), 1),
        "e_day_exp_kwh": round(float(e_day_exp), 2),
        "e_day_imp_kwh": round(float(e_day_imp), 2),
        "e_day_load_kwh": round(float(e_load_day), 2),
        "e_day_charge_kwh": round(float(e_bat_charge_day), 2),
        "e_day_discharge_kwh": round(float(e_bat_discharge_day), 2),

        # Faults & Alarms
        "has_fault": has_fault,
        "has_warning": has_warning,
        "error_codes": int(error_codes),
        "warning_code": int(warning_code),
        "fault_summary": ", ".join(fault_messages) if fault_messages else "System Normal",
        "fault_messages": fault_messages
    }
    return status_data


def write_atomic_json(filepath, data):
    """Write JSON file atomically to prevent reading half-written files."""
    dest_path = Path(filepath)
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    temp_file = tempfile.NamedTemporaryFile("w", dir=dest_path.parent, delete=False)
    try:
        json.dump(data, temp_file, indent=2)
        temp_file.flush()
        os.fsync(temp_file.fileno())
        temp_file.close()
        os.replace(temp_file.name, dest_path)
    except Exception as e:
        if os.path.exists(temp_file.name):
            os.remove(temp_file.name)
        raise e


async def run_poller(host, port, interval, output_file):
    logger.info(f"Connecting to GoodWe Inverter at {host}:{port}...")
    dest_path = Path(output_file)

    while True:
        try:
            inv = await goodwe.connect(host, port=port, timeout=2, retries=2)
            logger.info(f"Connected to inverter: {inv.model_name} (Serial: {inv.serial_number})")

            while True:
                try:
                    runtime = await asyncio.wait_for(inv.read_runtime_data(), timeout=3.5)
                    data = parse_inverter_data(inv, runtime)
                    write_atomic_json(dest_path, data)
                except asyncio.TimeoutError:
                    logger.warning("Read runtime data timeout")
                except Exception as e:
                    logger.warning(f"Error reading inverter runtime: {e}")
                    break  # Break inner loop to re-connect
                await asyncio.sleep(interval)
        except Exception as conn_err:
            logger.error(f"Inverter connection error: {conn_err}. Retrying in 5 seconds...")
            # Write offline status
            offline_payload = {
                "online": False,
                "timestamp": int(time.time()),
                "last_updated": time.strftime("%Y-%m-%d %H:%M:%S"),
                "fault_summary": f"Inverter unreachable ({conn_err})",
                "has_fault": True
            }
            try:
                write_atomic_json(dest_path, offline_payload)
            except Exception:
                pass
            await asyncio.sleep(5)


def main():
    parser = argparse.ArgumentParser(description="GoodWe Solar Modbus Poller")
    parser.add_argument("--host", default=DEFAULT_HOST, help=f"Inverter IP address (default: {DEFAULT_HOST})")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"Modbus port (default: {DEFAULT_PORT})")
    parser.add_argument("--interval", type=float, default=DEFAULT_INTERVAL, help=f"Poll interval in seconds (default: {DEFAULT_INTERVAL})")
    parser.add_argument("--output", default=DEFAULT_OUTPUT_FILE, help=f"Output JSON path (default: {DEFAULT_OUTPUT_FILE})")
    parser.add_argument("--once", action="store_true", help="Fetch once and exit")

    args = parser.parse_args()

    if args.once:
        async def once():
            inv = await goodwe.connect(args.host, port=args.port, timeout=2, retries=2)
            runtime = await inv.read_runtime_data()
            data = parse_inverter_data(inv, runtime)
            write_atomic_json(args.output, data)
            print(json.dumps(data, indent=2))
        asyncio.run(once())
    else:
        try:
            asyncio.run(run_poller(args.host, args.port, args.interval, args.output))
        except KeyboardInterrupt:
            logger.info("Poller stopped by user.")


if __name__ == "__main__":
    main()
