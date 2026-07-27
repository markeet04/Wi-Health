"""End-to-end breathing / respiration detection pipeline.

Given a raw wi-netra CSI capture CSV (subject stationary, breathing normally),
extract breaths-per-minute via two independent estimators (FFT and
autocorrelation) and flag agreement.

Pipeline
--------
    1. load_complex_session  (strip boot-bleed, parse complex CSI, timestamps)
    2. drop_null_subcarriers
    3. resample real+imag to a uniform grid at ~10 Hz
    4. select_subcarrier_pairs — pick top-N pairs by breathing-band SNR
    5. compute_cscr on selected pairs
    6. cscr_to_respiratory_waveform (real projection + avg + hampel + savgol)
    7. Butterworth bandpass 0.1-0.5 Hz
    8. bpm_from_fft, bpm_from_autocorrelation
    9. Report median + agreement flag.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np
from scipy.interpolate import interp1d
from scipy.signal import butter, sosfiltfilt

from ..csi_capture.clean_health import load_complex_session, drop_null_subcarriers_complex
from .cscr import (
    compute_cscr,
    select_subcarrier_pairs,
    cscr_to_respiratory_waveform,
)
from .motion import MotionGate


DEFAULTS: dict[str, Any] = {
    "target_sample_rate_hz": 10.0,
    "hampel_window_size": 5,
    "hampel_threshold": 3.0,
    "null_subcarrier_threshold": 2.0,
    "num_pairs": 20,
    "bandpass_low_hz": 0.1,
    "bandpass_high_hz": 0.5,
    "butter_order": 4,
    "savgol_window": 21,
    "savgol_order": 3,
    "window_seconds": 30.0,
    "stride_seconds": 5.0,
    "min_bpm": 6.0,
    "max_bpm": 30.0,
    "agreement_threshold_bpm": 2.0,
    # Module 2 ground-truth validation (2026-07-14, n=5, 8-21 bpm) found
    # confidence strongly predicts accuracy (r=-0.95): sessions below this
    # threshold are the ones where FFT/autocorrelation diverged and the
    # reported bpm was untrustworthy. Below this, extract_breathing_rate
    # reports status="low_confidence" instead of a bare number.
    "min_confidence": 0.3,
}


def _resample_complex_uniform(
    timestamps: np.ndarray,
    H: np.ndarray,
    target_rate_hz: float,
) -> tuple[np.ndarray, np.ndarray]:
    """Linear-interpolate a complex CSI matrix onto a uniform grid.

    Real and imaginary parts are interpolated separately, then recombined.
    """
    if H.shape[0] < 2:
        return np.zeros((0,), dtype=np.float64), np.zeros((0, H.shape[1]), dtype=np.complex64)

    order = np.argsort(timestamps, kind="stable")
    t = timestamps[order]
    H = H[order]
    uniq = np.concatenate(([True], np.diff(t) > 0))
    t = t[uniq]
    H = H[uniq]

    dt = 1.0 / target_rate_hz
    start = float(np.ceil(t[0] / dt) * dt)
    stop = float(np.floor(t[-1] / dt) * dt)
    if stop < start:
        return np.zeros((0,), dtype=np.float64), np.zeros((0, H.shape[1]), dtype=np.complex64)
    n_out = int(round((stop - start) / dt)) + 1
    grid = start + dt * np.arange(n_out, dtype=np.float64)

    real_fn = interp1d(t, H.real, axis=0, kind="linear", assume_sorted=True, copy=False)
    imag_fn = interp1d(t, H.imag, axis=0, kind="linear", assume_sorted=True, copy=False)
    resampled = (real_fn(grid) + 1j * imag_fn(grid)).astype(np.complex64)
    return grid, resampled


def _bandpass(signal: np.ndarray, low_hz: float, high_hz: float,
              sample_rate: float, order: int = 4) -> np.ndarray:
    nyq = 0.5 * sample_rate
    lo = max(1e-6, low_hz / nyq)
    hi = min(0.999, high_hz / nyq)
    sos = butter(order, [lo, hi], btype="bandpass", output="sos")
    # sosfiltfilt requires signal length > padlen; guard tiny inputs.
    if signal.size < 3 * (2 * order + 1):
        return signal.astype(np.float32, copy=True)
    return sosfiltfilt(sos, signal).astype(np.float32)


def bpm_from_fft(
    signal: np.ndarray,
    sample_rate: float,
    band: tuple[float, float] = (0.1, 0.5),
) -> tuple[float, float]:
    """FFT peak in `band` -> (bpm, confidence).

    Confidence = peak magnitude / mean magnitude across the full spectrum.
    """
    x = signal.astype(np.float64) - float(np.mean(signal))
    n = x.size
    if n < 16 or np.std(x) < 1e-9:
        return float("nan"), 0.0
    # Zero-pad to at least 4x for finer frequency resolution.
    nfft = int(2 ** np.ceil(np.log2(max(n * 4, 128))))
    spec = np.abs(np.fft.rfft(x, n=nfft))
    freqs = np.fft.rfftfreq(nfft, d=1.0 / sample_rate)
    in_band = (freqs >= band[0]) & (freqs <= band[1])
    if not np.any(in_band):
        return float("nan"), 0.0
    band_spec = spec.copy()
    band_spec[~in_band] = 0.0
    peak_idx = int(np.argmax(band_spec))
    peak_freq = float(freqs[peak_idx])
    peak_mag = float(spec[peak_idx])
    mean_mag = float(np.mean(spec) + 1e-12)
    return peak_freq * 60.0, peak_mag / mean_mag


def bpm_from_autocorrelation(
    signal: np.ndarray,
    sample_rate: float,
    band: tuple[float, float] = (0.1, 0.5),
) -> tuple[float, float]:
    """First significant autocorrelation peak in the lag range for `band`.

    Confidence = peak_height / autocorr[0].
    """
    x = signal.astype(np.float64) - float(np.mean(signal))
    n = x.size
    if n < 16 or np.std(x) < 1e-9:
        return float("nan"), 0.0
    # Biased autocorrelation via FFT.
    nfft = int(2 ** np.ceil(np.log2(2 * n)))
    F = np.fft.rfft(x, n=nfft)
    ac = np.fft.irfft(F * np.conj(F), n=nfft)[:n]
    ac0 = float(ac[0])
    if ac0 <= 0:
        return float("nan"), 0.0

    # Lag search bounds: high_hz -> smallest lag, low_hz -> largest lag.
    lag_min = int(np.floor(sample_rate / band[1]))
    lag_max = int(np.ceil(sample_rate / band[0]))
    lag_min = max(1, lag_min)
    lag_max = min(n - 1, lag_max)
    if lag_max <= lag_min:
        return float("nan"), 0.0

    segment = ac[lag_min:lag_max + 1]
    # Find first local peak; fall back to global argmax if none exists.
    peak_off: int | None = None
    for i in range(1, segment.size - 1):
        if segment[i] > segment[i - 1] and segment[i] > segment[i + 1]:
            peak_off = i
            break
    if peak_off is None:
        peak_off = int(np.argmax(segment))
    lag = lag_min + peak_off
    freq = sample_rate / lag
    conf = float(segment[peak_off] / ac0)
    return freq * 60.0, conf


def _estimate_from_complex(
    H_u: np.ndarray,
    fs: float,
    band: tuple[float, float],
    cfg: dict[str, Any],
    pairs: list[tuple[int, int]] | None = None,
) -> dict:
    """Core estimator: resampled complex CSI matrix -> full diagnostic dict.

    Shared by extract_breathing_rate (whole-file batch) and
    sliding_window_estimate (per-window streaming) so both paths run the
    exact same math. If `pairs` is given, subcarrier selection is skipped
    (a live/streaming caller reuses the pairs chosen on a prior window
    instead of re-running select_subcarrier_pairs on every stride, which
    is the expensive step).
    """
    if pairs is None:
        pairs = select_subcarrier_pairs(
            H_u,
            num_pairs=int(cfg["num_pairs"]),
            breathing_band=band,
            sample_rate=fs,
        )
    if not pairs:
        raise ValueError("no viable subcarrier pairs — CSCR selection failed")

    cscr = compute_cscr(H_u, pairs)
    wave = cscr_to_respiratory_waveform(
        cscr,
        hampel_window=int(cfg["hampel_window_size"]),
        hampel_threshold=float(cfg["hampel_threshold"]),
        savgol_window=int(cfg["savgol_window"]),
        savgol_order=int(cfg["savgol_order"]),
    )
    wave_bp = _bandpass(wave, band[0], band[1], fs, order=int(cfg["butter_order"]))

    bpm_fft, conf_fft = bpm_from_fft(wave_bp, fs, band=band)
    bpm_ac, conf_ac = bpm_from_autocorrelation(wave_bp, fs, band=band)

    valid_fft = np.isfinite(bpm_fft) and cfg["min_bpm"] <= bpm_fft <= cfg["max_bpm"]
    valid_ac = np.isfinite(bpm_ac) and cfg["min_bpm"] <= bpm_ac <= cfg["max_bpm"]

    if valid_fft and valid_ac:
        bpm_median = float(np.median([bpm_fft, bpm_ac]))
        agreement = abs(bpm_fft - bpm_ac) <= float(cfg["agreement_threshold_bpm"])
        confidence = float(min(conf_fft, conf_ac))
    elif valid_fft:
        bpm_median, agreement, confidence = float(bpm_fft), False, float(conf_fft) * 0.5
    elif valid_ac:
        bpm_median, agreement, confidence = float(bpm_ac), False, float(conf_ac) * 0.5
    else:
        bpm_median, agreement, confidence = float("nan"), False, 0.0

    # Gate the output: a window with low confidence and/or FFT/autocorr
    # disagreement is not trustworthy (see Module 2 finding above). Report
    # that explicitly via `status` rather than silently emitting a number a
    # caller has no reason to distrust. bpm_median is still returned
    # (never NaN'd out here) so callers that only look at bpm_median keep
    # working, but they should check `status` before trusting it.
    min_confidence = float(cfg["min_confidence"])
    if not (valid_fft or valid_ac):
        status = "no_valid_breathing"
    elif not agreement:
        status = "disagreement"
    elif confidence < min_confidence:
        status = "low_confidence"
    else:
        status = "ok"
    valid = status == "ok"

    # Spectrum for plotting / reporting.
    x = wave_bp.astype(np.float64) - float(np.mean(wave_bp))
    nfft = int(2 ** np.ceil(np.log2(max(x.size * 4, 128))))
    spec = np.abs(np.fft.rfft(x, n=nfft))
    freqs = np.fft.rfftfreq(nfft, d=1.0 / fs)

    return {
        "bpm_fft": float(bpm_fft),
        "bpm_autocorr": float(bpm_ac),
        "bpm_median": float(bpm_median),
        "confidence": float(confidence),
        "confidence_fft": float(conf_fft),
        "confidence_autocorr": float(conf_ac),
        "agreement": bool(agreement),
        "status": status,
        "valid": bool(valid),
        "respiratory_waveform": wave_bp,
        "waveform_unfiltered": wave,
        "spectrum": spec,
        "spectrum_freqs": freqs,
        "selected_pairs": pairs,
        "sample_rate_hz": fs,
        "band_hz": band,
    }


def extract_breathing_rate(
    csv_path: str | Path,
    config: dict | None = None,
) -> dict:
    """Full breathing detection pipeline; returns a diagnostic dict."""
    cfg = {**DEFAULTS, **(config or {})}
    fs = float(cfg["target_sample_rate_hz"])
    band = (float(cfg["bandpass_low_hz"]), float(cfg["bandpass_high_hz"]))

    H_raw, timestamps, load_meta = load_complex_session(csv_path)

    H_active, kept_idx = drop_null_subcarriers_complex(
        H_raw, threshold=float(cfg["null_subcarrier_threshold"])
    )
    if H_active.shape[1] < 4:
        raise ValueError(
            f"only {H_active.shape[1]} active subcarriers after null-drop; "
            "check gain / link"
        )

    grid, H_u = _resample_complex_uniform(timestamps, H_active, fs)
    if H_u.shape[0] < int(fs * 10):
        raise ValueError(
            f"resampled capture too short ({H_u.shape[0]} samples at {fs} Hz)"
        )

    result = _estimate_from_complex(H_u, fs, band, cfg)
    result["timestamps"] = grid
    result["kept_subcarriers"] = kept_idx.tolist()
    result["load_meta"] = load_meta
    result["config"] = cfg
    return result


class RollingBpmBuffer:
    """Module 3 Phase 2.5 — smooths single-window noise with a rolling median.

    Keeps the last `size` *valid* (status="ok") window estimates and reports
    their median. A single noisy window (the kind Module 2 saw plenty of)
    gets outvoted by its neighbors instead of standing alone as "the"
    reading. Invalid windows (low_confidence/disagreement/no_valid_breathing)
    are never added — they don't get to pollute the smoothed estimate, but
    they're also not silently hidden: the caller still sees that window's
    own status via sliding_window_estimate.
    """

    def __init__(self, size: int = 6):
        self.size = size
        self._buffer: list[float] = []

    def push(self, bpm: float) -> None:
        self._buffer.append(bpm)
        if len(self._buffer) > self.size:
            self._buffer.pop(0)

    @property
    def smoothed_bpm(self) -> float:
        if not self._buffer:
            return float("nan")
        return float(np.median(self._buffer))

    @property
    def window_count(self) -> int:
        return len(self._buffer)


def sliding_window_estimate(
    csv_path: str | Path,
    config: dict | None = None,
):
    """Module 3 Phase 2.4/2.6 — continuous windowed estimation over one capture.

    Replays a full capture as a sequence of overlapping windows
    (window_seconds long, advancing stride_seconds at a time — the same two
    config values the batch pipeline has always defined but never actually
    used for anything before this), yielding one result dict per window as
    they'd arrive in a live/streaming deployment.

    Each window:
      1. is screened by a MotionGate — a window where the subject moved is
         yielded with status="motion_rejected" and bpm_median=nan, WITHOUT
         running the CSCR/FFT/autocorrelation math on it (motion swamps the
         breathing signal, so estimating through it would just manufacture
         a confident-looking wrong number);
      2. otherwise runs the same _estimate_from_complex core the batch
         pipeline uses, reusing the subcarrier pairs chosen on the first
         valid window (re-selecting them every stride would be the most
         expensive part of the pipeline run on a needless repeat);
      3. valid (status="ok") windows are folded into a RollingBpmBuffer;
         every yielded dict carries the buffer's current smoothed_bpm
         alongside that window's own raw bpm_median, so a caller can choose
         either the instantaneous or the smoothed reading.

    Yields dicts with all the keys extract_breathing_rate returns for a
    valid window (status="ok"), plus for every window regardless of status:
    window_index, window_start_s, window_end_s, motion_rejected,
    motion_score, smoothed_bpm, smoothed_window_count.
    """
    cfg = {**DEFAULTS, **(config or {})}
    fs = float(cfg["target_sample_rate_hz"])
    band = (float(cfg["bandpass_low_hz"]), float(cfg["bandpass_high_hz"]))
    window_s = float(cfg["window_seconds"])
    stride_s = float(cfg["stride_seconds"])

    H_raw, timestamps, load_meta = load_complex_session(csv_path)
    H_active, kept_idx = drop_null_subcarriers_complex(
        H_raw, threshold=float(cfg["null_subcarrier_threshold"])
    )
    if H_active.shape[1] < 4:
        raise ValueError(
            f"only {H_active.shape[1]} active subcarriers after null-drop; "
            "check gain / link"
        )

    grid, H_u = _resample_complex_uniform(timestamps, H_active, fs)
    window_samples = int(round(window_s * fs))
    stride_samples = max(1, int(round(stride_s * fs)))
    if H_u.shape[0] < window_samples:
        raise ValueError(
            f"capture ({H_u.shape[0]} samples) shorter than one window "
            f"({window_samples} samples at {fs} Hz) — need at least "
            f"{window_s:.0f}s of data"
        )

    motion_gate = MotionGate()
    smoother = RollingBpmBuffer()
    reused_pairs: list[tuple[int, int]] | None = None

    window_index = 0
    start = 0
    while start + window_samples <= H_u.shape[0]:
        end = start + window_samples
        H_window = H_u[start:end]
        t_window = grid[start:end]

        is_motion, motion_score, motion_baseline = motion_gate.check(H_window)

        base = {
            "window_index": window_index,
            "window_start_s": float(t_window[0]),
            "window_end_s": float(t_window[-1]),
            "motion_rejected": bool(is_motion),
            "motion_score": motion_score,
            "motion_baseline": motion_baseline,
            "smoothed_bpm": smoother.smoothed_bpm,
            "smoothed_window_count": smoother.window_count,
        }

        if is_motion:
            base.update({
                "status": "motion_rejected",
                "bpm_fft": float("nan"),
                "bpm_autocorr": float("nan"),
                "bpm_median": float("nan"),
                "confidence": 0.0,
                "agreement": False,
                "valid": False,
            })
            yield base
            window_index += 1
            start += stride_samples
            continue

        try:
            result = _estimate_from_complex(
                H_window, fs, band, cfg, pairs=reused_pairs
            )
        except ValueError:
            base.update({
                "status": "no_valid_breathing",
                "bpm_fft": float("nan"),
                "bpm_autocorr": float("nan"),
                "bpm_median": float("nan"),
                "confidence": 0.0,
                "agreement": False,
                "valid": False,
            })
            yield base
            window_index += 1
            start += stride_samples
            continue

        if reused_pairs is None:
            reused_pairs = result["selected_pairs"]

        if result["status"] == "ok":
            smoother.push(result["bpm_median"])

        base.update(result)
        base["smoothed_bpm"] = smoother.smoothed_bpm
        base["smoothed_window_count"] = smoother.window_count
        yield base

        window_index += 1
        start += stride_samples
