"""The chained call unary_exp must serve: exp twice back to back in one XMEM.

The chip runs one layer's output straight into the next layer, so the verifier
runs the kernel twice in one XMEM -- the second run reading the first's ``y``
as its ``x``, where and as it was stored, with the registers as the first run
left them -- and rejects the kernel unless the second run is right too. For
exp that is a real constraint on the declared input range: the second launch's
exp2 argument is ``(y - 8) log2 e``, and ``y = exp(x)`` of a first run whose
``x`` reaches 8 would push it positive (an AaQ error). The declared range top
of 2 keeps it negative: exp(2) = 7.39 <= 8.
"""

import numpy as np

from ipu_harness.chain import Chain


def _operands(numel: int, seed: int = 5):
    rng = np.random.default_rng(seed)
    return rng.uniform(-8.0, 2.0, (numel,))


def test_the_kernel_runs_after_itself_in_one_xmem():
    """The second run reads the first's y as its x, and must be right too."""
    for numel in (1, 200, 1000):  # the default case's shape, and looped shapes
        x = _operands(numel)
        chain = Chain("dynamic")
        first = chain.run("unary_exp", {"fn": "exp", "numel": numel}, {"x": x}, check=True)
        assert first.result.passed, f"numel {numel}: {first.result.describe()}"
        second = chain.run(
            "unary_exp", {"fn": "exp", "numel": numel}, {"x": first.resident["y"]}, check=True
        )
        assert second.result.passed, f"numel {numel} chained: {second.result.describe()}"


def test_the_whole_declared_range_chains():
    """The range's corners: the second launch's exp2 argument stays <= 0."""
    for x0 in (-8.0, -1.0, 0.0, 1.0, 2.0):
        chain = Chain("dynamic")
        one = chain.run("unary_exp", {"fn": "exp", "numel": 1}, {"x": np.array([x0])}, check=True)
        assert one.result.passed, f"x0 {x0}: {one.result.describe()}"
        two = chain.run(
            "unary_exp", {"fn": "exp", "numel": 1}, {"x": one.resident["y"]}, check=True
        )
        assert two.result.passed, f"x0 {x0} chained: {two.result.describe()}"


def test_large_chain_values_stay_in_range():
    """Even exp of the chain's own output is a legal input: exp(2) <= 8."""
    assert np.exp(2.0) <= 8.0
