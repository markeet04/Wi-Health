"""Module 6.2.2 (companion) — Uniform-rate resampling.

After Module 6.2.2 cleaning, CSI packets are still irregularly timed:
``host_recv_ts`` carries up to ~100 ms of host-side jitter and the capture
rate fluctuates 20–80 pps depending on Wi-Fi congestion. The Butterworth
bandpass filter that follows in Module 6.2.3 assumes uniformly sampled input.
This module bridges that gap.

Algorithm
---------
Per subcarrier: linear interpolation onto a uniform time grid at
``target_rate_hz`` (default 20 Hz, decided in Module 6.2.1).
Linear interpolation is the standard CSI-resampling choice — for our
input rates (20–80 pps) and motion bands (0.2–3 Hz) it introduces no audible
artifacts and avoids the overshoot of cubic interpolation on noisy data.

Edge handling
-------------
- Output grid spans ``[ceil(t_in[0] / dt) * dt, floor(t_in[-1] / dt) * dt]``
  so we never extrapolate past the input range.
- Large input gaps (> 3 × expected dt for the input stream) are interpolated
  through, but the count is reported in metadata for downstream awareness
  (the Butterworth in 6.2.3 may want to drop windows that span such gaps).

Pi-portability constraint: numpy, scipy, pandas only.
"""
from __future__ import annotations

import warnings
from typing import Any

import numpy as np
from scipy.interpolate import interp1d


def resample_uniform(
    timestamps: np.ndarray,
    csi_matrix: np.ndarray,
    target_rate_hz: float = 20.0,
) -> tuple[np.ndarray, np.ndarray]:
    """Resample irregularly-timed CSI onto a uniform time grid.

    Parameters
    ----------
    timestamps    : (N,) float array of host_recv_ts in seconds (monotonic
                    non-decreasing; need not start at zero).
    csi_matrix    : (N, S) amplitude matrix.
    target_rate_hz : output sample rate in Hz (default 20.0).

    Returns
    -------
    uniform_timestamps : (M,) float64 array — evenly spaced by 1/target_rate_hz.
                         Same units as input ``timestamps``.
    resampled_matrix   : (M, S) float32 array — linear interpolation per
                         subcarrier.

    Behaviour
    ---------
    - Output is trimmed to the input's interior range (no extrapolation).
    - Strictly-equal timestamps (duplicates) are de-duplicated by keeping the
      first occurrence; ``interp1d`` requires monotonically increasing x.
    - If the input span < 1/target_rate_hz the function returns empty arrays
      and a warning.
    - Large gaps (> 3 × median input dt) are interpolated through; a warning
      is emitted via ``warnings.warn`` so calling code (or pytest -W) can
      surface it.
    """
    timestamps = np.asarray(timestamps, dtype=np.float64)
    csi = np.asarray(csi_matrix)
    if timestamps.ndim != 1:
        raise ValueError(f"timestamps must be 1-D, got shape {timestamps.shape}")
    if csi.ndim != 2:
        raise ValueError(f"csi_matrix must be 2-D, got shape {csi.shape}")
    if timestamps.shape[0] != csi.shape[0]:
        raise ValueError(
            f"timestamps and csi_matrix row counts disagree: "
            f"{timestamps.shape[0]} vs {csi.shape[0]}"
        )
    if target_rate_hz <= 0:
        raise ValueError(f"target_rate_hz must be > 0, got {target_rate_hz}")

    if timestamps.shape[0] < 2:
        warnings.warn(
            "resample_uniform: < 2 input samples; returning empty output",
            RuntimeWarning,
            stacklevel=2,
        )
        return np.zeros((0,), dtype=np.float64), np.zeros(
            (0, csi.shape[1]), dtype=np.float32
        )

    # 1. Sort + de-duplicate.
    order = np.argsort(timestamps, kind="stable")
    t_sorted = timestamps[order]
    csi_sorted = csi[order]
    unique_mask = np.concatenate(([True], np.diff(t_sorted) > 0))
    t_in = t_sorted[unique_mask]
    csi_in = csi_sorted[unique_mask]

    if t_in.size < 2:
        warnings.warn(
            "resample_uniform: < 2 unique timestamps after de-dup; "
            "returning empty output",
            RuntimeWarning,
            stacklevel=2,
        )
        return np.zeros((0,), dtype=np.float64), np.zeros(
            (0, csi.shape[1]), dtype=np.float32
        )

    # 2. Build the uniform grid INSIDE the input span — no extrapolation.
    dt = 1.0 / target_rate_hz
    # The grid is anchored so output timestamps are integer multiples of dt
    # relative to t_in[0] (avoids drifting / sub-sample offsets across sessions).
    start = float(np.ceil((t_in[0]) / dt) * dt)
    stop = float(np.floor((t_in[-1]) / dt) * dt)
    if stop < start:
        warnings.warn(
            f"resample_uniform: input span {t_in[-1] - t_in[0]:.4f}s is "
            f"shorter than one output sample period ({dt:.4f}s); "
            "returning empty output",
            RuntimeWarning,
            stacklevel=2,
        )
        return np.zeros((0,), dtype=np.float64), np.zeros(
            (0, csi.shape[1]), dtype=np.float32
        )

    # Use round to avoid floating-point drift accumulating in arange.
    n_out = int(round((stop - start) / dt)) + 1
    uniform_t = start + dt * np.arange(n_out, dtype=np.float64)

    # 3. Detect and warn about large gaps (> 3 * median input dt).
    in_dts = np.diff(t_in)
    median_in_dt = float(np.median(in_dts))
    gap_thresh = 3.0 * median_in_dt
    n_big_gaps = int((in_dts > gap_thresh).sum())
    if n_big_gaps > 0:
        warnings.warn(
            f"resample_uniform: {n_big_gaps} input gap(s) > "
            f"{gap_thresh:.4f}s (3 * median dt) "
            f"will be linearly interpolated through",
            RuntimeWarning,
            stacklevel=2,
        )

    # 4. Linear interpolation per subcarrier.
    interp_fn = interp1d(
        t_in,
        csi_in,
        kind="linear",
        axis=0,
        assume_sorted=True,
        bounds_error=False,
        # We anchored the grid inside [t_in[0], t_in[-1]] so fill_value is
        # actually unused; supply NaN to make any unexpected out-of-bounds
        # value obvious downstream.
        fill_value=np.nan,
        copy=False,
    )
    resampled = interp_fn(uniform_t).astype(np.float32)

    return uniform_t, resampled


