"""The calls row_norm must serve, held to the domain it declares.

The three layernorm calls mobilevit_s cvnets_in1k runs per forward are the
``CALLS`` below; each is bigger than one 128-lane tile in rows, channels or
both, and the kernel takes a whole call in one launch (its program loops over
the rows in groups of 128 and over the channel chunks). This test asks the
registry for every call as the coverage database queries it, for the shapes
just outside the declared domain, and it checks that each call really fits in
XMEM. It also reads the folder's ``kernelgen.toml``, the metadata the kernel
generator writes, and runs one call back to back with itself in one XMEM.
"""

import json
from pathlib import Path

import numpy as np
import tomli as tomllib

from ipu_harness.chain import Chain
from ipu_harness.registry import Registry, kernel_tree

#: The calls found in the models surveyed, per forward at full depth: the two
#: whisper-large-v3 layer norms (1280 channels; the host tiles the 1500 rows),
#: clip-vit's two, and the three direct-layout mobilevit_s calls.
CALLS = (
    {"kind": "layernorm", "channels": 1280, "rows": 32},
    {"kind": "layernorm", "channels": 1280, "rows": 1500},
    {"kind": "layernorm", "channels": 768, "rows": 50},
    {"kind": "layernorm", "channels": 768, "rows": 1},
    {"kind": "layernorm", "channels": 192, "rows": 256},
    {"kind": "layernorm", "channels": 240, "rows": 64},
    {"kind": "layernorm", "channels": 144, "rows": 1024},
)

#: The largest call the kernel takes in one launch, per dimension, and the
#: narrowest reduction it serves (see kernel.toml's header: below ~32 lanes a
#: group can hold a nearly-constant row, whose A drags the block row's scale).
#: `channels` has no upper bound the program cares about -- its chunk loop is
#: dynamic (CR13) -- but a launch is one XMEM, so the host tiles `rows` down
#: to what 16384 NX8 rows hold at the call's chunk count.
MAX_ROWS = 1500
MAX_CHANNELS = 122880
MIN_CHANNELS = 32


