#!/usr/bin/env python3
"""wi-netra health — resilient long-duration (overnight) breathing capture.

Same CSI capture + sliding-window analysis as live_breathing.py, but built
for multi-hour unattended runs where the USB serial link WILL glitch at
least once. Differences that matter for an all-night session:

  * auto-reconnect: a SerialException mid-read no longer kills the run.
    The port is closed, reopened, and capture resumes — every gap is
    logged (to stdout and a .gaps.log) so the disconnects are visible
    afterward instead of silently ending the session.

  * incremental analysis: instead of record-everything-then-replay-once
    at the end (live_breathing.py's flow, which prints nothing for hours
    and loses ALL analysis if it dies), this re-runs the sliding-window
    estimator on the accumulated CSV every --analyze-every seconds and
    appends fresh windows to a .windows.jsonl as they're produced. Kill
    it or crash it at any point and everything up to that moment is saved.

  * heartbeat: a one-line "still alive" print every --heartbeat seconds so
    you can glance at the terminal and know it's running.

The raw CSV is written line-by-line exactly like live_breathing.py, so a
completed (or partial) overnight capture re-analyzes with the same tools
as any other session.

Usage:
    # 8-hour run, analyze the last window batch every 5 min, heartbeat each min
    python overnight_breathing.py COM9 --duration 28800 \
        --analyze-every 300 --heartbeat 60 --outdir data
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
RECONNECT_WAIT_S = 2.0        # pause before reopening after a drop
MAX_CONSECUTIVE_FAILS = 30    # give up only after this many back-to-back reopen failures


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Resilient overnight breathing capture.")
    p.add_argument("port", help="RX serial port (native USB), e.g. COM9")
    p.add_argument("--baud", type=int, default=DEFAULT_BAUD)
    p.add_argument("--duration", type=int, default=28800,
                    help="total seconds to run (default 28800 = 8 hours)")
    p.add_argument("--outdir", default="data", help="output directory for the raw CSV")
    p.add_argument("--analyze-every", type=float, default=300.0,
                    help="re-run sliding-window analysis every N seconds (default 300)")
    p.add_argument("--heartbeat", type=float, default=60.0,
                    help="print a still-alive line every N seconds (default 60)")
    p.add_argument("--window-seconds", type=float, default=DEFAULTS["window_seconds"])
    p.add_argument("--stride-seconds", type=float, default=DEFAULTS["stride_seconds"])
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


def _now() -> str:
    return datetime.now().strftime("%H:%M:%S")


def _analyze(csv_path: Path, config: dict, jsonl_path: Path) -> tuple[int, int, float]:
    """Re-run sliding-window analysis on the CSV so far; rewrite the JSONL.

    Returns (total_windows, valid_windows, last_smoothed_bpm). Analysis is
    idempotent — we recompute the whole file and overwrite the JSONL each
    time, so the file always reflects the full session up to now and a
    mid-write crash can't leave it half-updated (write to tmp, then replace).
    """
    windows: list[dict] = []
    for r in sliding_window_estimate(csv_path, config=config):
        windows.append({k: v for k, v in r.items()
                        if k not in ("respiratory_waveform", "waveform_unfiltered",
                                     "spectrum", "spectrum_freqs", "selected_pairs")})
    tmp = jsonl_path.with_suffix(".jsonl.tmp")
    with tmp.open("w", encoding="utf-8") as f:
        for w in windows:
            f.write(json.dumps(w) + "\n")
    tmp.replace(jsonl_path)
    valid = [w for w in windows if w.get("status") == "ok"]
    last_bpm = windows[-1]["smoothed_bpm"] if windows else float("nan")
    return len(windows), len(valid), last_bpm


def main() -> int:
    args = parse_args()
    outdir = Path(args.outdir).resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    sys.stdout.write("\n=== Overnight breathing capture — session metadata ===\n")
    room = _ask("Room name", required=True)
    dist = _ask("TX-RX distance (ft)", required=True)
    subject = _ask("Subject name", required=True)
    notes = _ask("Notes", default="")

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    stem = f"overnight_{ts}_{_slug(room)}_{_slug(dist)}ft_{_slug(subject)}"
    csv_path = outdir / f"{stem}.csv"
    jsonl_path = outdir / f"{stem}.windows.jsonl"
    gaps_path = outdir / f"{stem}.gaps.log"

    stop = {"flag": False}

    def _sigint(signum, frame):  # noqa: ARG001
        stop["flag"] = True

    signal.signal(signal.SIGINT, _sigint)

    config = {"window_seconds": args.window_seconds, "stride_seconds": args.stride_seconds}

    hours = args.duration / 3600.0
    sys.stdout.write(
        f"\n=== Recording {args.duration}s ({hours:.1f}h) to {csv_path.name} ===\n"
        f"  window={args.window_seconds:.0f}s stride={args.stride_seconds:.0f}s | "
        f"analyze every {args.analyze_every:.0f}s | heartbeat every {args.heartbeat:.0f}s\n"
        f"  auto-reconnect ON — serial drops are logged to {gaps_path.name}, not fatal.\n"
        "  Subject: sit/lie still, breathe normally. Ctrl+C to stop early.\n\n"
    )
    sys.stdout.flush()

    log_f = csv_path.open("w", encoding="utf-8", newline="")
    gaps_f = gaps_path.open("w", encoding="utf-8")
    header_written = False
    total = 0
    disconnects = 0
    consecutive_fails = 0

    t_start = time.monotonic()
    t_end = t_start + args.duration
    t_next_analyze = t_start + args.analyze_every
    t_next_heartbeat = t_start + args.heartbeat
    last_valid = 0
    last_total = 0
    last_bpm = float("nan")

    ser = None
    try:
        while not stop["flag"] and time.monotonic() < t_end:
            # (re)establish the serial link if we don't have one
            if ser is None:
                try:
                    ser = open_rx(args.port, args.baud)
                    consecutive_fails = 0
                except serial.SerialException as e:
                    consecutive_fails += 1
                    msg = f"[{_now()}] reopen failed ({consecutive_fails}): {e}"
                    gaps_f.write(msg + "\n"); gaps_f.flush()
                    if consecutive_fails >= MAX_CONSECUTIVE_FAILS:
                        sys.stdout.write(f"\n  {msg}\n  giving up after "
                                         f"{MAX_CONSECUTIVE_FAILS} failed reopens.\n")
                        break
                    time.sleep(RECONNECT_WAIT_S)
                    continue

            # read one line, surviving a mid-read disconnect
            try:
                raw = ser.readline()
            except (serial.SerialException, OSError) as e:
                disconnects += 1
                msg = (f"[{_now()}] serial dropped after {total} pkts "
                       f"(disconnect #{disconnects}): {e}")
                gaps_f.write(msg + "\n"); gaps_f.flush()
                sys.stdout.write(f"  ! {msg} — reconnecting...\n"); sys.stdout.flush()
                try:
                    ser.close()
                except Exception:
                    pass
                ser = None
                time.sleep(RECONNECT_WAIT_S)
                continue

            if raw:
                line = raw.decode("utf-8", errors="replace").rstrip("\r\n")
                if line:
                    host_ts = datetime.now().isoformat(timespec="microseconds")
                    if line.startswith(HEADER_PREFIX) and not header_written:
                        log_f.write("host_recv_ts," + line + "\n")
                        header_written = True
                    elif line.startswith(CSV_PREFIX):
                        log_f.write(f"{host_ts},{line}\n")
                        total += 1

            now = time.monotonic()

            # heartbeat — prove we're alive without waiting for an analysis pass
            if now >= t_next_heartbeat:
                elapsed = now - t_start
                sys.stdout.write(
                    f"  · [{_now()}] alive — {elapsed/3600:.2f}h in, {total} pkts, "
                    f"{disconnects} disconnects, last smoothed bpm={last_bpm:.1f} "
                    f"({last_valid} valid windows)\n")
                sys.stdout.flush()
                t_next_heartbeat = now + args.heartbeat

            # periodic incremental analysis — crash-safe, always full-session
            if now >= t_next_analyze and total > 0:
                log_f.flush()
                try:
                    last_total, last_valid, last_bpm = _analyze(
                        csv_path, config, jsonl_path)
                    sys.stdout.write(
                        f"  = [{_now()}] analyzed: {last_total} windows, "
                        f"{last_valid} valid, smoothed bpm={last_bpm:.1f} "
                        f"-> {jsonl_path.name}\n")
                except (ValueError, Exception) as e:  # noqa: BLE001
                    # analysis failing must NEVER kill the capture
                    gaps_f.write(f"[{_now()}] analysis skipped: {e}\n"); gaps_f.flush()
                    sys.stdout.write(f"  = [{_now()}] analysis skipped ({e}); "
                                     "capture continues.\n")
                sys.stdout.flush()
                t_next_analyze = now + args.analyze_every
    finally:
        if ser is not None:
            try:
                ser.close()
            except Exception:
                pass
        log_f.flush(); log_f.close()

    # final analysis pass over the complete capture
    sys.stdout.write(f"\n  capture ended — {total} packets, "
                     f"{disconnects} disconnects. Final analysis...\n")
    sys.stdout.flush()
    final_total = final_valid = 0
    final_bpm = float("nan")
    try:
        if total > 0:
            final_total, final_valid, final_bpm = _analyze(csv_path, config, jsonl_path)
    except Exception as e:  # noqa: BLE001
        sys.stderr.write(f"  final analysis failed: {e}\n")

    summary = {
        "csv": csv_path.name,
        "total_packets": total,
        "disconnects": disconnects,
        "duration_requested_s": args.duration,
        "metadata": {"room_name": room, "tx_rx_distance_ft": dist,
                     "subject": subject, "notes": notes},
        "config": config,
        "window_count": final_total,
        "valid_window_count": final_valid,
        "final_smoothed_bpm": final_bpm,
    }
    (outdir / f"{stem}.summary.json").write_text(
        json.dumps(summary, indent=2), encoding="utf-8")
    gaps_f.write(f"[{_now()}] session end — {total} pkts, {disconnects} disconnects\n")
    gaps_f.close()

    sys.stdout.write(
        f"\n=== Summary ===\n"
        f"  packets:            {total}\n"
        f"  disconnects:        {disconnects}\n"
        f"  windows:            {final_total}\n"
        f"  valid (status=ok):  {final_valid}\n"
        f"  final smoothed bpm: {final_bpm:.1f}\n"
        f"  raw CSV:            {csv_path.name}\n"
        f"  per-window JSONL:   {jsonl_path.name}\n"
        f"  disconnect log:     {gaps_path.name}\n"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
