#!/usr/bin/env python3
r"""
wi-netra — phased baseline+motion capture session with ML training metadata.

Records ONE continuous CSV from the RX port with countdown prompts so the
human (you) can leave the room, let baseline run, come back and walk.
Writes a sidecar .phases.json that includes:
  * a top-level "session" block with room / distance / placement / subject /
    fan / notes captured interactively at the start of each session, and
  * per-phase [start, end, class, activity] entries (class ∈ {empty,
    transition, human, pet}; motion phases also carry an activity label).

Default schedule (override via --leave / --baseline / --motion seconds):
    1. LEAVE        (0..20 s)        — get out of the room
    2. BASELINE     (20..200 s)      — empty-room reference
    3. MOTION       (200..320 s)     — walk normally inside the room
    4. STOP                          — script exits

CSV filename format:
    train_YYYYMMDD_HHMMSS_<room>_<distance>ft_<class>_fan<ON|OFF>.csv
The paired sidecar shares the same stem with `.phases.json`.

Run from project root:
    python run_session.py COM6                                # interactive prompts
    python run_session.py COM6 --cycles 3 --class human --activity walking
    python run_session.py COM6 --class pet --activity random --outdir data\sessions\train
"""
from __future__ import annotations
import argparse, json, signal, statistics, sys, time
from datetime import datetime
from pathlib import Path

try:
    import serial
except ImportError:
    sys.stderr.write("pyserial missing — run: pip install -r requirements.txt\n")
    sys.exit(1)

CSV_PREFIX = "CSI_DATA,"
HEADER_PREFIX = "type,"
DEFAULT_BAUD = 921600


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Phased CSI baseline+motion capture.")
    p.add_argument("port", help="RX serial port, e.g. COM6")
    p.add_argument("--baud", type=int, default=DEFAULT_BAUD)
    p.add_argument("--leave",    type=int, default=20,  help="seconds to leave the room (default 20)")
    p.add_argument("--baseline", type=int, default=180, help="seconds of empty-room baseline used for threshold (default 180 = 3 min)")
    p.add_argument("--empty-extra", type=int, default=0,
                   help="extra empty-room seconds AFTER baseline (T2 false-positive test). 0 = skip.")
    p.add_argument("--motion",   type=int, default=120, help="seconds of walking in room (default 120 = 2 min)")
    # T3 cycles: when --cycles > 0, the --empty-extra and --motion flags are
    # ignored; instead we run N cycles of (empty -> motion -> leave-buffer),
    # with no leave-buffer after the final cycle.
    p.add_argument("--cycles", type=int, default=0,
                   help="run N empty/motion cycles instead of the single empty_extra+motion pair. 0 = disabled.")
    p.add_argument("--cycle-empty",  type=int, default=120, help="empty seconds per cycle (default 120)")
    p.add_argument("--cycle-motion", type=int, default=90,  help="motion seconds per cycle (default 90)")
    p.add_argument("--cycle-leave",  type=int, default=30,  help="leave-buffer seconds between cycles (default 30)")
    p.add_argument("--outdir", default=".", help="dir for train_*.csv + .phases.json")
    # ML training labels — written into each motion phase's JSON entry and used
    # to compose the output filename.
    p.add_argument("--class", dest="cls", default="human",
                   choices=["human", "pet"],
                   help="class label for motion phases (default: human)")
    p.add_argument("--activity", dest="activity", default="walking",
                   choices=["walking", "sitting", "standing", "entering", "random"],
                   help="activity sub-label for motion phases (default: walking)")
    # 6.2.1 acquisition-quality watchdogs. Print a warning (not abort) when the
    # link gets too thin or too dirty. Thresholds chosen from the floor we
    # observed across 6 working-distance sessions (worst yield ~14% = 13 pps,
    # malformed never exceeded 0.7% in clean runs).
    p.add_argument("--min-pps", type=float, default=15.0,
                   help="warn if observed pps stays below this for 30 s (default 15.0)")
    p.add_argument("--max-bad-pct", type=float, default=1.0,
                   help="warn if rolling malformed %% exceeds this for 30 s (default 1.0)")
    return p.parse_args()


