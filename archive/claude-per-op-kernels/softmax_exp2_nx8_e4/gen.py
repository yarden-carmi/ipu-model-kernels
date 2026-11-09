"""Case generators beyond the default uniform range of ``x``."""

from __future__ import annotations

import numpy as np


def negative(plan, rng):
    """Every logit in [-24, -4]: the row max is negative, so the zero lanes past
    n would make exp2 positive if the last chunk's DS did not exclude them."""
    return {"x": rng.uniform(-24.0, -4.0, size=plan.shapes["x"]).astype(np.float32)}


def wide(plan, rng):
    """Logits N(0, 8^2): rows whose probabilities span many octaves."""
    return {"x": (rng.standard_normal(plan.shapes["x"]) * 8.0).astype(np.float32)}


def constant(plan, rng):
    """Every logit 3: y = 1 / n everywhere."""
    return {"x": np.full(plan.shapes["x"], 3.0, dtype=np.float32)}
