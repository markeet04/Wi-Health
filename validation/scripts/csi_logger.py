#!/usr/bin/env python3
"""
wi-netra Step 0 — laptop-side CSI logger.

Reads CSV lines from the RX board (rx_csi_recv) over USB serial,
appends them to a timestamped log file with a host-side receive timestamp,
and prints live stats every ~2 s.

Usage:
    python csi_logger.py COM7              # Windows
    python csi_logger.py /dev/ttyUSB0      # Linux
    python csi_logger.py --baud 921600 --port COM7

Stats printed every 2 s:
    - packets/sec over the window
    - mean + stdev of inter-packet interval (rate stability)
    - count and % of malformed/dropped frames in the window

Exits cleanly on Ctrl-C with a summary of total packets and duration.
"""
from __future__ import annotations

import argparse
import csv
import math
import signal
import statistics
import sys
import time
from datetime import datetime
from pathlib import Path

try:
    import serial  # type: ignore
except ImportError:
    sys.stderr.write(
        "pyserial is not installed. Activate the venv and run:\n"
        "    pip install -r requirements.txt\n"
    )
    sys.exit(1)


CSV_PREFIX = "CSI_DATA,"
HEADER_PREFIX = "type,"
DEFAULT_BAUD = 921600
STATS_INTERVAL_S = 2.0


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Log ESP32-C6 CSI CSV over serial.")
    p.add_argument("port", nargs="?", help="Serial port, e.g. COM7 or /dev/ttyUSB0")
    p.add_argument("--port", dest="port_opt", help="Same as positional port.")
    p.add_argument("--baud", type=int, default=DEFAULT_BAUD,
                   help=f"Serial baud (default {DEFAULT_BAUD}).")
    p.add_argument("--outdir", default=".", help="Directory for the log CSV.")
    args = p.parse_args()
    args.port = args.port or args.port_opt
    if not args.port:
        p.error("serial port is required (positional or --port).")
    return args


def is_data_line(line: str) -> bool:
    return line.startswith(CSV_PREFIX)


def is_header_line(line: str) -> bool:
    return line.startswith(HEADER_PREFIX)


def malformed_from_line(line: str) -> bool:
    """
    A frame is considered malformed if:
      - it is shorter than expected (no CSI data section), or
      - the device-side first_word_invalid flag is set.

    The CSV row format for ESP32-C6 ends with:
        ..., len, first_word, "[i0,q0,i1,q1,...]"
    We look at the second-to-last numeric column before the bracket-quoted CSI
    array.
    """
    # Split off the quoted CSI array first.
    bracket = line.find(',"[')
    if bracket < 0:
        return True
    head = line[:bracket]
    fields = head.split(",")
    if len(fields) < 4:
        return True
    try:
        first_word_invalid = int(fields[-1])
    except ValueError:
        return True
    return first_word_invalid != 0


class Stats:
    def __init__(self) -> None:
        self.window_packets = 0
        self.window_malformed = 0
        self.window_intervals: list[float] = []
        self.last_rx_t: float | None = None
        self.window_start = time.monotonic()
        self.total_packets = 0
        self.total_malformed = 0
        self.session_start = time.monotonic()

    def record(self, malformed: bool) -> None:
        now = time.monotonic()
        if self.last_rx_t is not None:
            self.window_intervals.append(now - self.last_rx_t)
        self.last_rx_t = now
        self.window_packets += 1
        self.total_packets += 1
        if malformed:
            self.window_malformed += 1
            self.total_malformed += 1

    def maybe_emit(self) -> None:
        elapsed = time.monotonic() - self.window_start
        if elapsed < STATS_INTERVAL_S:
            return
        pps = self.window_packets / elapsed if elapsed > 0 else 0.0
        if self.window_intervals:
            mean_dt_ms = statistics.mean(self.window_intervals) * 1000
            std_dt_ms = (statistics.stdev(self.window_intervals) * 1000
                         if len(self.window_intervals) > 1 else 0.0)
        else:
            mean_dt_ms = float("nan")
            std_dt_ms = float("nan")
        pct_bad = (100.0 * self.window_malformed / self.window_packets
                   if self.window_packets else 0.0)
        sys.stdout.write(
            f"[stats] {pps:6.1f} pkt/s  "
            f"dt={mean_dt_ms:6.2f}±{std_dt_ms:5.2f} ms  "
            f"bad={self.window_malformed}/{self.window_packets} ({pct_bad:4.1f}%)\n"
        )
        sys.stdout.flush()
        self.window_packets = 0
        self.window_malformed = 0
        self.window_intervals.clear()
        self.window_start = time.monotonic()

    def final_report(self) -> str:
        duration = time.monotonic() - self.session_start
        avg_pps = self.total_packets / duration if duration > 0 else 0.0
        pct_bad = (100.0 * self.total_malformed / self.total_packets
                   if self.total_packets else 0.0)
        return (
            f"\n[done] packets={self.total_packets} "
            f"malformed={self.total_malformed} ({pct_bad:.2f}%) "
            f"duration={duration:.1f}s avg={avg_pps:.1f} pkt/s\n"
        )


