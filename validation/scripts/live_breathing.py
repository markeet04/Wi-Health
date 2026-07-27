#!/usr/bin/env python3
"""wi-netra health — live continuous breathing monitor (Module 3 Phase 2).

Streams CSI from the RX board and prints a breathing-rate update every
stride_seconds (default 5s), same as a live deployment would — instead of
capture_breathing.py's record-N-seconds-then-analyze-once batch flow.

Records the raw CSI to disk as it goes (so a session can be re-analyzed
later, same as any other capture), but analysis happens continuously
in the background via sliding_window_estimate: once enough seconds have
landed for one more window, it's estimated and printed immediately.

Also the intended tool for the Phase 2 motion-rejection test: run this,
sit still for the first ~40s, then shift position / stand up / sit back
down around the middle of the session, and confirm the printed status
flips to "motion_rejected" during the movement and recovers after.

Usage:
    python live_breathing.py COM9 --duration 180 --outdir ../../validation/data
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

from firmware.components.dsp_breathing.breathing import DEFAULTS, sliding_window_estimate

CSV_PREFIX = "CSI_DATA,"
HEADER_PREFIX = "type,"
DEFAULT_BAUD = 921600


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Live continuous breathing monitor.")
    p.add_argument("port", help="RX serial port (native USB), e.g. COM9")
    p.add_argument("--baud", type=int, default=DEFAULT_BAUD)
    p.add_argument("--duration", type=int, default=180,
                    help="total seconds to run (default 180 = 3 min)")
    p.add_argument("--outdir", default="data", help="output directory for the raw CSV")
    p.add_argument("--window-seconds", type=float, default=DEFAULTS["window_seconds"],
                    help=f"estimation window length (default {DEFAULTS['window_seconds']:.0f}s)")
    p.add_argument("--stride-seconds", type=float, default=DEFAULTS["stride_seconds"],
                    help=f"seconds between updates (default {DEFAULTS['stride_seconds']:.0f}s)")
    return p.parse_args()


def _slug(s: str) -> str:
    out = "".join(c if c.isalnum() else "_" for c in (s or "").strip().lower()).strip("_")
    while "__" in out:
        out = out.replace("__", "_")
    return out or "unknown"


def _ask(prompt: str, default: str | None = None, required: bool = False) -> str:
    suffix = f" [{default}]" if default else ""
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


def open_rx(port: str, baud: int) -> "serial.Serial":
    s = serial.Serial()
    s.port = port
    s.baudrate = baud
    s.dsrdtr = False
    s.rtscts = False
    s.timeout = 0.2
    s.open()
    s.dtr = False
    s.rts = True
    time.sleep(0.15)
    s.rts = False
    time.sleep(1.0)
    return s


def _status_line(r: dict) -> str:
    if r["motion_rejected"]:
        return (f"  [{r['window_start_s']:6.1f}s-{r['window_end_s']:6.1f}s]  "
                f"MOTION DETECTED — window skipped  "
                f"(score {r['motion_score']:.4f} vs baseline {r['motion_baseline']:.4f})")

    tag = "" if r["status"] == "ok" else f"  <-- {r['status'].upper()}, not trusted"
    smoothed = (f"smoothed={r['smoothed_bpm']:.1f} (n={r['smoothed_window_count']})"
                if r["smoothed_window_count"] > 0 else "smoothed=--")
    return (f"  [{r['window_start_s']:6.1f}s-{r['window_end_s']:6.1f}s]  "
            f"bpm={r['bpm_median']:5.1f}  conf={r['confidence']:+.2f}  "
            f"{smoothed}{tag}")


def main() -> int:
    args = parse_args()
    outdir = Path(args.outdir).resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    sys.stdout.write("\n=== Live breathing monitor — session metadata ===\n")
    room = _ask("Room name", required=True)
    dist = _ask("TX-RX distance (ft)", required=True)
    subject = _ask("Subject name", required=True)
    notes = _ask(
        "Notes (e.g. 'will shift position at ~90s for motion test')", default="")

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    stem = f"live_{ts}_{_slug(room)}_{_slug(dist)}ft_{_slug(subject)}"
    csv_path = outdir / f"{stem}.csv"
    json_path = outdir / f"{stem}.live.json"

    stop = {"flag": False}

    def _sigint(signum, frame):  # noqa: ARG001
        stop["flag"] = True

    signal.signal(signal.SIGINT, _sigint)

    try:
        ser = open_rx(args.port, args.baud)
    except serial.SerialException as e:
        sys.stderr.write(f"cannot open {args.port}: {e}\n")
        return 2

    sys.stdout.write(
        f"\n=== Recording {args.duration}s to {csv_path.name} ===\n"
        f"  window={args.window_seconds:.0f}s stride={args.stride_seconds:.0f}s — "
        f"first estimate appears once {args.window_seconds:.0f}s of data has landed.\n"
        "  Subject: sit still, breathe normally. Ctrl+C to stop early.\n\n"
    )
    sys.stdout.flush()

    log_f = csv_path.open("w", encoding="utf-8", newline="")
    header_written = False
    total = 0
    t_end = time.monotonic() + args.duration

    try:
        while not stop["flag"] and time.monotonic() < t_end:
            raw = ser.readline()
            if not raw:
                continue
            line = raw.decode("utf-8", errors="replace").rstrip("\r\n")
            if not line:
                continue
            host_ts = datetime.now().isoformat(timespec="microseconds")
            if line.startswith(HEADER_PREFIX) and not header_written:
                log_f.write("host_recv_ts," + line + "\n")
                header_written = True
                continue
            if not line.startswith(CSV_PREFIX):
                continue
            log_f.write(f"{host_ts},{line}\n")
            total += 1
    finally:
        try:
            ser.close()
        except Exception:
            pass
        log_f.flush()
        log_f.close()

    sys.stdout.write(f"\n  capture done — {total} packets. Replaying as sliding windows...\n\n")
    sys.stdout.flush()

    config = {"window_seconds": args.window_seconds, "stride_seconds": args.stride_seconds}
    windows: list[dict] = []
    try:
        for r in sliding_window_estimate(csv_path, config=config):
            sys.stdout.write(_status_line(r) + "\n")
            sys.stdout.flush()
            windows.append({k: v for k, v in r.items()
                             if k not in ("respiratory_waveform", "waveform_unfiltered",
                                          "spectrum", "spectrum_freqs", "selected_pairs")})
    except ValueError as e:
        sys.stderr.write(f"\n  cannot run sliding-window analysis: {e}\n")
        windows = []

    valid_windows = [w for w in windows if w.get("status") == "ok"]
    motion_windows = [w for w in windows if w.get("motion_rejected")]
    result = {
        "csv": csv_path.name,
        "total_packets": total,
        "metadata": {
            "room_name": room, "tx_rx_distance_ft": dist,
            "subject": subject, "notes": notes,
        },
        "config": config,
        "window_count": len(windows),
        "valid_window_count": len(valid_windows),
        "motion_rejected_count": len(motion_windows),
        "final_smoothed_bpm": windows[-1]["smoothed_bpm"] if windows else float("nan"),
        "windows": windows,
    }
    json_path.write_text(json.dumps(result, indent=2), encoding="utf-8")

    sys.stdout.write(
        f"\n=== Summary ===\n"
        f"  windows:            {len(windows)}\n"
        f"  valid (status=ok):  {len(valid_windows)}\n"
        f"  motion-rejected:    {len(motion_windows)}\n"
        f"  final smoothed bpm: {result['final_smoothed_bpm']:.1f}\n"
        f"  written:            {json_path.name}\n"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
