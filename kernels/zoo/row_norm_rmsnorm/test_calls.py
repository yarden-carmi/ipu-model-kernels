"""The calls row_norm_rmsnorm must serve, held to the domain it declares.

The two rmsnorm calls of facebook/detr-resnet-50 (8192 and 32768 rows of 16
channels) are the ``CALLS`` below; the host tiles `rows`, and the kernel takes a
whole tile in one launch -- its group loop runs over ceil(rows / 128) groups.
This test asks the registry for every call as the coverage database queries it,
checks the shapes just outside the declared domain, and runs the kernel twice
back to back in one XMEM, the second reading the first's y as its x.
"""

import numpy as np

from ipu_harness.chain import Chain
from ipu_harness.registry import Registry, kernel_tree

#: The rmsnorm calls found in facebook/detr-resnet-50, per forward at full depth.
CALLS = (
    {"kind": "rmsnorm", "rows": 8192, "channels": 16},
    {"kind": "rmsnorm", "rows": 32768, "channels": 16},
)


def _registry() -> Registry:
    """The registry of the kernel tree, this family only."""
    return Registry.load(kernel_tree(), families=["zoo"])


def _operands(rows: int, channels: int, seed: int = 3):
    """The two operands of a call, over float64."""
    rng = np.random.default_rng(seed)
    return rng.uniform(-1, 1, (rows, channels)), rng.uniform(-1, 1, (channels,))


def test_every_call_routes_to_the_kernel():
    """Registry.resolve accepts each detr call as the host asks for it."""
    registry = _registry()
    for call in CALLS:
        verdict = registry.resolve("row_norm", **call)
        assert verdict, f"{call}: {verdict.reason}"


def test_a_call_beyond_the_domain_is_refused():
    """The kernel refuses what its loops and its datapath cannot take."""
    registry = _registry()
    beyond = (
        {**CALLS[0], "rows": 32769},  # above the declared maximum
        {**CALLS[0], "rows": 0},  # nothing to do
        {**CALLS[0], "channels": 15},  # below the datapath's channels floor
        {**CALLS[0], "channels": 1281},  # above the chunk loop's domain
        {**CALLS[0], "kind": "layernorm"},  # the layernorm program's half of row_norm
        {**CALLS[0], "shapes": [8192, 16]},  # unknown parameter
    )
    for call in beyond:
        verdict = registry.resolve("row_norm", **call)
        assert not verdict, f"{call} is beyond the domain but accepted: {verdict.reason}"


def test_the_kernel_runs_after_itself_in_one_xmem():
    """On the chip y is the next layer's input: a second run reads the first's rows.

    Both runs share one XMEM and one register file, so this is the chain the
    verifier builds: the second kernel's ``x`` is the first's ``y`` resident,
    exactly where and as it stored it, and nothing between them is a host step.
    The program sets every LR it reads and loads its own mask row, so the
    registers the first run left behind cannot matter.
    """
    rows, channels = 20, 16  # one short group
    x, gamma = _operands(rows, channels)
    params = {"kind": "rmsnorm", "rows": rows, "channels": channels}
    chain = Chain("dynamic")
    first = chain.run("row_norm_rmsnorm", params, {"x": x, "gamma": gamma}, check=True)
    assert first.result.passed, first.result.describe()
    second = chain.run(
        "row_norm_rmsnorm", params, {"x": first.resident["y"], "gamma": gamma}, check=True
    )
    assert second.result.passed, second.result.describe()
