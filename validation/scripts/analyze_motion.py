#!/usr/bin/env python3
"""
wi-netra Step 1 — variance-based presence detector.

Inputs:  csi_log_*.csv + matching .phases.json from run_session.py.
Output:  per-window verdict, accuracy vs ground-truth phase labels,
         and an optional PNG plot of motion energy + threshold.

Algorithm:
  1. Parse the "data" array (int8 I/Q pairs) -> complex CSI per packet.
  2. Compute amplitude |H| per subcarrier.
  3. Drop "null" subcarriers — those whose median amplitude across the
     whole capture is near zero (DC + guard bands).
  4. Window packets by host_recv_ts into 1-second windows.
  5. Per-window motion energy = mean(var(|H_k|)) over active subcarriers k.
     Variance is what jumps when a body moves through the channel.
  6. Threshold: median + k * MAD over BASELINE windows (k=4 by default).
     Robust to outliers; doesn't need a Gaussian assumption.
  7. Decision smoothing: a window is PRESENT iff >= N_OF_M windows in the
     trailing M-window buffer (incl. current) cross the threshold.
  8. Score against the phase labels in the sidecar JSON.
"""
from __future__ import annotations
import argparse, json, sys
from pathlib import Path
from typing import Optional

import numpy as np
import pandas as pd

CSV_PREFIX = "CSI_DATA"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="CSI presence detector.")
    p.add_argument("csv", help="csi_log_*.csv from run_session.py")
    p.add_argument("--phases", help="phases.json sidecar (auto-detected if omitted)")
    # Defaults tuned for ~10 pps capture (channel 6 with neighbour Wi-Fi).
    # Also work fine for ~80 pps captures — 5 s windows just contain more
    # samples then.
    p.add_argument("--window-s",   type=float, default=5.0, help="seconds per analysis window (default 5.0)")
    p.add_argument("--mad-k",      type=float, default=2.5, help="threshold = median + k * MAD (default 2.5)")
    p.add_argument("--smooth-n",   type=int,   default=2,   help="N of last M windows must be motion (default 2)")
    p.add_argument("--smooth-m",   type=int,   default=3,   help="M = sliding window length (default 3)")
    p.add_argument("--plot",       action="store_true", help="save PNG plot next to CSV")
    p.add_argument("--null-thresh", type=float, default=2.0,
                   help="subcarriers with median amplitude < this are dropped (default 2.0)")
    p.add_argument("--threshold-from", choices=["baseline", "all-empty"], default="baseline",
                   help="which windows compute the threshold from. 'baseline' = only the initial baseline phase. "
                        "'all-empty' = baseline + every empty_N + empty_extra phase combined (tests whether the "
                        "algorithm works given a drift-aware baseline).")
    p.add_argument("--threshold-phases", default=None,
                   help="comma-separated list of phase names whose windows compute the threshold. "
                        "Overrides --threshold-from when set. Example: --threshold-phases empty_2,empty_3 "
                        "(tests algorithm in a single noise regime).")
    p.add_argument("--score-phases", default=None,
                   help="comma-separated list of phase names to RESTRICT scoring/timeline to. "
                        "Useful with --threshold-phases to test a regime-isolated subset.")
    return p.parse_args()


def parse_data_field(s: str) -> Optional[np.ndarray]:
    """Parse the bracketed I/Q array. Returns a flat int8 array, or None on error."""
    if not isinstance(s, str):
        return None
    s = s.strip()
    if not s.startswith("["):
        return None
    if s.endswith("]"):
        body = s[1:-1]
    else:
        # Truncated row (rare); still try to salvage what's there.
        body = s[1:].rstrip("]")
    try:
        arr = np.fromstring(body, sep=",", dtype=np.int16)
    except Exception:
        return None
    if arr.size % 2 != 0:
        arr = arr[:-1]  # drop trailing odd byte
    return arr


def to_complex(iq: np.ndarray) -> np.ndarray:
    """Flat [I0,Q0,I1,Q1,...] -> complex H[k]."""
    iq = iq.reshape(-1, 2)
    return iq[:, 0].astype(np.float32) + 1j * iq[:, 1].astype(np.float32)