def open_rx(port: str, baud: int) -> serial.Serial:
    # Open WITHOUT asserting DTR/RTS. On ESP32-C6 native USB-Serial-JTAG,
    # those modem-control lines are mapped to EN / IO0 by the USB-JTAG
    # firmware; pyserial's default of DTR=True / RTS=True can hold the chip
    # in reset on Windows. The sequence below disables hardware handshake
    # first, then de-asserts DTR/RTS explicitly after open, then sleeps to
    # let the C6 finish booting from the unavoidable open-time blip.
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


def banner(msg: str) -> None:
    line = "=" * max(60, len(msg) + 4)
    sys.stdout.write(f"\n{line}\n  {msg}\n{line}\n")
    sys.stdout.flush()


def _slug(s: str) -> str:
    """Filesystem-safe slug: lowercase alnum + underscore, empty -> 'unknown'."""
    s = (s or "").strip().lower()
    out = "".join(c if c.isalnum() else "_" for c in s).strip("_")
    while "__" in out:
        out = out.replace("__", "_")
    return out or "unknown"


def prompt_metadata() -> dict:
    """Interactively collect session metadata. Blank input keeps defaults for
    optional fields; room_name and tx_rx_distance_ft are required."""
    banner("Session metadata — press Enter to skip optional fields")

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
            sys.stdout.write("    (required — please enter a value)\n")

    def _ask_number(prompt: str, required: bool = False) -> float | None:
        while True:
            raw = _ask(prompt, default=None if required else "", required=required)
            if raw == "":
                return None
            try:
                return float(raw)
            except ValueError:
                sys.stdout.write("    (must be a number)\n")

    def _ask_fan() -> str:
        while True:
            v = _ask("Fan status (on/off)", default="off").lower()
            if v in ("on", "off"):
                return v
            sys.stdout.write("    (must be 'on' or 'off')\n")

    room       = _ask("Room name (e.g. bedroom)", required=True)
    dims       = _ask("Room dimensions (e.g. 12x14 ft)")
    dist_ft    = _ask_number("TX-RX distance (ft)", required=True)
    tx_h_cm    = _ask_number("TX height from floor (cm)")
    rx_h_cm    = _ask_number("RX height from floor (cm)")
    placement  = _ask("Placement description (e.g. clean LOS, module ends facing)")
    fan        = _ask_fan()
    subject    = _ask("Subject name (e.g. abubakar)")
    notes      = _ask("Notes (optional)")

    return {
        "room_name":         room,
        "room_dimensions":   dims,
        "tx_rx_distance_ft": dist_ft,
        "tx_height_cm":      tx_h_cm,
        "rx_height_cm":      rx_h_cm,
        "placement":         placement,
        "fan_status":        fan,
        "subject":           subject,
        "notes":             notes,
    }


def build_filename_stem(ts: str, meta: dict, cls: str) -> str:
    """train_YYYYMMDD_HHMMSS_<room>_<distance>ft_<class>_fan<ON|OFF>"""
    room = _slug(meta.get("room_name", ""))
    dist = meta.get("tx_rx_distance_ft")
    try:
        dist_str = f"{int(round(float(dist)))}ft"
    except (TypeError, ValueError):
        dist_str = "distUNK"
    fan = "ON" if str(meta.get("fan_status", "")).lower() == "on" else "OFF"
    return f"train_{ts}_{room}_{dist_str}_{cls}_fan{fan}"


def phase_labels(name: str, cls: str, activity: str) -> dict:
    """Map phase name to {class[, activity]} for the sidecar."""
    if name.startswith("motion"):
        return {"class": cls, "activity": activity}
    if name.startswith("leave"):
        return {"class": "transition"}
    if name == "baseline" or name.startswith("empty"):
        return {"class": "empty"}
    return {}


