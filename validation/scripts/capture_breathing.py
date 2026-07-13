#!/usr/bin/env python3
"""wi-netra health — breathing capture session.

Records N seconds of continuous CSI from a stationary subject, then runs the
breathing pipeline and reports breaths-per-minute.

Usage:
    python capture_breathing.py COM9 --duration 120 --outdir data/sessions
"""
from __future__ import annotations

import argparse
import json
import os
import signal
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

try:
    import serial
except ImportError:
    sys.stderr.write("pyserial missing — run: pip install -r requirements.txt\n")
    sys.exit(1)

CSV_PREFIX = "CSI_DATA,"
HEADER_PREFIX = "type,"
DEFAULT_BAUD = 921600


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Capture a stationary breathing session.")
    p.add_argument("port", help="RX serial port, e.g. COM9")
    p.add_argument("--baud", type=int, default=DEFAULT_BAUD)
    p.add_argument("--duration", type=int, default=120,
                   help="seconds of continuous breathing capture (default 120)")
    p.add_argument("--outdir", default="data/sessions", help="output directory")
    p.add_argument("--no-analyze", action="store_true",
                   help="skip running extract_breathing_rate after capture")
    return p.parse_args()


def _slug(s: str) -> str:
    s = (s or "").strip().lower()
    out = "".join(c if c.isalnum() else "_" for c in s).strip("_")
    while "__" in out:
        out = out.replace("__", "_")
    return out or "unknown"


def _ask(prompt: str, default: str | None = None, required: bool = False) -> str:
    suffix = f" [{default}]" if default is not None and default != "" else ""
    while True:
        try:
            raw = input(f"  {prompt}{suffix}: ").strip()
        except EOFError:
            raw = ""
        if raw:
            return raw
        if default is not None:
            return default
        if not required:
            return ""
        sys.stdout.write("    (required)\n")


def _ask_number(prompt: str, required: bool = False) -> float | None:
    while True:
        raw = _ask(prompt, default=None if required else "", required=required)
        if raw == "":
            return None
        try:
            return float(raw)
        except ValueError:
            sys.stdout.write("    (must be a number)\n")


def prompt_metadata() -> dict:
    sys.stdout.write("\n=== Breathing session metadata ===\n")
    room = _ask("Room name", required=True)
    dist_ft = _ask_number("TX-RX distance (ft)", required=True)
    subject = _ask("Subject name", required=True)
    posture = _ask("Subject posture (sitting/lying/standing)", default="sitting").lower()
    chest_orientation = _ask(
        "Chest orientation vs LOS (facing/perpendicular/back)", default="facing"
    ).lower()
    notes = _ask("Notes (optional)")
    return {
        "room_name": room,
        "tx_rx_distance_ft": dist_ft,
        "subject": subject,
        "posture": posture,
        "chest_orientation": chest_orientation,
        "notes": notes,
    }


def open_rx(port: str, baud: int) -> "serial.Serial":
    s = serial.Serial()
    s.port = port
    s.baudrate = baud
    s.dsrdtr = False
    s.rtscts = False
    s.timeout = 0.2
    s.open()
    s.dtr = False
    s.rts = False
    time.sleep(1.0)
    return s


def main() -> int:
    args = parse_args()
    outdir = Path(args.outdir).resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    meta = prompt_metadata()
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    dist_str = f"{int(round(meta['tx_rx_distance_ft']))}ft"
    stem = f"breath_{ts}_{_slug(meta['room_name'])}_{dist_str}_{_slug(meta['subject'])}"
    csv_path = outdir / f"{stem}.csv"
    json_path = outdir / f"{stem}.breathing.json"

    stop = {"flag": False}
    def _sigint(signum, frame):  # noqa: ARG001
        stop["flag"] = True
    signal.signal(signal.SIGINT, _sigint)

    try:
        ser = open_rx(args.port, args.baud)
    except serial.SerialException as e:
        sys.stderr.write(f"cannot open {args.port}: {e}\n")
        return 2

    sys.stdout.write(f"\n=== Capturing {args.duration}s to {csv_path.name} ===\n")
    sys.stdout.write("  Subject: sit still, breathe normally. Recording starts NOW.\n\n")
    sys.stdout.flush()

    log_f = csv_path.open("w", encoding="utf-8", newline="")
    header_written = False
    total = 0
    session_start_iso = datetime.now().isoformat(timespec="microseconds")
    t_end = time.monotonic() + args.duration
    next_status = time.monotonic() + 5.0

    try:
        while not stop["flag"] and time.monotonic() < t_end:
            raw = ser.readline()
            if not raw:
                if time.monotonic() >= next_status:
                    remaining = max(0, int(t_end - time.monotonic()))
                    sys.stdout.write(f"  {remaining:3d}s left  total={total}\n")
                    sys.stdout.flush()
                    next_status = time.monotonic() + 5.0
                continue
            try:
                line = raw.decode("utf-8", errors="replace").rstrip("\r\n")
            except Exception:
                continue
            if not line:
                continue
            host_ts = datetime.now().isoformat(timespec="microseconds")
            if line.startswith(HEADER_PREFIX) and not header_written:
                log_f.write("host_recv_ts," + line + "\n")
                log_f.flush()
                header_written = True
                continue
            if not line.startswith(CSV_PREFIX):
                continue
            log_f.write(f"{host_ts},{line}\n")
            total += 1
            if time.monotonic() >= next_status:
                remaining = max(0, int(t_end - time.monotonic()))
                sys.stdout.write(f"  {remaining:3d}s left  total={total}\n")
                sys.stdout.flush()
                next_status = time.monotonic() + 5.0
    finally:
        try:
            ser.close()
        except Exception:
            pass
        log_f.flush()
        log_f.close()

    session_end_iso = datetime.now().isoformat(timespec="microseconds")
    result: dict = {
        "csv": csv_path.name,
        "session_start": session_start_iso,
        "session_end": session_end_iso,
        "total_packets": total,
        "metadata": meta,
    }

    if not args.no_analyze:
        try:
            from firmware.components.dsp_breathing.breathing import extract_breathing_rate
        except Exception as e:
            sys.stderr.write(f"cannot import breathing pipeline: {e}\n")
            json_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
            return 0

        sys.stdout.write("\n=== Running breathing analysis ===\n")
        sys.stdout.flush()
        try:
            r = extract_breathing_rate(csv_path)
            sys.stdout.write(
                f"  BPM (FFT):         {r['bpm_fft']:.1f}\n"
                f"  BPM (autocorr):    {r['bpm_autocorr']:.1f}\n"
                f"  BPM (median):      {r['bpm_median']:.1f}\n"
                f"  confidence:        {r['confidence']:.2f}\n"
                f"  methods agree:     {r['agreement']}\n"
            )
            sys.stdout.flush()
            result["bpm_fft"] = r["bpm_fft"]
            result["bpm_autocorr"] = r["bpm_autocorr"]
            result["bpm_median"] = r["bpm_median"]
            result["confidence"] = r["confidence"]
            result["agreement"] = r["agreement"]
            result["selected_pairs"] = r["selected_pairs"]
            result["sample_rate_hz"] = r["sample_rate_hz"]
        except Exception as e:
            sys.stderr.write(f"breathing analysis failed: {e}\n")
            result["error"] = str(e)

    json_path.write_text(json.dumps(result, indent=2, default=str), encoding="utf-8")
    sys.stdout.write(f"\n  CSV:      {csv_path}\n  sidecar:  {json_path}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
