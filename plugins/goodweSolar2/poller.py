#!/usr/bin/env python3
"""
GoodWe Inverter Poller Daemon
Reads telemetry directly via Modbus TCP (port 502), maintains historical daily & power trends,
and writes atomic status JSON.
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

DEFAULT_HOST = os.environ.get("GOODWE_INVERTER_IP", "192.168.1.100")
DEFAULT_PORT = int(os.environ.get("GOODWE_INVERTER_PORT", "502"))
DEFAULT_INTERVAL = float(os.environ.get("GOODWE_POLL_INTERVAL", "3.0"))

_xdg_cache = os.environ.get("XDG_CACHE_HOME")
_cache_dir = Path(_xdg_cache) if _xdg_cache else Path.home() / ".cache"

DEFAULT_OUTPUT_FILE = os.environ.get("GOODWE_OUTPUT_FILE", str(_cache_dir / "goodwe_solar.json"))
HISTORY_FILE = os.environ.get("GOODWE_HISTORY_FILE", str(_cache_dir / "goodwe_solar_history.json"))


def clean_val(val, default=0):
    if val is None or val == "":
        return default
    return val


def load_history():
    """Load persistent daily history and power samples."""
    p = Path(HISTORY_FILE)
    if p.exists():
        try:
            with open(p, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return {
        "days": {},  # "YYYY-MM-DD": {"pv_kwh": x, "exp_kwh": y, "load_kwh": z, "peak_pv_w": w}
        "today_samples": []  # [{"time": "09:30", "pv_w": 1200, "load_w": 300, "soc": 60, "grid_w": 200}]
    }


def save_history(history):
    """Save persistent history atomically."""
    dest_path = Path(HISTORY_FILE)
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    temp_file = tempfile.NamedTemporaryFile("w", dir=dest_path.parent, delete=False)
    try:
        json.dump(history, temp_file, indent=2)
        temp_file.flush()
        os.fsync(temp_file.fileno())
        temp_file.close()
        os.replace(temp_file.name, dest_path)
    except Exception as e:
        if os.path.exists(temp_file.name):
            os.remove(temp_file.name)
        logger.warning(f"Could not save history: {e}")


def update_history(history, today_str, time_str, ppv, pgrid, house_load, battery_soc, battery_power, e_day, e_day_exp, e_load_day):
    """Record day totals and downsampled intra-day time points."""
    # 1. Update today's record
    days = history.setdefault("days", {})
    day_entry = days.setdefault(today_str, {
        "pv_kwh": 0.0,
        "exp_kwh": 0.0,
        "load_kwh": 0.0,
        "peak_pv_w": 0
    })
    day_entry["pv_kwh"] = round(max(day_entry["pv_kwh"], float(e_day)), 2)
    day_entry["exp_kwh"] = round(max(day_entry["exp_kwh"], float(e_day_exp)), 2)
    day_entry["load_kwh"] = round(max(day_entry["load_kwh"], float(e_load_day)), 2)
    day_entry["peak_pv_w"] = max(day_entry["peak_pv_w"], int(ppv))

    # Keep at most last 30 days
    if len(days) > 30:
        sorted_keys = sorted(days.keys())
        for old_k in sorted_keys[:-30]:
            del days[old_k]

    # 2. Add time samples for graph over time (every ~60-120 seconds or if changed significantly)
    samples = history.setdefault("today_samples", [])
    now_ts = int(time.time())

    should_add = False
    if not samples:
        should_add = True
    else:
        last_s = samples[-1]
        # Reset samples array if day rolled over
        if last_s.get("day") != today_str:
            samples.clear()
            should_add = True
        elif now_ts - last_s.get("ts", 0) >= 60:  # record every 60 seconds
            should_add = True

    if should_add:
        samples.append({
            "day": today_str,
            "ts": now_ts,
            "time": time_str,
            "pv_w": int(ppv),
            "load_w": int(house_load),
            "grid_w": int(pgrid),
            "bat_w": int(battery_power),
            "soc": int(battery_soc)
        })
        # Keep maximum 1440 points (24 hours at 1/min)
        if len(samples) > 1440:
            samples.pop(0)


def parse_inverter_data(inv, runtime, history):
    """Normalize raw sensor dictionary into a clean, UI-ready payload."""
    ppv = clean_val(runtime.get("ppv") or runtime.get("ppv_total") or runtime.get("ppv1"), 0)
    ppv1 = clean_val(runtime.get("ppv1"), 0)
    ppv2 = clean_val(runtime.get("ppv2"), 0)

    # Battery metrics
    # In GoodWe Modbus: pbattery1 is negative when charging, positive when discharging.
    # Sign convention: positive indicates charging, negative indicates discharging.
    raw_pbattery = clean_val(runtime.get("pbattery1"), 0)
    bat_charge_w = int(abs(raw_pbattery)) if raw_pbattery < 0 else 0
    bat_discharge_w = int(raw_pbattery) if raw_pbattery > 0 else 0
    signed_battery_power_w = bat_charge_w if bat_charge_w > 0 else (-bat_discharge_w)

    battery_soc = clean_val(runtime.get("battery_soc"), 0)
    battery_soh = clean_val(runtime.get("battery_soh"), 100)
    battery_mode_code = clean_val(runtime.get("battery_mode"), 0)
    battery_mode_label = str(runtime.get("battery_mode_label") or "Idle").strip()
    battery_temp = clean_val(runtime.get("battery_temperature"), 0.0)
    vbattery = clean_val(runtime.get("vbattery1"), 0.0)
    ibattery = clean_val(runtime.get("ibattery1"), 0.0)

    # Grid metrics: positive indicates export to grid, negative indicates import from grid.
    active_power = clean_val(runtime.get("active_power"), None)
    if active_power is not None:
        signed_grid_w = int(active_power)
    else:
        raw_pgrid = clean_val(runtime.get("pgrid"), 0)
        signed_grid_w = int(raw_pgrid)

    grid_export_w = signed_grid_w if signed_grid_w > 0 else 0
    grid_import_w = abs(signed_grid_w) if signed_grid_w < 0 else 0

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

    now_t = time.localtime()
    today_str = time.strftime("%Y-%m-%d", now_t)
    time_str = time.strftime("%H:%M", now_t)

    # Update history tracking (stores signed grid_w and signed bat_w)
    update_history(history, today_str, time_str, ppv, signed_grid_w, house_consumption, battery_soc, signed_battery_power_w, e_day, e_day_exp, e_load_day)

    # Downsampled time series for QML graph
    today_samples = history.get("today_samples", [])
    pv_history = [s.get("pv_w", 0) for s in today_samples]
    load_history = [s.get("load_w", 0) for s in today_samples]
    grid_history = [s.get("grid_w", 0) for s in today_samples]
    soc_history = [s.get("soc", 0) for s in today_samples]
    bat_history = [s.get("bat_w", 0) for s in today_samples]
    time_labels = [s.get("time", "") for s in today_samples]

    # Last 7 days summary for daily bar chart
    days_dict = history.get("days", {})
    recent_days = []
    for d in sorted(days_dict.keys())[-7:]:
        item = days_dict[d].copy()
        item["date"] = d
        item["day_name"] = time.strftime("%a", time.strptime(d, "%Y-%m-%d"))
        recent_days.append(item)

    status_data = {
        "online": True,
        "timestamp": int(time.time()),
        "last_updated": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": str(inv.model_name or "GoodWe Inverter").replace("\u4d57", "GoodWe"),
        "serial": str(inv.serial_number or ""),
        "firmware": str(inv.firmware or ""),
        "work_mode": work_mode_label,

        # Power flows (Watts)
        # Sign convention: + means charging / sending to grid; - means discharging / buying from grid
        "pv_power_w": int(ppv),
        "pv1_power_w": int(ppv1),
        "pv2_power_w": int(ppv2),
        "battery_power_w": signed_battery_power_w,
        "battery_charge_w": bat_charge_w,
        "battery_discharge_w": bat_discharge_w,
        "house_consumption_w": int(house_consumption),
        "grid_power_w": signed_grid_w,
        "grid_export_w": grid_export_w,
        "grid_import_w": grid_import_w,
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
        "fault_messages": fault_messages,

        # Historical trend data for graph rendering
        "history_pv": pv_history,
        "history_load": load_history,
        "history_grid": grid_history,
        "history_soc": soc_history,
        "history_battery": bat_history,
        "history_times": time_labels,
        "recent_days": recent_days
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


def write_offline_status(dest_path, message="Inverter Unreachable"):
    """Write an offline status snapshot so UI immediately reflects disconnection."""
    data = {
        "online": False,
        "timestamp": int(time.time()),
        "last_updated": time.strftime("%Y-%m-%d %H:%M:%S"),
        "has_fault": True,
        "fault_summary": message,
        "fault_messages": [message],
        "pv_power_w": 0,
        "battery_power_w": 0,
        "battery_charge_w": 0,
        "battery_discharge_w": 0,
        "grid_power_w": 0,
        "grid_export_w": 0,
        "grid_import_w": 0,
        "house_consumption_w": 0
    }
    try:
        write_atomic_json(dest_path, data)
    except Exception as e:
        logger.warning(f"Failed to write offline state: {e}")


async def run_poller(host, port, interval, output_file):
    logger.info(f"Connecting to GoodWe Inverter at {host}:{port}...")
    dest_path = Path(output_file)
    history = load_history()
    last_hist_save = time.time()

    while True:
        try:
            inv = await goodwe.connect(host, port=port, timeout=2, retries=2)
            logger.info(f"Connected to inverter: {inv.model_name} (Serial: {inv.serial_number})")

            while True:
                try:
                    runtime = await asyncio.wait_for(inv.read_runtime_data(), timeout=3.5)
                    data = parse_inverter_data(inv, runtime, history)
                    write_atomic_json(dest_path, data)

                    # Periodically save history to disk (every 30 seconds)
                    if time.time() - last_hist_save >= 30:
                        save_history(history)
                        last_hist_save = time.time()

                except asyncio.TimeoutError:
                    logger.warning("Read runtime data timeout")
                    write_offline_status(dest_path, "Inverter Read Timeout")
                except Exception as e:
                    logger.warning(f"Error reading inverter runtime: {e}")
                    write_offline_status(dest_path, f"Runtime Read Error: {e}")
                    break
                await asyncio.sleep(interval)
        except Exception as conn_err:
            logger.error(f"Inverter connection error: {conn_err}. Retrying in 5 seconds...")
            write_offline_status(dest_path, f"Connection Failed: {conn_err}")
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
            history = load_history()
            inv = await goodwe.connect(args.host, port=args.port, timeout=2, retries=2)
            runtime = await inv.read_runtime_data()
            data = parse_inverter_data(inv, runtime, history)
            save_history(history)
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
