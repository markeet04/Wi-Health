"""Cleaning + timestamp extraction for the breathing pipeline.

Companion to preprocessing/clean.py — that module is amplitude-only and
hardcodes 128-byte CSI + the C6 column layout. This one:
  * works with both the C6 and S3 CSV column layouts (only relies on the
    shared columns: host_recv_ts, type, len, first_word, data),
  * detects the packet byte count dynamically from the first valid row
    (128 for C6 HT20, 256 for S3 HT20 LLTF+HT-LTF),
  * returns complex CSI (I + jQ),
  * strips boot-bleed / malformed rows and returns aligned timestamps.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

from .parse_complex import parse_csi_to_complex


def _parsed_len(s: object) -> int:
    """Return the number of ints in a bracketed CSI-data cell, or 0 if malformed."""
    if not isinstance(s, str):
        return 0
    s = s.strip()
    if not (s.startswith("[") and s.endswith("]")):
        return 0
    body = s[1:-1]
    n_ints = body.count(",") + 1 if body else 0
    if n_ints < 8 or n_ints % 2 != 0:
        return 0
    try:
        arr = np.fromstring(body, sep=",", dtype=np.int16)
    except Exception:
        return 0
    return int(arr.size) if arr.size == n_ints else 0


def _detect_packet_len(df: pd.DataFrame) -> int:
    """Infer the expected CSI byte count from the modal `len` on well-formed rows.

    We look at rows that (a) claim type==CSI_DATA, (b) have first_word==0, and
    (c) have a `data` cell that parses to an even int array. The mode of their
    `len` field is what the device is producing this session — 128 on C6,
    256 on S3 with LLTF+HT-LTF, etc.
    """
    if "data" not in df.columns:
        return 0
    type_ok = (df["type"] == "CSI_DATA") if "type" in df.columns else pd.Series([True] * len(df))
    fw = pd.to_numeric(df["first_word"], errors="coerce") if "first_word" in df.columns else pd.Series([0] * len(df))
    fw_ok = fw == 0
    parsed_sizes = df["data"].apply(_parsed_len)
    data_ok = parsed_sizes > 0

    mask = type_ok & fw_ok & data_ok
    if not mask.any():
        return 0

    if "len" in df.columns:
        lens = pd.to_numeric(df.loc[mask, "len"], errors="coerce").dropna().astype(int)
        if not lens.empty:
            return int(lens.mode().iat[0])
    # Fall back to the modal parsed size if the CSV somehow lacks a `len` column.
    return int(parsed_sizes[mask].mode().iat[0])


def strip_boot_bleed_health(
    df: pd.DataFrame, expected_len: int | None = None
) -> tuple[pd.DataFrame, int]:
    """Drop boot-bleed / malformed rows. Returns (kept_df, expected_len).

    Column-layout-agnostic: only requires the shared columns type, first_word,
    len, data. Works with both the C6 layout (15 cols) and the S3 layout
    (25 cols).

    A row is kept iff:
      * type == "CSI_DATA"
      * first_word coerces to 0
      * data parses to an even array of >= 8 ints of size == expected_len
      * len (if present) equals expected_len

    `expected_len` is auto-detected from the modal value on well-formed rows
    unless explicitly passed.
    """
    df = df.copy()

    if expected_len is None:
        expected_len = _detect_packet_len(df)
    if expected_len <= 0 or expected_len % 2 != 0:
        return df.iloc[0:0].reset_index(drop=True), 0

    type_ok = (df["type"] == "CSI_DATA") if "type" in df.columns else pd.Series([False] * len(df))
    fw = pd.to_numeric(df["first_word"], errors="coerce") if "first_word" in df.columns else pd.Series([np.nan] * len(df))
    fw_ok = fw == 0
    parsed_sizes = df["data"].apply(_parsed_len) if "data" in df.columns else pd.Series([0] * len(df))
    data_ok = parsed_sizes == expected_len

    if "len" in df.columns:
        ln = pd.to_numeric(df["len"], errors="coerce")
        len_ok = ln == expected_len
    else:
        len_ok = pd.Series([True] * len(df))

    keep = type_ok & fw_ok & data_ok & len_ok
    return df.loc[keep].reset_index(drop=True), expected_len


def load_complex_session(csv_path: str | Path) -> tuple[np.ndarray, np.ndarray, dict]:
    """Load a breathing capture CSV -> (H_complex, timestamps_s, meta).

    Returns
    -------
    H          : (N, S) complex64 — raw complex CSI (no gain / null filtering).
    timestamps : (N,) float64 seconds since first packet (from host_recv_ts).
    meta       : dict with row-count diagnostics.
    """
    csv_path = Path(csv_path)
    raw = csv_path.read_text(encoding="utf-8", errors="replace")
    if not raw.startswith("host_recv_ts,type,"):
        idx = raw.find("\nhost_recv_ts,type,")
        if idx < 0:
            raise ValueError(f"no header row found in {csv_path}")
        raw = raw[idx + 1 :]
    from io import StringIO
    df = pd.read_csv(StringIO(raw), low_memory=False, on_bad_lines="skip")
    original_rows = int(df.shape[0])

    df, expected_len = strip_boot_bleed_health(df)
    if len(df) == 0:
        raise ValueError(f"no valid rows in {csv_path}")

    df["host_recv_ts"] = pd.to_datetime(df["host_recv_ts"], errors="coerce")
    df = df.dropna(subset=["host_recv_ts"]).reset_index(drop=True)

    H = parse_csi_to_complex(df["data"])
    if H.shape[0] != len(df):
        raise RuntimeError(f"row mismatch: parsed {H.shape[0]} vs cleaned {len(df)}")

    ts_ns = df["host_recv_ts"].to_numpy().astype("datetime64[ns]")
    t0 = ts_ns[0]
    timestamps = (ts_ns - t0).astype("timedelta64[us]").astype(np.int64) / 1_000_000.0
    timestamps = timestamps.astype(np.float64)

    meta = {
        "csv_path": str(csv_path),
        "original_rows": original_rows,
        "kept_rows": int(len(df)),
        "bytes_per_packet": int(H.shape[1] * 2),
        "subcarriers": int(H.shape[1]),
        "duration_s": float(timestamps[-1] - timestamps[0]) if len(timestamps) > 1 else 0.0,
    }
    return H, timestamps, meta


def drop_null_subcarriers_complex(
    H: np.ndarray, threshold: float = 2.0
) -> tuple[np.ndarray, np.ndarray]:
    """Drop subcarriers whose median amplitude < threshold. Complex-in, complex-out."""
    if H.ndim != 2 or H.shape[0] == 0:
        return H, np.arange(H.shape[1] if H.ndim >= 2 else 0, dtype=np.int64)
    amp = np.abs(H)
    med = np.median(amp, axis=0)
    keep = med > threshold
    kept_idx = np.flatnonzero(keep).astype(np.int64)
    return H[:, keep], kept_idx
