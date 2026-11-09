"""Case generators beyond the default uniform ranges."""

from __future__ import annotations

import numpy as np


def _affine(plan, rng):
    channels = plan.shapes["gamma"]
    return {
        "gamma": rng.uniform(-2.0, 2.0, size=channels).astype(np.float32),
        "beta": rng.uniform(-1.0, 1.0, size=channels).astype(np.float32),
    }


def offset(plan, rng):
    """x = 6 + N(0, 1): every token's mean is six standard deviations from 0,
    so the centering must use an accurate mean (the hi + lo split)."""
    x = 6.0 + rng.standard_normal(plan.shapes["x"])
    return {"x": x.astype(np.float32), **_affine(plan, rng)}


def residual(plan, rng):
    """A transformer residual stream: N(0, 1) with a few outlier channels at
    +-20, which set the row scale of their chunk."""
    x = rng.standard_normal(plan.shapes["x"])
    channels = plan.shapes["x"][-1]
    outliers = rng.choice(channels, size=max(1, channels // 128), replace=False)
    x[:, outliers] = rng.choice([-20.0, 20.0], size=(x.shape[0], outliers.size))
    return {"x": x.astype(np.float32), **_affine(plan, rng)}


def constant(plan, rng):
    """Every x 3: the variance is 0, so y = beta (eps keeps rsqrt finite)."""
    return {"x": np.full(plan.shapes["x"], 3.0, dtype=np.float32), **_affine(plan, rng)}
