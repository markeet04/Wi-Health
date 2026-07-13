"""Module 6.2.3 — Butterworth bandpass filter (zero-phase, per subcarrier).

Why bandpass
------------
Human-motion CSI fluctuations live in roughly the 0.3–5 Hz band. What lies
outside this band is what killed T3 cycles 2 and 3 in PROGRESS.md:

  - Below ~0.3 Hz: DC drift + slow channel-state changes (neighbour AP turning
    on, gain controller settling, fan-load thermal drift). This component is
    the "regime shift" that broke the static threshold in T3.
  - Above ~5 Hz: electronic noise, fan-blade harmonics, EMI, and aliased
    sub-packet jitter.

A Butterworth bandpass set to [0.3, 3.0] Hz removes both, so the residual
signal is the motion-band component the detector actually cares about. With
DC removed, the downstream variance/energy metric becomes drift-immune:
the median of "empty" energy stays approximately constant across regimes,
which lets a single static threshold work across the whole session — making
the adaptive-baseline workaround mentioned in PROGRESS.md unnecessary.

Implementation notes
--------------------
- Filter is designed in second-order-section form (`output='sos'`). SOS is the
  numerically stable choice for orders >= 4 and is recommended by scipy.
- ``scipy.signal.sosfiltfilt`` applies the filter forward and backward, which
  cancels phase distortion. The output is zero-phase: peak positions are
  preserved within ~1 sample.
- For typical 6.2.2 outputs (thousands of samples at 20 Hz) the filtfilt
  padlen default is fine. For pathologically short inputs (< 3 * (2*ns + 1)
  samples, where ns = number of biquad sections) we fall back to a shorter
  padlen and emit a warning rather than crashing.

Pi-portability constraint: only numpy + scipy are imported. No pandas, no
pyserial, no paho-mqtt. This module deploys unmodified on a Raspberry Pi.
"""
from __future__ import annotations

import warnings

import numpy as np
from scipy import signal


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def butterworth_bandpass(
    csi_matrix: np.ndarray,
    sample_rate_hz: float,
    low_hz: float = 0.3,
    high_hz: float = 3.0,
    order: int = 4,
) -> np.ndarray:
    """Apply a zero-phase Butterworth bandpass to each subcarrier independently.

    Parameters
    ----------
    csi_matrix     : (N, S) amplitude matrix — uniformly sampled, e.g. the
                     output of ``preprocessing.resample.resample_uniform``.
    sample_rate_hz : sample rate of the input (20.0 Hz from the wi-netra
                     pipeline; can be anything > 2 * high_hz).
    low_hz         : high-pass cutoff (default 0.3 — removes DC drift).
    high_hz        : low-pass cutoff (default 3.0 — removes high-frequency
                     noise above the human-motion band).
    order          : Butterworth order (default 4 — flat passband, ~24 dB/oct
                     rolloff; higher orders sharpen the cutoff at the cost of
                     more transient ringing).

    Returns
    -------
    filtered : (N, S) float32 array, same shape as input. Zero-mean per
               column (DC removed by the high-pass edge).

    Notes
    -----
    - ``filtfilt`` is mandatory here, not plain ``filt``. Half of the reason
      we tolerate the bandpass at all is that it doesn't shift peak positions
      relative to the raw input — that holds only for zero-phase filtering.
    - The float32 output dtype matches the 6.2.2 contract so the rest of the
      pipeline can stay in float32.
    """
    if csi_matrix.ndim != 2:
        raise ValueError(
            f"csi_matrix must be 2-D, got shape {csi_matrix.shape}"
        )
    if order < 1:
        raise ValueError(f"order must be >= 1, got {order}")
    nyq = 0.5 * sample_rate_hz
    if not (0 < low_hz < high_hz):
        raise ValueError(
            f"need 0 < low_hz < high_hz, got low_hz={low_hz} high_hz={high_hz}"
        )
    if high_hz >= nyq:
        raise ValueError(
            f"high_hz ({high_hz}) must be < Nyquist ({nyq}); "
            f"raise sample_rate_hz or lower high_hz"
        )

    # SOS form — numerically stable for order >= 4 and orders we may sweep later.
    sos = signal.butter(
        order, [low_hz, high_hz], btype="bandpass",
        fs=sample_rate_hz, output="sos",
    )
    n_sections = sos.shape[0]

    n_samples = csi_matrix.shape[0]
    # Empirical default padlen for sosfiltfilt is 3 * (2*n_sections + 1).
    # If the input is shorter than that, fall back to (n_samples - 1) and warn.
    default_padlen = 3 * (2 * n_sections + 1)

    x = np.asarray(csi_matrix, dtype=np.float64, order="C")
    if n_samples <= default_padlen:
        padlen = max(0, n_samples - 1)
        warnings.warn(
            f"butterworth_bandpass: input length {n_samples} <= recommended "
            f"padlen {default_padlen} for order={order}; falling back to "
            f"padlen={padlen}. Filter transient may dominate the output.",
            RuntimeWarning,
            stacklevel=2,
        )
        if padlen < 2:
            # Cannot filter sensibly — return mean-removed copy as a graceful
            # degradation that at least preserves the shape contract.
            out = x - x.mean(axis=0, keepdims=True)
            return out.astype(np.float32)
        filtered = signal.sosfiltfilt(sos, x, axis=0, padlen=padlen)
    else:
        filtered = signal.sosfiltfilt(sos, x, axis=0)

    return filtered.astype(np.float32)


def compute_frequency_response(
    sample_rate_hz: float,
    low_hz: float = 0.3,
    high_hz: float = 3.0,
    order: int = 4,
    num_points: int = 512,
) -> tuple[np.ndarray, np.ndarray]:
    """Return (frequencies_hz, magnitude_db) of the bandpass for plotting.

    The magnitude reflects the *single-pass* filter response; the actual
    ``sosfiltfilt`` applies the filter twice (forward + backward), which
    squares the magnitude response — so the effective passband ripple is
    double the dB shown here and the transition is twice as sharp.
    """
    sos = signal.butter(
        order, [low_hz, high_hz], btype="bandpass",
        fs=sample_rate_hz, output="sos",
    )
    w, h = signal.sosfreqz(sos, worN=num_points, fs=sample_rate_hz)
    mag_db = 20.0 * np.log10(np.maximum(np.abs(h), 1e-12))
    return np.asarray(w, dtype=np.float64), mag_db.astype(np.float64)
