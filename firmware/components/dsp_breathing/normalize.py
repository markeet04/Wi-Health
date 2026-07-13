"""Module 6.2.4 — Per-window Z-score normalization (per subcarrier).

Why per-window
--------------
The 6.2.3 Butterworth output is already zero-mean *globally* (DC removed),
but the residual standard deviation varies across:

  - rooms / board placements (different RSSI → different signal scale)
  - sessions in the same room recorded at different times (Wi-Fi noise drift)
  - subcarriers within a session (some carry more multipath energy than others)

Z-scoring each window per subcarrier compresses those scale differences so
the downstream feature extractor in Module 6.3 sees inputs on a common scale
regardless of where / when the data was recorded.

Design decision: Option A — per-window
--------------------------------------
We normalize *inside* each window rather than on the full signal. Trade-offs:

  + Each window is self-contained — works for online / streaming where no
    "global statistics" are available.
  + Matches the proposal's stated per-window contract.
  + Compatible with Module 6.3's expectation that each window arrives ready
    to feature-extract.

  - A dead-quiet window (std below epsilon) can't be Z-scored without
    dividing by ~0. Handled by clipping: if a subcarrier's std is below
    `epsilon`, its output is forced to all zeros in that window — signalling
    "no motion-band content here" rather than producing inf / NaN.

Pi-portability constraint: only numpy. No scipy, no pandas, no I/O libs.
This module deploys unmodified on a Raspberry Pi.
"""
from __future__ import annotations

import numpy as np


def zscore_normalize(window: np.ndarray, epsilon: float = 1e-8) -> np.ndarray:
    """Per-subcarrier Z-score normalization within a single window.

    Parameters
    ----------
    window  : (T, S) float array — one window of filtered CSI amplitude. T is
              the number of time samples in the window, S is the number of
              subcarriers.
    epsilon : minimum acceptable standard deviation. Any subcarrier whose
              within-window std falls below this is treated as "dead quiet"
              and emitted as all zeros rather than divided through.

    Returns
    -------
    out : (T, S) float32 array of the same shape. For each alive subcarrier
          ``k``, ``out[:, k]`` has mean ~0 and std ~1. For each dead-quiet
          subcarrier, ``out[:, k]`` is all zeros.

    Notes
    -----
    - Uses the *population* std (``ddof=0``). For motion-detection windows
      around 100 samples the bias relative to ddof=1 is negligible
      (~0.5%) and the result is closer to "what a downstream feature would
      assume" of a finite chunk of stationary data.
    - This function does not mutate the input.
    """
    if not isinstance(window, np.ndarray):
        window = np.asarray(window)
    if window.ndim != 2:
        raise ValueError(f"window must be 2-D, got shape {window.shape}")
    if epsilon <= 0:
        raise ValueError(f"epsilon must be > 0, got {epsilon}")

    x = window.astype(np.float64, copy=False)
    mean = x.mean(axis=0, keepdims=True)
    std = x.std(axis=0, keepdims=True, ddof=0)

    # Per-subcarrier alive mask: True if std >= epsilon.
    alive = std >= epsilon

    # Z-score where alive, 0 where dead. We use np.where rather than masking
    # in-place to avoid running division on the dead columns at all.
    safe_std = np.where(alive, std, 1.0)
    centered = x - mean
    out = np.where(alive, centered / safe_std, 0.0)

    return out.astype(np.float32)


def zscore_normalize_batch(
    windows: list[np.ndarray],
    epsilon: float = 1e-8,
) -> list[np.ndarray]:
    """Apply ``zscore_normalize`` to every window in a list.

    Parameters
    ----------
    windows : list of (T_i, S) arrays — windows may differ in T_i (e.g.,
              partial trailing windows). All must share the same number of
              subcarriers, but this function does not enforce that — each
              window is normalized independently.
    epsilon : passed through to ``zscore_normalize``.

    Returns
    -------
    list of (T_i, S) float32 arrays — same lengths as input, in the same order.
    """
    return [zscore_normalize(w, epsilon=epsilon) for w in windows]