def main() -> int:
    args = parse_args()
    outdir = Path(args.outdir).resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    # Collect training metadata before opening the serial port so aborts here
    # don't leave a half-open COM handle around.
    metadata = prompt_metadata()

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    stem = build_filename_stem(ts, metadata, args.cls)
    csv_path = outdir / f"{stem}.csv"
    json_path = outdir / f"{stem}.phases.json"

    # Banner is printed AFTER the schedule is built (see below) so the
    # printed total accurately reflects --cycles / --empty-extra.
    pending_banner_path = csv_path

    stop = {"flag": False}
    def _sigint(signum, frame):  # noqa: ARG001
        stop["flag"] = True
    signal.signal(signal.SIGINT, _sigint)

    try:
        ser = open_rx(args.port, args.baud)
    except serial.SerialException as e:
        sys.stderr.write(f"cannot open {args.port}: {e}\n")
        return 2

    log_f = csv_path.open("w", encoding="utf-8", newline="")
    header_written = False
    total = 0
    bad = 0
    last_rx = None
    intervals: list[float] = []
    # 6.2.1 watchdogs: how many consecutive 5-s status ticks we've spent
    # below --min-pps or above --max-bad-pct. We emit a one-line warning
    # the first time either streak crosses 6 ticks (30 s sustained) and
    # again every 30 s while the condition persists, then reset on recovery.
    low_pps_streak = 0
    high_bad_streak = 0
    warn_low_pps_at = 0
    warn_high_bad_at = 0
    recent_bad = 0
    recent_total = 0
    # Phase boundaries — host wall-clock ISO strings.
    phases: list[dict] = []
    session_start = datetime.now().isoformat(timespec="microseconds")

    def phase_change(name: str) -> str:
        ts_iso = datetime.now().isoformat(timespec="microseconds")
        if phases:
            phases[-1]["end"] = ts_iso
        entry = {"name": name, "start": ts_iso, "end": None}
        entry.update(phase_labels(name, args.cls, args.activity))
        phases.append(entry)
        return ts_iso

    schedule = [
        ("leave",    args.leave,    "LEAVE THE ROOM NOW — recording starts but ignore these seconds"),
        ("baseline", args.baseline, "BASELINE — empty room.  STAY OUT.  Just collecting reference data."),
    ]
    if args.cycles > 0:
        # T3 multi-cycle schedule. Generates empty_K -> motion_K -> leave_K
        # for K=1..N, omitting the final leave buffer.
        for k in range(1, args.cycles + 1):
            schedule.append((
                f"empty_{k}", args.cycle_empty,
                f"CYCLE {k}/{args.cycles}  EMPTY — stay OUT of the room ({args.cycle_empty}s)."
            ))
            schedule.append((
                f"motion_{k}", args.cycle_motion,
                f"CYCLE {k}/{args.cycles}  MOTION — come IN and walk normally ({args.cycle_motion}s)."
            ))
            if k < args.cycles:
                schedule.append((
                    f"leave_{k}", args.cycle_leave,
                    f"CYCLE {k}/{args.cycles}  LEAVE BUFFER — walk OUT now ({args.cycle_leave}s)."
                ))
    else:
        if args.empty_extra > 0:
            schedule.append(
                ("empty_extra", args.empty_extra,
                 "EMPTY_EXTRA — keep staying out.  False-positive test segment.")
            )
        if args.motion > 0:
            schedule.append(
                ("motion", args.motion,
                 "MOTION — come back in and walk around normally.")
            )

    total_s = sum(d for _, d, _ in schedule)
    banner(f"wi-netra capture session — writing to {pending_banner_path.name}")
    sys.stdout.write(f"  phases: {' -> '.join(n for n, _, _ in schedule)}\n")
    sys.stdout.write(f"  total run time: ~{total_s/60:.1f} min\n\n")
    sys.stdout.flush()

    try:
        for phase_name, dur, prompt in schedule:
            phase_change(phase_name)
            banner(f"[phase] {phase_name.upper()} ({dur}s) — {prompt}")
            phase_end = time.monotonic() + dur
            next_status = time.monotonic() + 5.0
            while not stop["flag"] and time.monotonic() < phase_end:
                raw = ser.readline()
                if not raw:
                    # keep status emission alive even if serial is quiet
                    if time.monotonic() >= next_status:
                        remaining = max(0, int(phase_end - time.monotonic()))
                        sys.stdout.write(f"  [{phase_name}] {remaining:3d}s left  total={total}\n")
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
                    log_f.write("host_recv_ts,phase," + line + "\n")
                    log_f.flush()
                    header_written = True
                    continue
                if not line.startswith(CSV_PREFIX):
                    continue
                if not header_written:
                    log_f.write(
                        "host_recv_ts,phase,type,seq,mac,rssi,rate,noise_floor,"
                        "fft_gain,agc_gain,channel,local_timestamp,sig_len,"
                        "rx_format,len,first_word,data\n"
                    )
                    header_written = True
                log_f.write(f"{host_ts},{phase_name},{line}\n")
                total += 1
                # quick badness check (uses the first_word_invalid column position)
                head = line.split(',"[', 1)[0]
                cols = head.split(",")
                if len(cols) >= 14:
                    try:
                        if int(cols[13]) != 0:
                            bad += 1
                    except ValueError:
                        bad += 1
                now = time.monotonic()
                if last_rx is not None:
                    intervals.append(now - last_rx)
                last_rx = now
                if time.monotonic() >= next_status:
                    remaining = max(0, int(phase_end - time.monotonic()))
                    if intervals:
                        recent = intervals[-200:]
                        pps = 1.0 / (sum(recent) / len(recent))
                    else:
                        pps = 0.0
                    # Rolling malformed % over packets received since the last
                    # status tick — gives a per-window read of link cleanliness.
                    win_total = total - recent_total
                    win_bad = bad - recent_bad
                    win_bad_pct = (100.0 * win_bad / win_total) if win_total else 0.0
                    recent_total = total
                    recent_bad = bad
                    sys.stdout.write(
                        f"  [{phase_name}] {remaining:3d}s left  total={total}  "
                        f"pps~{pps:5.1f}  bad={bad}\n"
                    )
                    sys.stdout.flush()
                    # min-pps watchdog (Task 1.5)
                    if pps > 0 and pps < args.min_pps:
                        low_pps_streak += 1
                    else:
                        low_pps_streak = 0
                        warn_low_pps_at = 0
                    if low_pps_streak >= 6 and (
                        warn_low_pps_at == 0 or (time.monotonic() - warn_low_pps_at) >= 30
                    ):
                        sys.stdout.write(
                            f"  ! [watchdog] sustained pps {pps:.1f} < {args.min_pps:.1f} "
                            f"for {low_pps_streak*5}s — link is thin, check antennas / "
                            f"channel / nearby interferers.\n"
                        )
                        sys.stdout.flush()
                        warn_low_pps_at = time.monotonic()
                    # malformed-rate watchdog (Task 3)
                    if win_total >= 20 and win_bad_pct > args.max_bad_pct:
                        high_bad_streak += 1
                    else:
                        high_bad_streak = 0
                        warn_high_bad_at = 0
                    if high_bad_streak >= 6 and (
                        warn_high_bad_at == 0 or (time.monotonic() - warn_high_bad_at) >= 30
                    ):
                        sys.stdout.write(
                            f"  ! [watchdog] sustained malformed {win_bad_pct:.1f}% > "
                            f"{args.max_bad_pct:.1f}% for {high_bad_streak*5}s — "
                            f"frames corrupted on the air or in the CSI callback.\n"
                        )
                        sys.stdout.flush()
                        warn_high_bad_at = time.monotonic()
                    next_status = time.monotonic() + 5.0
            if stop["flag"]:
                break
        # Close out the last phase
        if phases:
            phases[-1]["end"] = datetime.now().isoformat(timespec="microseconds")
    finally:
        try:
            ser.close()
        except Exception:
            pass
        log_f.flush()
        log_f.close()

    # Sidecar summary
    duration = (datetime.fromisoformat(phases[-1]["end"]) - datetime.fromisoformat(session_start)).total_seconds() if phases else 0.0
    avg_pps = (total / duration) if duration > 0 else 0.0
    pct_bad = (100.0 * bad / total) if total else 0.0
    summary = {
        "csv": csv_path.name,
        "session": {
            **metadata,
            "class":    args.cls,
            "activity": args.activity,
        },
        "session_start": session_start,
        "session_end": phases[-1]["end"] if phases else None,
        "total_packets": total,
        "malformed_packets": bad,
        "malformed_pct": round(pct_bad, 3),
        "avg_pps": round(avg_pps, 2),
        "phases": phases,
        "schedule": {
            "leave_s": args.leave,
            "baseline_s": args.baseline,
            "empty_extra_s": args.empty_extra,
            "motion_s": args.motion,
            "cycles": args.cycles,
            "cycle_empty_s": args.cycle_empty,
            "cycle_motion_s": args.cycle_motion,
            "cycle_leave_s": args.cycle_leave,
        },
    }
    json_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    banner(f"[done] {total} packets  ({pct_bad:.1f}% malformed)  avg {avg_pps:.1f} pkt/s")
    sys.stdout.write(f"  CSV:    {csv_path}\n")
    sys.stdout.write(f"  phases: {json_path}\n")
    sys.stdout.write(f"\nNow analyze with:\n  python analyze_motion.py {csv_path.name}\n")
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