def tile_rows(channels: int) -> int:
    """The rows a launch holds at this chunk count: 3 matrices + constants."""
    chunks = -(-channels // 128)
    return max(1, (16384 - 2 * chunks - 7) // (3 * chunks))


TILE_ROWS = 512  # the host's tile at 1280 channels (544 is the exact bound)

#: The XMEM rows an NX8 call can address.
XMEM_ROWS = 16384


def _registry() -> Registry:
    """The registry of the kernel tree, this family only."""
    return Registry.load(kernel_tree(), families=["zoo"])


def _rows(call: dict) -> int:
    """The XMEM rows a call packs into: x, gamma, beta, y, p and the constants.

    The host tiles `rows` -- per-row normalisation makes the tiles independent
    -- so what must fit one launch is a tile, not the whole call, and the tile
    shrinks with the chunk count (x, y and p are rows * chunks rows each).
    """
    chunks = -(-call["channels"] // 128)
    return 3 * min(call["rows"], tile_rows(call["channels"])) * chunks + 2 * chunks + 7


def test_every_call_routes_to_the_kernel():
    """Registry.resolve accepts each surveyed call as the host asks for it."""
    registry = _registry()
    for call in CALLS:
        verdict = registry.resolve("row_norm", **call)
        assert verdict, f"{call}: {verdict.reason}"
        assert verdict.kernel_name == "row_norm_layernorm"


def test_every_call_fits_in_xmem():
    """The calls the domain accepts are calls the launch can actually hold."""
    for call in CALLS:
        rows = _rows(call)
        assert rows <= XMEM_ROWS, f"{call} needs {rows} XMEM rows"


def test_the_whole_domain_fits_in_xmem():
    """Every corner of the declared rectangle, not only the surveyed calls."""
    for rows in (1, 127, 128, 129):
        for channels in (MIN_CHANNELS, 128, 129, MAX_CHANNELS):
            for kind in ("layernorm", "rmsnorm"):
                call = {"kind": kind, "rows": rows, "channels": channels}
                assert _rows(call) <= XMEM_ROWS, call
    for channels in (MIN_CHANNELS, 1280, MAX_CHANNELS):
        call = {"kind": "layernorm", "rows": tile_rows(channels), "channels": channels}
        assert _rows(call) <= XMEM_ROWS, call


def test_a_call_beyond_the_domain_is_refused():
    """The kernel refuses what its loops, its XMEM and its datapath cannot take."""
    registry = _registry()
    beyond = (
        {**CALLS[6], "rows": MAX_ROWS + 1},
        {**CALLS[0], "channels": MAX_CHANNELS + 1},
        {**CALLS[0], "channels": MIN_CHANNELS - 1},  # a group's A row cannot hold it
        {**CALLS[0], "kind": "groupnorm"},  # groupnorm lowers to rows of a group
        {**CALLS[0], "kind": "none"},
        {**CALLS[0], "rows": 0},
        {**CALLS[0], "channels": 0},
        {**CALLS[0], "weights": 3},  # unknown parameter
        {**CALLS[0], "x_from": "patches:2"},  # the mobilevit patch permutation
        {**CALLS[0], "x_from": "pixels:2"},
        {**CALLS[0], "y_to": "patches:2"},
        {**CALLS[0], "y_to": "pixels:2"},
        {**CALLS[0], "x_from": "heads:4:64"},
        {**CALLS[0], "x_from": "merge:4:64"},
    )
    for call in beyond:
        verdict = registry.resolve("row_norm", **call)
        assert not verdict, f"{call} is above the domain but accepted: {verdict.reason}"


def test_the_domain_holds_the_largest_call():
    """The maxima are shapes the kernel really runs, and they are the maxima."""
    registry = _registry()
    for call in (
        {"kind": "layernorm", "rows": MAX_ROWS, "channels": 128},
        {"kind": "rmsnorm", "rows": tile_rows(MAX_CHANNELS), "channels": MAX_CHANNELS},
        {"kind": "layernorm", "rows": tile_rows(MAX_CHANNELS), "channels": MAX_CHANNELS},
        {"kind": "layernorm", "rows": 1, "channels": MIN_CHANNELS},
        {"kind": "rmsnorm", "rows": 1, "channels": MIN_CHANNELS},
        {"kind": "layernorm", "rows": 32, "channels": 2560},
        {"kind": "layernorm", "rows": 32, "channels": 40960},
        {"kind": "layernorm", "rows": 32, "channels": 122880},
        {"kind": "rmsnorm", "rows": 32, "channels": 122880},
    ):
        verdict = registry.resolve("row_norm", **call)
        assert verdict, f"{call}: {verdict.reason}"
        assert _rows(call) <= XMEM_ROWS, call


def test_the_kernel_runs_after_itself_in_one_xmem():
    """On the chip y is the next layer's x: a second run reads the first's rows.

    Both runs share one XMEM and one register file, so this is the chain the
    verifier builds: the second kernel's ``x`` is the first's ``y`` resident,
    exactly where and as it stored it, and nothing between them is a host step.
    """
    params = {"kind": "layernorm", "rows": 64, "channels": 240}
    rng = np.random.default_rng(7)
    x = rng.uniform(-1, 1, (params["rows"], params["channels"]))
    gamma = rng.uniform(-1, 1, (params["channels"],))
    beta = rng.uniform(-1, 1, (params["channels"],))
    chain = Chain("dynamic")
    first = chain.run(
        "row_norm_layernorm", params, {"x": x, "gamma": gamma, "beta": beta}, check=True
    )
    assert first.result.passed, first.result.describe()
    second = chain.run(
        "row_norm_layernorm",
        params,
        {"x": first.resident["y"], "gamma": gamma, "beta": beta},
        check=True,
    )
    assert second.result.passed, second.result.describe()


def test_the_kernelgen_metadata_says_what_the_kernel_does():
    """kernelgen.toml reads, and agrees with the kernel's own declarations."""
    folder = Path(__file__).parent
    with (folder / "kernelgen.toml").open("rb") as handle:
        gen = tomllib.load(handle)
    assert gen["kind"] == "approximation"
    assert gen["method"] == "rsqrt"
    assert gen["task"] == "row_norm_layernorm"
    assert gen["hw_clean"] is True, "an NX8 kernel whose stores are ACTIVATE.QUANTIZE"
    assert gen["host_steps"] == [], "the goal is every layer on the IPU"
    assert gen["chain_in"] == "x" and gen["chain_out"] == "y"
    asm = (folder / "row_norm_layernorm.asm").read_text(encoding="utf-8")
    assert "ACTIVATE.EXACT" not in asm
    assert "BREAK" not in asm
    assert "rsqrt" in asm, "the AaQ stage's rsqrt is the approximation"
    with (folder / "kernel.toml").open("rb") as handle:
        assert tomllib.load(handle)["kernel"]["op"] == "row_norm"
    for entry in gen["unsupported"]:
        head, sep, why = entry.partition("}: ")
        assert sep and why, entry
        params = json.loads(head + "}")
        assert params not in CALLS, entry  # every surveyed call is supported
        assert not _registry().resolve("row_norm", **params), entry
