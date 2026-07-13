"""Module 6.2.2 — Cleaning & Conditioning.

Pipeline (in order):
    1. strip_boot_bleed       — drop ESP32-C6 boot-bleed and otherwise malformed rows
    2. parse_csi_to_amplitude — parse "data" column into |H| = sqrt(I^2 + Q^2)
    3. drop_null_subcarriers  — drop DC + guard subcarriers (low median amplitude)
    4. hampel_filter          — per-subcarrier impulsive-spike replacement

Phase decision — AMPLITUDE ONLY (no CSI phase).
    Justification: single-antenna ESP32-C6 CSI phase is corrupted by CFO (carrier
    frequency offset), SFO (sampling frequency offset), and PBD (packet boundary
    detection) timing jitter on a per-packet basis. The conjugate-multiplication
    trick that sanitizes phase requires >= 2 RX antennas; the C6 has 1. Amplitude
    after AGC/FFT-gain compensation (done in firmware via esp_csi_gain_ctrl) is
    reliable. Phase is discarded at parse time and never propagated.

Pi-portability constraint: only numpy / scipy / pandas / stdlib are imported.
No pyserial, no paho-mqtt, no I/O beyond pandas.read_csv. This module must
deploy unmodified on a Raspberry Pi.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

# Default knobs. The caller may pass overrides via clean_session(config=...).
DEFAULTS: dict[str, Any] = {
    "null_subcarrier_threshold": 2.0,
    "hampel_window_size":        5,
    "hampel_threshold":          3.0,
}

# Expected CSI byte count per packet from rx_csi_recv firmware
# (HT20 ESP32-C6 emits 128 bytes = 64 I/Q pairs = 64 subcarriers).
_EXPECTED_CSI_BYTES = 128


# ---------------------------------------------------------------------------
# 2a. Boot-bleed row stripping
# ---------------------------------------------------------------------------

def _parses_to_expected_size(s: Any) -> bool:
    """Cheap-first check that `data` is a bracketed array of exactly 128 ints."""
    if not isinstance(s, str):
        return False
    s = s.strip()
    if not (s.startswith("[") and s.endswith("]")):
        return False
    body = s[1:-1]
    # Fast pre-filter: 128 ints means exactly 127 commas. Skips the expensive
    # np.fromstring path on the (rare) malformed rows.
    if body.count(",") != _EXPECTED_CSI_BYTES - 1:
        return False
    try:
        arr = np.fromstring(body, sep=",", dtype=np.int16)
    except Exception:
        return False
    return arr.size == _EXPECTED_CSI_BYTES


def strip_boot_bleed(df: pd.DataFrame) -> pd.DataFrame:
    """Remove malformed boot-bleed rows from raw CSV DataFrame.

    Boot-bleed mechanism: when the C6 resets on serial open, the ROM boot banner
    bytes interleave with the in-flight CSV line. The resulting CSV row has its
    columns shifted — `rx_format` contains 'ESP-ROM:esp32c6-20220919', and the
    rest of the columns are missing/garbage. Pandas reads `first_word` and `len`
    as object dtype on the whole column when this happens, so `== 0` comparisons
    silently match nothing. See MODULE_6_2_1.md section 4.4.

    Row is kept iff ALL of:
      - type == "CSI_DATA"
      - first_word (coerced to numeric) == 0   (device's own invalid flag)
      - len        (coerced to numeric) == 128 (expected CSI byte count)
      - data parses to exactly 128 comma-separated ints
    """
    df = df.copy()

    type_ok = df["type"] == "CSI_DATA" if "type" in df.columns else pd.Series([False] * len(df))

    fw = pd.to_numeric(df["first_word"], errors="coerce") if "first_word" in df.columns else pd.Series([np.nan] * len(df))
    fw_ok = fw == 0

    ln = pd.to_numeric(df["len"], errors="coerce") if "len" in df.columns else pd.Series([np.nan] * len(df))
    ln_ok = ln == _EXPECTED_CSI_BYTES

    data_ok = df["data"].apply(_parses_to_expected_size) if "data" in df.columns else pd.Series([False] * len(df))

    keep = type_ok & fw_ok & ln_ok & data_ok
    return df.loc[keep].reset_index(drop=True)


# ---------------------------------------------------------------------------
# 2b. CSI parsing — amplitude only
# ---------------------------------------------------------------------------

def _parse_one_row(s: str) -> np.ndarray | None:
    """Bracketed-array string -> flat int16 I/Q array. Returns None on failure."""
    if not isinstance(s, str):
        return None
    s = s.strip()
    if not s.startswith("["):
        return None
    body = s[1:-1] if s.endswith("]") else s[1:].rstrip("]")
    try:
        arr = np.fromstring(body, sep=",", dtype=np.int16)
    except Exception:
        return None
    if arr.size % 2 != 0:
        arr = arr[:-1]
    return arr


def parse_csi_to_amplitude(data_column: pd.Series) -> np.ndarray:
    """Parse the CSV `data` column (bracketed I/Q strings) into an amplitude
    matrix of shape ``[packets, subcarriers]``.

    Phase is discarded. Output is float32 ``|H| = sqrt(I^2 + Q^2)`` per
    subcarrier per packet.

    Expects input that has already been passed through ``strip_boot_bleed`` —
    every row must parse cleanly. Rows that fail to parse contribute zero rows
    (skipped); caller is responsible for keeping any companion timestamps
    aligned by using the same row mask.
    """
    parsed_list = [_parse_one_row(s) for s in data_column]
    # Determine common row length (use median to be robust against rare misfits).
    lengths = np.array([a.size if a is not None else 0 for a in parsed_list])
    if (lengths == 0).all():
        return np.zeros((0, 0), dtype=np.float32)
    K = int(np.median(lengths[lengths > 0]))
    if K < 8 or K % 2 != 0:
        raise ValueError(f"unexpected CSI vector length K={K}; data column is malformed")

    n = len(parsed_list)
    iq_mat = np.zeros((n, K), dtype=np.int16)
    for i, arr in enumerate(parsed_list):
        if arr is None:
            continue
        a = arr[:K]
        iq_mat[i, : a.size] = a

    I = iq_mat[:, 0::2].astype(np.float32)
    Q = iq_mat[:, 1::2].astype(np.float32)
    # |H| = sqrt(I^2 + Q^2). Phase is intentionally not computed.
    return np.sqrt(I * I + Q * Q)


# ---------------------------------------------------------------------------
# 2c. Null/pilot subcarrier drop
# ---------------------------------------------------------------------------

def drop_null_subcarriers(
    csi_matrix: np.ndarray,
    threshold: float = 2.0,
) -> tuple[np.ndarray, np.ndarray]:
    """Drop subcarriers whose median amplitude across all packets is < threshold.

    Equivalent to the active-subcarrier selection inside ``analyze_motion.py``
    but split out for reuse and downstream reproducibility.

    Returns
    -------
    filtered_matrix : (packets, S_kept) float array
    kept_indices    : 1-D int array of the original subcarrier indices retained.
                      Required so downstream stages can map back to firmware-
                      level subcarrier positions if needed.
    """
    if csi_matrix.ndim != 2:
        raise ValueError(f"csi_matrix must be 2-D, got shape {csi_matrix.shape}")
    if csi_matrix.shape[0] == 0:
        return csi_matrix, np.arange(csi_matrix.shape[1], dtype=np.int64)

    med_per_sub = np.median(csi_matrix, axis=0)
    active_mask = med_per_sub > threshold
    kept_indices = np.flatnonzero(active_mask).astype(np.int64)
    return csi_matrix[:, active_mask], kept_indices


# ---------------------------------------------------------------------------
# 2d. Hampel filter — per-subcarrier impulsive-spike replacement
# ---------------------------------------------------------------------------

def hampel_filter(
    csi_matrix: np.ndarray,
    window_size: int = 5,
    threshold: float = 3.0,
) -> tuple[np.ndarray, int]:
    """Per-subcarrier Hampel outlier removal.

    For each subcarrier independently, slide a centered window of length
    ``window_size`` over the amplitude time series. At every sample compute the
    local median ``m`` and local MAD ``d``. If
    ``|sample - m| > threshold * d``, replace the sample with ``m``.

    A small floor (1e-9) is added to MAD to avoid divide-by-zero in flat
    regions; in such regions any non-equal-to-median sample is flagged, which
    correctly catches spikes injected into otherwise constant signals.

    Parameters
    ----------
    csi_matrix  : (N, S) float array
    window_size : odd integer >= 3 (default 5)
    threshold   : MAD multiplier (default 3.0)

    Returns
    -------
    cleaned          : (N, S) float32 array, copy of input with outliers replaced
    total_replacements : int — total number of samples that were replaced across
                         all subcarriers (diagnostic / regression check).
    """
    if window_size < 3 or window_size % 2 == 0:
        raise ValueError(f"window_size must be odd and >= 3, got {window_size}")
    if csi_matrix.ndim != 2:
        raise ValueError(f"csi_matrix must be 2-D, got shape {csi_matrix.shape}")

    cleaned = csi_matrix.astype(np.float32, copy=True)
    total_replacements = 0

    if csi_matrix.shape[0] < window_size:
        # Not enough samples to filter sensibly — leave as-is.
        return cleaned, 0

    for k in range(cleaned.shape[1]):
        col = pd.Series(cleaned[:, k].astype(np.float64))
        roll = col.rolling(window_size, center=True, min_periods=1)
        med = roll.median()
        mad = roll.apply(
            lambda x: np.median(np.abs(x - np.median(x))),
            raw=True,
        )
        mad_safe = mad.where(mad > 0, 1e-9)

        diff = (col - med).abs()
        outliers = diff > threshold * mad_safe
        n_out = int(outliers.sum())
        if n_out > 0:
            cleaned[outliers.to_numpy(), k] = med[outliers].to_numpy().astype(np.float32)
            total_replacements += n_out

    return cleaned, total_replacements


# ---------------------------------------------------------------------------
# Full session orchestration
# ---------------------------------------------------------------------------

def clean_session(
    csv_path: str | Path,
    config: dict | None = None,
) -> tuple[np.ndarray, np.ndarray, dict]:
    """End-to-end Module-6.2.2 cleaning pipeline for one capture session.

    Steps (in order):
        1. Load CSV with on_bad_lines="skip" (handles column-shifted boot-bleed).
        2. ``strip_boot_bleed`` — drop malformed rows.
        3. Parse host_recv_ts to datetime, drop unparseable.
        4. ``parse_csi_to_amplitude`` — |H| matrix.
        5. ``drop_null_subcarriers`` — DC + guards out.
        6. ``hampel_filter`` — impulsive spikes replaced.

    Returns
    -------
    cleaned_amplitude_matrix : (N, S_kept) float32 array
    timestamps               : (N,) float64 array of seconds since first packet
    metadata                 : dict with diagnostic / reproducibility fields
    """
    cfg = {**DEFAULTS, **(config or {})}
    csv_path = Path(csv_path)

    df = pd.read_csv(csv_path, low_memory=False, on_bad_lines="skip")
    original_shape = (int(df.shape[0]), int(df.shape[1]))

    df = strip_boot_bleed(df)
    after_strip_rows = len(df)
    rows_stripped = original_shape[0] - after_strip_rows
    if after_strip_rows == 0:
        raise ValueError(f"no valid rows after strip_boot_bleed for {csv_path}")

    # Parse timestamps and drop any rows whose timestamp doesn't parse. Indexes
    # of the surviving df rows align 1:1 with the rows we feed to the parser.
    df["host_recv_ts"] = pd.to_datetime(df["host_recv_ts"], errors="coerce")
    df = df.dropna(subset=["host_recv_ts"]).reset_index(drop=True)

    # Parse CSI -> amplitude.
    amp_raw = parse_csi_to_amplitude(df["data"])
    if amp_raw.shape[0] != len(df):
        # parse_csi_to_amplitude is supposed to produce one row per input row
        # (zero rows for unparseable). Defensively re-align via row mask.
        raise RuntimeError(
            f"parse_csi_to_amplitude row count {amp_raw.shape[0]} != "
            f"input rows {len(df)} — strip_boot_bleed should have caught this"
        )

    # Null/pilot subcarrier drop.
    amp_active, kept_idx = drop_null_subcarriers(
        amp_raw, threshold=cfg["null_subcarrier_threshold"]
    )

    # Hampel.
    amp_clean, n_replacements = hampel_filter(
        amp_active,
        window_size=cfg["hampel_window_size"],
        threshold=cfg["hampel_threshold"],
    )

    # Timestamps in seconds since first packet.
    ts_ns = df["host_recv_ts"].to_numpy().astype("datetime64[ns]")
    t0 = ts_ns[0]
    timestamps = (ts_ns - t0).astype("timedelta64[us]").astype(np.int64) / 1_000_000.0
    timestamps = timestamps.astype(np.float64)

    duration_s = float(timestamps[-1] - timestamps[0]) if len(timestamps) > 1 else 0.0
    avg_pps = (len(timestamps) / duration_s) if duration_s > 0 else 0.0

    total_amp_samples = int(amp_clean.size)
    hampel_pct = (
        100.0 * n_replacements / total_amp_samples if total_amp_samples > 0 else 0.0
    )

    metadata = {
        "csv_path":                 str(csv_path),
        "original_shape":           original_shape,
        "rows_stripped":            int(rows_stripped),
        "after_strip_rows":         int(after_strip_rows),
        "subcarriers_total":        int(amp_raw.shape[1]),
        "subcarriers_kept":         int(amp_clean.shape[1]),
        "subcarrier_indices":       kept_idx.tolist(),
        "hampel_replacements":      int(n_replacements),
        "hampel_replacements_pct":  round(hampel_pct, 4),
        "cleaned_shape":            tuple(int(x) for x in amp_clean.shape),
        "duration_s":               round(duration_s, 3),
        "avg_pps_raw":              round(avg_pps, 2),
        "config":                   cfg,
    }
    return amp_clean, timestamps, metadata
