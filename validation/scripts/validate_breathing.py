#!/usr/bin/env python3
"""Validate a breathing capture — run the pipeline and produce a 4-panel plot.

Usage:
    python validate_breathing.py path/to/breath_YYYYMMDD_....csv
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

from firmware.components.dsp_breathing.breathing import extract_breathing_rate
from firmware.components.csi_capture.clean_health import load_complex_session, drop_null_subcarriers_complex


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Validate a breathing capture.")
    p.add_argument("csv", help="path to breathing session CSV")
    p.add_argument("--outdir", default=None, help="dir for the .breathing.png (default: alongside CSV)")
    p.add_argument("--no-plot", action="store_true", help="skip plotting; print BPM only")
    return p.parse_args()


def _autocorr_curve(x: np.ndarray) -> np.ndarray:
    x = x.astype(np.float64) - float(np.mean(x))
    n = x.size
    nfft = int(2 ** np.ceil(np.log2(2 * n)))
    F = np.fft.rfft(x, n=nfft)
    ac = np.fft.irfft(F * np.conj(F), n=nfft)[:n]
    if ac[0] > 0:
        ac = ac / ac[0]
    return ac


def main() -> int:
    args = parse_args()
    csv_path = Path(args.csv).resolve()
    if not csv_path.exists():
        sys.stderr.write(f"file not found: {csv_path}\n")
        return 2

    result = extract_breathing_rate(csv_path)

    sys.stdout.write(
        f"\n=== {csv_path.name} ===\n"
        f"  duration:        {result['load_meta']['duration_s']:.1f} s\n"
        f"  subcarriers:     {result['load_meta']['subcarriers']} "
        f"({result['load_meta']['bytes_per_packet']} bytes/pkt)\n"
        f"  active subs:     {len(result['kept_subcarriers'])}\n"
        f"  selected pairs:  {len(result['selected_pairs'])}\n"
        f"  fs (resampled):  {result['sample_rate_hz']} Hz\n"
        f"  BPM (FFT):       {result['bpm_fft']:.2f}  (conf {result['confidence_fft']:.2f})\n"
        f"  BPM (autocorr):  {result['bpm_autocorr']:.2f}  (conf {result['confidence_autocorr']:.2f})\n"
        f"  BPM (median):    {result['bpm_median']:.2f}\n"
        f"  methods agree:   {result['agreement']}\n"
        f"  status:          {result['status']}"
        f"{'' if result['valid'] else '  <-- DO NOT TRUST'}\n"
    )
    sys.stdout.flush()

    if args.no_plot:
        return 0

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        sys.stderr.write("matplotlib not installed — skipping plot.\n")
        return 0

    # Raw amplitude of one representative subcarrier for the top panel.
    H_raw, ts_raw, _ = load_complex_session(csv_path)
    H_active, _ = drop_null_subcarriers_complex(H_raw, threshold=2.0)
    if H_active.shape[1] > 0:
        mid = H_active.shape[1] // 2
        raw_amp = np.abs(H_active[:, mid])
    else:
        raw_amp = np.abs(H_raw[:, 0]) if H_raw.size else np.zeros(0)

    wave = result["respiratory_waveform"]
    ts = result["timestamps"]
    freqs = result["spectrum_freqs"]
    spec = result["spectrum"]
    fs = result["sample_rate_hz"]
    band = result["band_hz"]

    fig, axes = plt.subplots(4, 1, figsize=(10, 11))

    axes[0].plot(ts_raw, raw_amp, linewidth=0.6, color="#444")
    axes[0].set_title(f"Raw CSI amplitude — subcarrier {mid if H_active.shape[1] > 0 else 0}")
    axes[0].set_xlabel("time (s)")
    axes[0].set_ylabel("|H|")

    axes[1].plot(ts, wave, color="tab:blue")
    axes[1].set_title("CSCR respiratory waveform (combined, band-passed)")
    axes[1].set_xlabel("time (s)")
    axes[1].set_ylabel("normalized")

    axes[2].plot(freqs, spec, color="tab:purple")
    axes[2].set_xlim(0, max(band[1] * 3, 1.0))
    axes[2].axvspan(band[0], band[1], alpha=0.15, color="tab:green", label="breathing band")
    if np.isfinite(result["bpm_fft"]):
        f_peak = result["bpm_fft"] / 60.0
        axes[2].axvline(f_peak, color="tab:red", linestyle="--",
                        label=f"peak = {result['bpm_fft']:.1f} BPM")
    axes[2].set_title("FFT spectrum")
    axes[2].set_xlabel("Hz")
    axes[2].set_ylabel("magnitude")
    axes[2].legend(loc="upper right")

    ac = _autocorr_curve(wave)
    lags = np.arange(ac.size) / fs
    axes[3].plot(lags, ac, color="tab:orange")
    axes[3].set_xlim(0, min(lags[-1], 20.0))
    axes[3].axhline(0, color="#999", linewidth=0.5)
    if np.isfinite(result["bpm_autocorr"]) and result["bpm_autocorr"] > 0:
        lag_peak = 60.0 / result["bpm_autocorr"]
        axes[3].axvline(lag_peak, color="tab:red", linestyle="--",
                        label=f"peak = {result['bpm_autocorr']:.1f} BPM (lag {lag_peak:.2f}s)")
        axes[3].legend(loc="upper right")
    axes[3].set_title("Autocorrelation")
    axes[3].set_xlabel("lag (s)")
    axes[3].set_ylabel("normalized")

    fig.suptitle(
        f"{csv_path.stem} — BPM median {result['bpm_median']:.1f}  "
        f"(agree={result['agreement']}, conf={result['confidence']:.2f}, "
        f"status={result['status']})",
        fontsize=11,
    )
    fig.tight_layout()

    out_dir = Path(args.outdir).resolve() if args.outdir else csv_path.parent
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{csv_path.stem}.breathing.png"
    fig.savefig(out_path, dpi=120)
    plt.close(fig)
    sys.stdout.write(f"  plot:            {out_path}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
