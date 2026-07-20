"""Motion-artifact rejection for the breathing pipeline (Module 3 Phase 2.6).

Large body movement (shifting posture, reaching, standing up) perturbs the
CSI amplitude far more than the small chest-wall displacement of breathing
does. This reuses the same idea the guide's intrusion-detection pipeline
uses for human-motion classification: per-subcarrier amplitude variance
rises sharply during movement relative to a stationary baseline.

Applied here as a pre-filter on each sliding window: if a window looks like
the subject moved, it's dropped before it ever reaches CSCR/FFT/
autocorrelation — a moved-during window produces a real but meaningless
"breathing rate" (the movement, not the breath, dominates the signal), so
dropping it beats trying to estimate through it.

v1 (rolling-median-baseline-vs-4x-spike) was live-tested 2026-07-18 against
real, sustained movement (shifting, bending, standing, hand motion, breaking
LOS) and caught NONE of it: 0/31 windows flagged. Root cause — the baseline
was a rolling median of the last 6 windows, and nothing excluded a
window from that rolling set unless it had ALREADY been flagged as motion.
Gradual, sustained escalation (the realistic case — a person doesn't
teleport into a new position) never crossed the spike ratio in any single
step, so the "baseline" just drifted upward in lockstep with the motion
and kept calling it normal. A short adaptive window is structurally blind
to slow drift — it starts looking like "the new normal" before it ever
looks like an outlier.

v2 fixes this with two independent checks, either of which can flag a
window as motion:
  1. COLD BASELINE — locked from the first `cold_baseline_windows` windows
     of the session and never updated again. Immune to drift by
     construction: it cannot chase the signal upward because it stops
     listening after the opening window. Catches motion relative to how
     the session started.
  2. STEP CHANGE — compares each window's score to the immediately
     preceding window's score (not a multi-window rolling average).
     Catches motion the cold baseline might miss if the session opened
     during already-elevated conditions, and catches escalation
     window-to-window even when the absolute level is still below the
     cold-baseline multiple.
"""
from __future__ import annotations

import numpy as np


def window_motion_score(H_window: np.ndarray) -> float:
    """Motion score for one window of complex CSI: (N samples, S subcarriers).

    Mean per-subcarrier amplitude variance across the window, normalized by
    the mean amplitude — a scale-free "how much did |H| wobble" score. Higher
    = more movement. Breathing alone (a ~1-3% chest-wall displacement) keeps
    this low and stable; real body movement raises it.
    """
    if H_window.shape[0] < 2:
        return 0.0
    amp = np.abs(H_window)
    per_sub_var = np.var(amp, axis=0)
    mean_amp = np.mean(amp) + 1e-9
    return float(np.mean(per_sub_var) / (mean_amp ** 2))


class MotionGate:
    """Flags windows where the subject likely moved, via two checks:

    - vs a COLD baseline locked at session start (never drifts)
    - vs a STEP change from the immediately preceding window (catches
      gradual escalation the cold baseline alone might not clear)

    Either check tripping is enough to flag the window as motion.
    """

    def __init__(
        self,
        cold_baseline_windows: int = 3,
        cold_spike_ratio: float = 2.5,
        step_ratio: float = 1.6,
    ):
        self.cold_baseline_windows = cold_baseline_windows
        self.cold_spike_ratio = cold_spike_ratio
        self.step_ratio = step_ratio
        self._cold_samples: list[float] = []
        self._cold_baseline: float | None = None
        self._prev_score: float | None = None

    def check(self, H_window: np.ndarray) -> tuple[bool, float, float]:
        """Returns (is_motion, score, reference_baseline).

        is_motion=True means this window should be dropped, not estimated
        against. reference_baseline is the cold baseline once locked (or
        the running mean of opening samples before it locks), for logging.
        """
        score = window_motion_score(H_window)

        if self._cold_baseline is None:
            self._cold_samples.append(score)
            self._prev_score = score
            if len(self._cold_samples) >= self.cold_baseline_windows:
                self._cold_baseline = float(np.median(self._cold_samples))
            # Nothing to compare against yet — first windows are trusted
            # by construction (there is no prior signal to call them an
            # outlier relative to).
            return False, score, float(np.mean(self._cold_samples))

        cold_flag = (
            self._cold_baseline > 1e-12
            and score > self._cold_baseline * self.cold_spike_ratio
        )
        step_flag = (
            self._prev_score is not None
            and self._prev_score > 1e-12
            and score > self._prev_score * self.step_ratio
        )
        is_motion = bool(cold_flag or step_flag)

        self._prev_score = score
        return is_motion, score, self._cold_baseline