def resample_metadata(
    in_timestamps: np.ndarray,
    out_timestamps: np.ndarray,
    target_rate_hz: float,
) -> dict[str, Any]:
    """Compute a small diagnostic dict for a resample_uniform call.

    Not part of the test contract — provided for the validation harness in
    Step 5 and for downstream stages that need to know about gaps.
    """
    in_t = np.asarray(in_timestamps, dtype=np.float64)
    out_t = np.asarray(out_timestamps, dtype=np.float64)
    in_dts = np.diff(in_t) if in_t.size > 1 else np.array([])
    median_in_dt = float(np.median(in_dts)) if in_dts.size else 0.0
    gap_thresh = 3.0 * median_in_dt if median_in_dt > 0 else 0.0
    n_big_gaps = int((in_dts > gap_thresh).sum()) if gap_thresh > 0 else 0
    span_in = float(in_t[-1] - in_t[0]) if in_t.size > 1 else 0.0
    span_out = float(out_t[-1] - out_t[0]) if out_t.size > 1 else 0.0
    return {
        "input_samples":         int(in_t.size),
        "output_samples":        int(out_t.size),
        "input_span_s":          round(span_in, 3),
        "output_span_s":         round(span_out, 3),
        "input_median_dt_s":     round(median_in_dt, 6),
        "input_avg_pps":         round(1.0 / median_in_dt, 2) if median_in_dt > 0 else 0.0,
        "target_rate_hz":        float(target_rate_hz),
        "large_gaps_count":      n_big_gaps,
        "large_gap_threshold_s": round(gap_thresh, 6),
    }