def open_log(outdir: Path) -> tuple[Path, "object"]:
    outdir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    path = outdir / f"csi_log_{ts}.csv"
    f = path.open("w", encoding="utf-8", newline="")
    return path, f


def main() -> int:
    args = parse_args()
    outdir = Path(args.outdir).resolve()
    log_path, log_file = open_log(outdir)

    sys.stdout.write(
        f"[csi_logger] port={args.port} baud={args.baud}\n"
        f"[csi_logger] writing -> {log_path}\n"
    )
    sys.stdout.flush()

    stop = {"flag": False}
    def _handle_sigint(signum, frame):  # noqa: ARG001
        stop["flag"] = True
    signal.signal(signal.SIGINT, _handle_sigint)

    stats = Stats()
    header_written = False

    # Open WITHOUT asserting DTR/RTS. On ESP32-C6 native USB-Serial-JTAG,
    # those modem-control lines are mapped to EN / IO0 by the USB-JTAG
    # firmware; pyserial's default of DTR=True / RTS=True can hold the chip
    # in reset on Windows.
    try:
        ser = serial.Serial()
        ser.port = args.port
        ser.baudrate = args.baud
        ser.dsrdtr = False
        ser.rtscts = False
        ser.timeout = 0.2
        ser.open()
        ser.dtr = False
        ser.rts = False
        time.sleep(1.0)  # let the chip finish booting after the open-time reset.
    except serial.SerialException as e:
        sys.stderr.write(f"[csi_logger] cannot open {args.port}: {e}\n")
        log_file.close()
        return 2

    try:
        while not stop["flag"]:
            raw = ser.readline()
            if not raw:
                stats.maybe_emit()
                continue
            try:
                line = raw.decode("utf-8", errors="replace").rstrip("\r\n")
            except Exception:
                continue
            if not line:
                continue

            host_ts = datetime.now().isoformat(timespec="microseconds")

            if is_header_line(line) and not header_written:
                log_file.write("host_recv_ts," + line + "\n")
                log_file.flush()
                header_written = True
                continue

            if is_data_line(line):
                if not header_written:
                    # No header captured (board already running); synthesize.
                    log_file.write(
                        "host_recv_ts,type,seq,mac,rssi,rate,noise_floor,"
                        "fft_gain,agc_gain,channel,local_timestamp,sig_len,"
                        "rx_format,len,first_word,data\n"
                    )
                    header_written = True
                log_file.write(host_ts + "," + line + "\n")
                stats.record(malformed=malformed_from_line(line))
            # else: log/debug noise from the board — ignored.

            stats.maybe_emit()
    finally:
        try:
            ser.close()
        except Exception:
            pass
        log_file.flush()
        log_file.close()
        sys.stdout.write(stats.final_report())
        sys.stdout.write(f"[csi_logger] saved -> {log_path}\n")
        sys.stdout.flush()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
