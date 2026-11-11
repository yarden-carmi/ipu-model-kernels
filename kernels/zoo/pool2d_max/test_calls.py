"""pool2d_max's calls: the domain's corners, refusals, and chaining.

The resnet18.a1_in1k max-pool (64 channels, 112x112, 3x3, stride 2, padding 1)
is the `default` case in kernel.toml. This test checks the domain's other
corners at emulable sizes, that a call outside the domain is refused, and that
the kernel runs twice back to back in one XMEM, the second reading the first's
y as its x -- the registers the first run left behind cannot matter (the
program sets every LR it relies on and loads its own mask row).
"""

import numpy as np

from ipu_harness.chain import Chain
from ipu_harness.registry import Registry, kernel_tree

BASE = {"kind": "max", "channels": 64, "h": 8, "w": 9, "k": 3, "stride": 2, "padding": 1}

CORNERS = [
    BASE,
    {**BASE, "k": 1, "stride": 1, "padding": 0},
    {**BASE, "k": 2, "stride": 2, "padding": 0},
    {**BASE, "k": 3, "stride": 1, "padding": 2},
    {**BASE, "channels": 256},
    {**BASE, "channels": 1},
    {**BASE, "h": 1, "w": 1},
]

REFUSED = [
    {**BASE, "padding": 3},  # a window can cover no pixel: no valid seed
    {**BASE, "kind": "avg"},  # no exact division on the datapath
    {**BASE, "channels": 300},  # above the declared maximum
]


def _operands(h: int, w: int, channels: int, seed: int = 5):
    rng = np.random.default_rng(seed)
    return rng.uniform(-1, 1, (h, w, channels))


def _run(params):
    chain = Chain("dynamic")
    return chain.run(
        "pool2d_max",
        params,
        {"x": _operands(params["h"], params["w"], params["channels"])},
        check=True,
    )


def test_the_corners_run():
    for params in CORNERS:
        run = _run(params)
        assert run.result.passed, f"{params}: {run.result.describe()}"


def test_a_call_outside_the_domain_is_refused():
    registry = Registry.load(kernel_tree(), families=["zoo"])
    for params in REFUSED:
        verdict = registry.resolve("pool2d", **params)
        assert not verdict, f"{params} is outside the domain but accepted: {verdict.reason}"


def test_the_kernel_runs_after_itself_in_one_xmem():
    """A second run reads the first's y as its x (a 4x5 pool after an 8x9)."""
    chain = Chain("dynamic")
    first = chain.run(
        "pool2d_max", BASE, {"x": _operands(BASE["h"], BASE["w"], BASE["channels"])}, check=True
    )
    assert first.result.passed, first.result.describe()
    inner = {**BASE, "h": 4, "w": 5}  # y of the first is exactly this call's x
    second = chain.run("pool2d_max", inner, {"x": first.resident["y"]}, check=True)
    assert second.result.passed, f"chained: {second.result.describe()}"
