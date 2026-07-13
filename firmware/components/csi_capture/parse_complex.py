"""Complex CSI parsing for health/breathing pipeline.

Parses the CSV ``data`` column (bracketed int8/int16 I/Q byte lists emitted
by rx_csi_recv) into complex CSI matrices where H = I + jQ per subcarrier.

Handles both 128-byte (64 subcarriers, C6 HT20) and 256-byte (128 subcarriers,
S3 HT20 with LLTF+HT-LTF merged) formats. Row length is inferred from data.

Pi-portability: numpy / pandas only.
"""
from __future__ import annotations

import numpy as np
import pandas as pd


def _parse_one_row(s: object) -> np.ndarray | None:
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
    if arr.size < 4 or arr.size % 2 != 0:
        return None
    return arr


def _parse_all(data_column: pd.Series) -> np.ndarray:
    parsed = [_parse_one_row(s) for s in data_column]
    lengths = np.array([a.size if a is not None else 0 for a in parsed])
    if (lengths == 0).all():
        return np.zeros((0, 0), dtype=np.int16)
    K = int(np.median(lengths[lengths > 0]))
    if K < 8 or K % 2 != 0:
        raise ValueError(f"unexpected CSI vector length K={K}")
    n = len(parsed)
    iq = np.zeros((n, K), dtype=np.int16)
    for i, a in enumerate(parsed):
        if a is None:
            continue
        take = a[:K]
        iq[i, : take.size] = take
    return iq


def parse_csi_to_complex(data_column: pd.Series) -> np.ndarray:
    """Return complex CSI matrix H = I + jQ, shape [packets, subcarriers].

    Handles arbitrary even byte counts — 128 bytes yields 64 subcarriers (C6),
    256 bytes yields 128 subcarriers (S3 LLTF+HT-LTF).
    """
    iq = _parse_all(data_column)
    if iq.size == 0:
        return np.zeros((0, 0), dtype=np.complex64)
    I = iq[:, 0::2].astype(np.float32)
    Q = iq[:, 1::2].astype(np.float32)
    return (I + 1j * Q).astype(np.complex64)


def parse_csi_to_amplitude_and_phase(
    data_column: pd.Series,
) -> tuple[np.ndarray, np.ndarray]:
    """Return (amplitude, unwrapped_phase), each [packets, subcarriers], float32.

    Phase is unwrapped per subcarrier across packets with np.unwrap.
    Note: raw ESP32 CSI phase is corrupted per-packet by CFO/SFO/PBD; this
    unwrapping is done for diagnostic use. The CSCR stage (see cscr.py)
    is what actually cancels the per-packet phase offset.
    """
    H = parse_csi_to_complex(data_column)
    if H.size == 0:
        return (np.zeros((0, 0), dtype=np.float32),
                np.zeros((0, 0), dtype=np.float32))
    amp = np.abs(H).astype(np.float32)
    phase = np.angle(H).astype(np.float32)
    phase = np.unwrap(phase, axis=0).astype(np.float32)
    return amp, phase
