#!/usr/bin/env python3
"""wi-netra health — guided rig calibration (Module 2 onboarding step).

Implements the spec's "sit still for 60 seconds" onboarding calibration as a
command-line flow, producing the empty-vs-occupied SNR reference the apps and
firmware will later use to tell "empty room" apart from "possible apnea".

Two guided phases:
  1. EMPTY     (~30 s): nobody in / near the line-of-sight path.
  2. OCCUPIED  (~60 s): subject seated, still, chest facing the LOS.

Both phases are scored with the same CSCR breathing-band SNR used by the
main pipeline; the midpoint between the two scores becomes the occupancy
threshold. Outputs land in --outdir:

  calib_<ts>_<room>_<dist>ft.empty.csv       raw CSI, empty phase
  calib_<ts>_<room>_<dist>ft.occupied.csv    raw CSI, occupied phase
  calib_<ts>_<room>_<dist>ft.calibration.json  full result
  rig_baseline.json                          canonical latest baseline

Usage:
    python calibrate_rig.py COM<RX_USB_PORT> --outdir ..\\..\\validation\\data

-------------------------------------------------------------------------
STANDARD RIG (Module 9 reference setup — keep every session consistent):
  * Boards at chest height, 1.0-1.2 m off the floor (table / boxes).
  * Antenna ends (notched PCB tips) facing each other, clear line of sight.
  * TX on standalone 5V power; RX -> laptop via the board's NATIVE USB
    connector (VID 303A enumerates as "USB Serial Device"), NOT the CH343
    UART connector.
  * TX-RX distance: see "distance_ft" in rig_baseline.json — set from the
    Module 2 distance sweep (1-3 ft band; sweep data in validation/data).
  * Subject seated between/beside LOS, chest facing the line, still, quiet.
  * No fans, phones or moving people in the LOS during captures.
-------------------------------------------------------------------------
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

try:
    import numpy as np
    import serial
except ImportError:
    sys.stderr.write("deps missing — activate the venv: pip install -r requirements.txt\n")
    sys.exit(1)

from firmware.components.csi_capture.clean_health import (
    drop_null_subcarriers_complex,
    load_complex_session,
)
from firmware.components.dsp_breathing.breathing import _resample_complex_uniform
from firmware.components.dsp_breathing.cscr import (
    _pair_snr,
    compute_cscr,
    select_subcarrier_pairs,
)

CSV_PREFIX = "CSI_DATA,"
HEADER_PREFIX = "type,"
DEFAULT_BAUD = 921600
SAMPLE_RATE_HZ = 10.0
BAND = (0.1, 0.5)
NUM_PAIRS = 20

# Verdict bands for occupied/empty SNR separation.
PASS_RATIO = 2.0
MARGINAL_RATIO = 1.3


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Guided empty-vs-occupied rig calibration.")
    p.add_argument("port", help="RX serial port (native USB), e.g. COM7")
    p.add_argument("--baud", type=int, default=DEFAULT_BAUD)
    p.add_argument("--empty-secs", type=int, default=30)
    p.add_argument("--occupied-secs", type=int, default=60)
    p.add_argument("--outdir", default=os.path.join("..", "..", "validation", "data"))
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
    # Explicit reset pulse so the RX re-prints its CSV header — captures
    # started mid-stream would otherwise produce a headerless CSV that the
    # loader rejects.
    s.dtr = False
    s.rts = True
    time.sleep(0.15)
    s.rts = False
    time.sleep(1.0)
    return s


def record_phase(ser: "serial.Serial", seconds: int, path: Path, label: str) -> int:
    """Record one phase to CSV; returns packet count."""
    sys.stdout.write(f"\n  --- {label}: recording {seconds}s -> {path.name} ---\n")
    sys.stdout.flush()
    total = 0
    header_written = False
    t_end = time.monotonic() + seconds
    next_status = time.monotonic() + 5.0
    with path.open("w", encoding="utf-8", newline="") as f:
        while time.monotonic() < t_end:
            raw = ser.readline()
            if not raw:
                continue
            line = raw.decode("utf-8", errors="replace").rstrip("\r\n")
            if not line:
                continue
            host_ts = datetime.now().isoformat(timespec="microseconds")
            if line.startswith(HEADER_PREFIX) and not header_written:
                f.write("host_recv_ts," + line + "\n")
                header_written = True
                continue
            if not line.startswith(CSV_PREFIX):
                continue
            f.write(f"{host_ts},{line}\n")
            total += 1
            if time.monotonic() >= next_status:
                sys.stdout.write(
                    f"    {max(0, int(t_end - time.monotonic())):3d}s left  packets={total}\n")
                sys.stdout.flush()
                next_status = time.monotonic() + 5.0
    sys.stdout.write(f"    done — {total} packets\n")
    return total


def band_snr(csv_path: Path, pairs: list | None = None):
    """(mean band SNR over CSCR pairs, pairs, kept_idx) for one capture."""
    H_raw, timestamps, _meta = load_complex_session(csv_path)
    H_active, kept_idx = drop_null_subcarriers_complex(H_raw)
    _grid, H_u = _resample_complex_uniform(timestamps, H_active, SAMPLE_RATE_HZ)

    if pairs is None:
        pairs = select_subcarrier_pairs(
            H_u, num_pairs=NUM_PAIRS, breathing_band=BAND, sample_rate=SAMPLE_RATE_HZ)
        if not pairs:
            raise ValueError(f"no viable subcarrier pairs in {csv_path.name}")

    # Pairs are indices into the active-subcarrier matrix; clamp for safety
    # when the two phases kept slightly different subcarrier sets.
    S = H_u.shape[1]
    usable = [(i, j) for (i, j) in pairs if i < S and j < S]
    cscr = compute_cscr(H_u, usable)
    snrs = [
        _pair_snr(cscr[:, k], SAMPLE_RATE_HZ, BAND) for k in range(cscr.shape[1])
    ]
    return float(np.mean(snrs)) if snrs else 0.0, pairs, kept_idx


def main() -> int:
    args = parse_args()
    outdir = Path(args.outdir).resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    sys.stdout.write("\n=== Rig calibration metadata ===\n")
    room = _ask("Room name", required=True)
    dist = _ask("TX-RX distance (ft)", required=True)
    subject = _ask("Subject name (occupied phase)", required=True)
    notes = _ask("Notes (optional)")

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    stem = f"calib_{ts}_{_slug(room)}_{_slug(dist)}ft"
    empty_csv = outdir / f"{stem}.empty.csv"
    occupied_csv = outdir / f"{stem}.occupied.csv"

    try:
        ser = open_rx(args.port, args.baud)
    except serial.SerialException as e:
        sys.stderr.write(f"cannot open {args.port}: {e}\n")
        return 2

    try:
        sys.stdout.write(
            "\n=== PHASE 1 / EMPTY ===\n"
            "  Everyone OUT of the line-of-sight path (leave the room if small).\n")
        input("  Press Enter when the LOS is clear... ")
        n_empty = record_phase(ser, args.empty_secs, empty_csv, "EMPTY")

        sys.stdout.write(
            "\n=== PHASE 2 / OCCUPIED — the 60s onboarding step ===\n"
            "  Subject: sit between/beside the LOS, chest facing the line.\n"
            "  Sit STILL, breathe normally, no talking, no phone.\n")
        input("  Press Enter when the subject is seated and still... ")
        n_occ = record_phase(ser, args.occupied_secs, occupied_csv, "OCCUPIED")
    finally:
        try:
            ser.close()
        except Exception:
            pass

    if n_empty == 0 or n_occ == 0:
        sys.stderr.write(
            "no packets captured — wrong port? (needs the RX native-USB port; "
            "see the USB-vs-COM note in the rig block above)\n")
        return 3

    sys.stdout.write("\n=== Scoring phases ===\n")
    # Pairs are chosen on the occupied phase (where breathing lives) and the
    # SAME pairs are then scored against the empty phase.
    snr_occupied, pairs, _ = band_snr(occupied_csv, pairs=None)
    snr_empty, _, _ = band_snr(empty_csv, pairs=pairs)

    ratio = snr_occupied / max(snr_empty, 1e-9)
    occupancy_threshold = float(np.sqrt(max(snr_empty, 1e-9) * max(snr_occupied, 1e-9)))
    verdict = ("PASS" if ratio >= PASS_RATIO
               else "MARGINAL" if ratio >= MARGINAL_RATIO
               else "FAIL")

    result = {
        "created": datetime.now().isoformat(timespec="seconds"),
        "rig": {
            "room": room,
            "tx_rx_distance_ft": dist,
            "subject": subject,
            "notes": notes,
            "board_height_m": "1.0-1.2",
            "orientation": "antenna ends facing, subject chest facing LOS",
        },
        "phases": {
            "empty": {"csv": empty_csv.name, "seconds": args.empty_secs,
                      "packets": n_empty, "band_snr": snr_empty},
            "occupied": {"csv": occupied_csv.name, "seconds": args.occupied_secs,
                         "packets": n_occ, "band_snr": snr_occupied},
        },
        "thresholds": {
            "occupancy_snr_threshold": occupancy_threshold,
            "separation_ratio": ratio,
            "verdict": verdict,
        },
        "config": {
            "sample_rate_hz": SAMPLE_RATE_HZ,
            "band_hz": list(BAND),
            "num_pairs": NUM_PAIRS,
            "pairs": [list(p) for p in pairs],
        },
    }

    detail_path = outdir / f"{stem}.calibration.json"
    detail_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
    # Canonical "latest baseline" that downstream gating loads by fixed name.
    (outdir / "rig_baseline.json").write_text(
        json.dumps(result, indent=2), encoding="utf-8")

    sys.stdout.write(
        f"\n=== Calibration result ===\n"
        f"  band SNR empty:    {snr_empty:8.2f}\n"
        f"  band SNR occupied: {snr_occupied:8.2f}\n"
        f"  separation ratio:  {ratio:8.2f}x\n"
        f"  occupancy gate:    {occupancy_threshold:8.2f}\n"
        f"  verdict:           {verdict}\n"
        f"  written:           {detail_path.name} + rig_baseline.json\n")
    if verdict == "FAIL":
        sys.stdout.write(
            "  Occupied is not separable from empty — re-seat the rig: shorter\n"
            "  distance, chest facing the LOS, no fans/motion, then re-run.\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