def load_phases(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    args = parse_args()
    csv_path = Path(args.csv).resolve()
    if not csv_path.exists():
        sys.stderr.write(f"CSV not found: {csv_path}\n"); return 2
    phases_path = Path(args.phases).resolve() if args.phases else \
        csv_path.with_suffix("").with_suffix(".phases.json")
    if not phases_path.exists():
        # try replacing the trailing .csv with .phases.json
        alt = Path(str(csv_path)[:-4] + ".phases.json")
        if alt.exists():
            phases_path = alt
        else:
            sys.stderr.write(f"phases sidecar not found near CSV: {phases_path}\n"); return 2

    phases = load_phases(phases_path)
    sys.stdout.write(f"[load] csv={csv_path.name} ({csv_path.stat().st_size/1e6:.1f} MB)\n")
    sys.stdout.write(f"[load] phases={phases_path.name}  packets={phases.get('total_packets')}  pps={phases.get('avg_pps')}\n")

    # ---- Read CSV ----
    df = pd.read_csv(csv_path, low_memory=False, on_bad_lines="skip")
    df = df[df["type"] == "CSI_DATA"]
    # first_word can be string-typed if any row was corrupted (e.g. boot-banner
    # text bled into the field on the first packet after a chip reset). Coerce
    # to numeric so the comparison works regardless.
    fw = pd.to_numeric(df["first_word"], errors="coerce")
    df = df[fw == 0]  # drop frames the device flagged invalid
    if df.empty:
        sys.stderr.write("no valid rows after filtering\n"); return 3
    df["host_recv_ts"] = pd.to_datetime(df["host_recv_ts"], errors="coerce")
    df = df.dropna(subset=["host_recv_ts"])
    sys.stdout.write(f"[load] {len(df)} valid rows  span = {df['host_recv_ts'].iloc[0]} .. {df['host_recv_ts'].iloc[-1]}\n")

    # ---- Parse CSI arrays ----
    parsed = df["data"].map(parse_data_field)
    keep = parsed.notna()
    df = df.loc[keep].copy()
    parsed = parsed.loc[keep]

    # Build a (N, K) matrix of complex H[n, k]. Trim to common K.
    lengths = parsed.map(len).to_numpy()
    K = int(np.median(lengths))
    if K < 8:
        sys.stderr.write(f"CSI vectors too short (K={K}) — something is wrong\n"); return 3
    sys.stdout.write(f"[csi] N={len(df)} packets, median I/Q-pair vector length = {K//2}\n")

    iq_mat = np.zeros((len(df), K), dtype=np.int16)
    for i, arr in enumerate(parsed.to_numpy()):
        a = arr[:K]
        iq_mat[i, :a.size] = a
    H = iq_mat[:, 0::2].astype(np.float32) + 1j * iq_mat[:, 1::2].astype(np.float32)
    amp = np.abs(H)  # (N, S) — S subcarriers
    S = amp.shape[1]
    sys.stdout.write(f"[csi] amplitude matrix shape: {amp.shape}\n")

    # ---- Drop null subcarriers (DC, guard) ----
    med_per_sub = np.median(amp, axis=0)
    active = med_per_sub > args.null_thresh
    n_active = int(active.sum())
    sys.stdout.write(f"[csi] active subcarriers: {n_active}/{S}  (kept those with median |H| > {args.null_thresh})\n")
    if n_active < 4:
        sys.stderr.write("not enough active subcarriers — null threshold may be too high\n"); return 3
    amp_a = amp[:, active]

    # ---- Window by time ----
    ts = df["host_recv_ts"].to_numpy().astype("datetime64[ns]")
    t0 = ts[0]
    secs = (ts - t0).astype("timedelta64[ms]").astype(np.int64) / 1000.0
    win_id = np.floor(secs / args.window_s).astype(np.int64)
    n_windows = int(win_id.max()) + 1
    sys.stdout.write(f"[win] {n_windows} windows of {args.window_s:.1f} s\n")

    # Build per-window motion energy = mean(var_n(|H[n,k]|)) over k
    # Use grouped variance.
    motion = np.full(n_windows, np.nan, dtype=np.float64)
    pps    = np.zeros(n_windows, dtype=np.int32)
    # Use pandas groupby for speed/clarity.
    grp = pd.DataFrame({"w": win_id}).groupby("w").indices
    for w, idx in grp.items():
        if len(idx) < 4:
            pps[w] = len(idx)
            continue
        v = amp_a[idx, :].var(axis=0, ddof=1)
        motion[w] = float(np.nanmean(v))
        pps[w] = len(idx)

    # ---- Per-window phase labels from sidecar ----
    phase_label = np.array(["?"] * n_windows, dtype=object)
    phase_starts: list[pd.Timestamp] = []
    for ph in phases["phases"]:
        if not ph.get("start") or not ph.get("end"):
            continue
        s = pd.to_datetime(ph["start"]).to_datetime64()
        e = pd.to_datetime(ph["end"]).to_datetime64()
        s_w = max(0, int(((s - t0).astype("timedelta64[ms]").astype(np.int64) / 1000.0) // args.window_s))
        e_w = min(n_windows, int(((e - t0).astype("timedelta64[ms]").astype(np.int64) / 1000.0) // args.window_s) + 1)
        phase_label[s_w:e_w] = ph["name"]
        phase_starts.append((ph["name"], s_w, e_w))

    # ---- Threshold ----
    if args.threshold_phases:
        wanted = {p.strip() for p in args.threshold_phases.split(",") if p.strip()}
        is_empty_phase = np.array([str(n) in wanted for n in phase_label])
        src_label = f"explicit phases {sorted(wanted)}"
    elif args.threshold_from == "all-empty":
        is_empty_phase = np.array([
            (str(n) == "baseline") or str(n).startswith("empty")
            for n in phase_label
        ])
        src_label = "all-empty (baseline + every empty_N)"
    else:
        is_empty_phase = (phase_label == "baseline")
        src_label = "baseline only"
    base_mask = is_empty_phase & np.isfinite(motion)
    if base_mask.sum() < 5:
        sys.stderr.write(f"not enough {args.threshold_from} windows to compute a threshold\n"); return 3
    base_vals = motion[base_mask]
    med = float(np.median(base_vals))
    mad = float(np.median(np.abs(base_vals - med)))
    thr = med + args.mad_k * mad
    sys.stdout.write(
        f"[thr] source={src_label}  n={base_mask.sum()}  median={med:.2f}  MAD={mad:.2f}  "
        f"threshold (median + {args.mad_k}*MAD)={thr:.2f}\n"
    )

    # ---- Per-window raw motion bit + smoothed PRESENT ----
    raw = (motion > thr).astype(np.int8)
    raw[~np.isfinite(motion)] = -1  # mark windows with too few packets
    smooth = np.zeros(n_windows, dtype=np.int8)
    valid_buf: list[int] = []
    for w in range(n_windows):
        r = raw[w]
        if r >= 0:
            valid_buf.append(r)
            if len(valid_buf) > args.smooth_m:
                valid_buf = valid_buf[-args.smooth_m:]
            smooth[w] = 1 if sum(valid_buf) >= args.smooth_n else 0
        else:
            smooth[w] = smooth[w-1] if w > 0 else 0

    # ---- Scoring against phase labels ----
    # ground_truth: any phase whose name starts with "motion"  = PRESENT (1)
    #               any phase named "baseline" or starting with "empty" = EMPTY (0)
    #               any "leave*" phase = ignore (transition buffer)
    truth = np.full(n_windows, -1, dtype=np.int8)
    for w in range(n_windows):
        name = str(phase_label[w])
        if name == "baseline" or name.startswith("empty"):
            truth[w] = 0
        elif name.startswith("motion"):
            truth[w] = 1
        # leave*, "?" -> stays -1 (ignored from scoring)
    if args.score_phases:
        wanted_s = {p.strip() for p in args.score_phases.split(",") if p.strip()}
        score_phase_mask = np.array([str(n) in wanted_s for n in phase_label])
        truth = np.where(score_phase_mask, truth, -1).astype(np.int8)
    mask = (truth >= 0) & np.isfinite(motion)
    if mask.sum() > 0:
        correct = int((smooth[mask] == truth[mask]).sum())
        acc = 100.0 * correct / int(mask.sum())
        # confusion
        tp = int(((smooth == 1) & (truth == 1) & mask).sum())
        tn = int(((smooth == 0) & (truth == 0) & mask).sum())
        fp = int(((smooth == 1) & (truth == 0) & mask).sum())
        fn = int(((smooth == 0) & (truth == 1) & mask).sum())
        sys.stdout.write(
            f"\n[score] accuracy: {acc:.1f}%  ({correct}/{int(mask.sum())} windows)\n"
            f"        TP={tp}  TN={tn}  FP={fp}  FN={fn}\n"
        )
    else:
        sys.stdout.write("\n[score] no labeled windows — skipping accuracy\n")

    # ---- Phase-level verdict (majority of smoothed flag per phase) ----
    sys.stdout.write("\n[phase verdicts]\n")
    for name, s_w, e_w in phase_starts:
        seg = smooth[s_w:e_w]
        if seg.size == 0:
            continue
        present_frac = 100.0 * float((seg == 1).sum()) / seg.size
        if name.startswith("motion"):
            expected = "PRESENT"
        elif name == "baseline" or name.startswith("empty"):
            expected = "EMPTY"
        else:
            expected = "ignore"
        verdict = "PRESENT" if present_frac >= 50.0 else "EMPTY"
        ok = "  ✓" if expected in (verdict, "ignore") else "  ✗"
        sys.stdout.write(
            f"  {name:10s} windows={seg.size:4d}  present={present_frac:5.1f}%  "
            f"verdict={verdict:7s}  expected={expected}{ok}\n"
        )

    # ---- Cycle rollup (T3): aggregate all empty_N and motion_N phases ----
    cycle_phases = [(n, s, e) for n, s, e in phase_starts
                    if (n.startswith("empty_") or n.startswith("motion_"))]
    if cycle_phases:
        sys.stdout.write("\n[cycle rollup]\n")
        total_empty_w  = total_empty_fp = 0
        total_motion_w = total_motion_tp = 0
        # Per-cycle (find max cycle number)
        max_k = 0
        for n, _, _ in cycle_phases:
            try:
                k = int(n.split("_")[-1])
                max_k = max(max_k, k)
            except ValueError:
                pass
        for k in range(1, max_k + 1):
            e_segs = [(s, e) for n, s, e in cycle_phases if n == f"empty_{k}"]
            m_segs = [(s, e) for n, s, e in cycle_phases if n == f"motion_{k}"]
            e_w = sum(e - s for s, e in e_segs); e_fp = sum(int((smooth[s:e] == 1).sum()) for s, e in e_segs)
            m_w = sum(e - s for s, e in m_segs); m_tp = sum(int((smooth[s:e] == 1).sum()) for s, e in m_segs)
            total_empty_w  += e_w; total_empty_fp  += e_fp
            total_motion_w += m_w; total_motion_tp += m_tp
            if e_w + m_w == 0:
                continue
            fp_rate = (100.0 * e_fp / e_w) if e_w else float("nan")
            tp_rate = (100.0 * m_tp / m_w) if m_w else float("nan")
            sys.stdout.write(
                f"  cycle {k}:  empty windows={e_w:3d}  FP={e_fp:3d} ({fp_rate:5.1f}%)   "
                f"motion windows={m_w:3d}  TP={m_tp:3d} ({tp_rate:5.1f}%)\n"
            )
        if total_empty_w + total_motion_w > 0:
            tot_fp = (100.0 * total_empty_fp / total_empty_w) if total_empty_w else float("nan")
            tot_tp = (100.0 * total_motion_tp / total_motion_w) if total_motion_w else float("nan")
            sys.stdout.write(
                f"  ALL:     empty windows={total_empty_w:3d}  FP={total_empty_fp:3d} ({tot_fp:5.1f}%)   "
                f"motion windows={total_motion_w:3d}  TP={total_motion_tp:3d} ({tot_tp:5.1f}%)\n"
            )

    # ---- Compact ASCII timeline ----
    sys.stdout.write("\n[timeline] one char per window — '.' empty, '#' present, '_' too few pkts\n  ")
    chars = []
    for w in range(n_windows):
        if not np.isfinite(motion[w]):
            chars.append("_")
        else:
            chars.append("#" if smooth[w] == 1 else ".")
    sys.stdout.write("".join(chars) + "\n")
    sys.stdout.write("  phases: ")
    for w in range(n_windows):
        name = str(phase_label[w])
        if name.startswith("leave"):
            c = "L"
        elif name == "baseline":
            c = "B"
        elif name.startswith("empty"):
            c = "E"
        elif name.startswith("motion"):
            c = "M"
        else:
            c = " "
        sys.stdout.write(c)
    sys.stdout.write("\n")

    # ---- Plot ----
    if args.plot:
        try:
            import matplotlib
            matplotlib.use("Agg")
            import matplotlib.pyplot as plt
            fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 6), sharex=True)
            ws = np.arange(n_windows) * args.window_s
            ax1.plot(ws, motion, lw=0.8, label="motion energy")
            ax1.axhline(thr, color="r", lw=0.8, ls="--", label=f"threshold ({thr:.2f})")
            def phase_color(n: str) -> str:
                if n == "baseline":         return "lightgreen"
                if n.startswith("empty"):   return "palegreen"
                if n.startswith("motion"):  return "salmon"
                if n.startswith("leave"):   return "gainsboro"
                return "white"
            for name, s_w, e_w in phase_starts:
                color = phase_color(name)
                ax1.axvspan(s_w*args.window_s, e_w*args.window_s, alpha=0.25, color=color, label=name)
            handles, labels = ax1.get_legend_handles_labels()
            seen, dh, dl = set(), [], []
            for h, l in zip(handles, labels):
                if l not in seen:
                    dh.append(h); dl.append(l); seen.add(l)
            ax1.legend(dh, dl, loc="upper right", fontsize=8)
            ax1.set_ylabel("motion energy")
            ax1.set_title("CSI motion energy + presence verdict")
            ax2.plot(ws, smooth, drawstyle="steps-post", lw=1.2)
            ax2.set_yticks([0, 1])
            ax2.set_yticklabels(["EMPTY", "PRESENT"])
            ax2.set_xlabel("time (s)")
            png = csv_path.with_suffix(".analysis.png")
            fig.tight_layout()
            fig.savefig(png, dpi=120)
            sys.stdout.write(f"\n[plot] saved -> {png}\n")
        except ImportError:
            sys.stdout.write("\n[plot] matplotlib not installed; skipping\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
