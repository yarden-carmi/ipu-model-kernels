"""The calls row_softmax must serve, and what a launch of it must fit.

The three surveyed mobilevit_s.cvnets_in1k signatures and whisper-large-v3's
two 1500-wide ones are routed by the registry; the largest single launch each
needs is checked against the 16384 addressable NX8 rows (``rows`` is the
dimension the host tiles when a call does not fit in one), and the folder's
``kernelgen.toml`` is read. The last test runs the kernel twice on one XMEM,
the second step reading the first step's ``y`` as its ``x`` -- what it is like
between two other kernels on the chip.
"""

from pathlib import Path

import numpy as np
import tomli as tomllib

from ipu_harness.chain import Chain
from ipu_harness.manifest import load_manifest
from ipu_harness.registry import Registry, kernel_tree
from ipu_harness.variants import variant

#: The calls found in the models surveyed, per forward at full depth.
CALLS = (
    {"rows": 4096, "n": 256},  # x2 per forward, mobilevit_s
    {"rows": 1024, "n": 64},  # x4 per forward, mobilevit_s
    {"rows": 256, "n": 16},  # x3 per forward, mobilevit_s
    {"rows": 640, "n": 1500},  # x32 per forward, openai/whisper-large-v3
    {"rows": 30000, "n": 1500},  # x32 per forward, openai/whisper-large-v3
    {"rows": 56, "n": 4096},  # x3 per forward, facebook/sam-vit-base
)

#: The largest values the program's loops take: any ``rows`` is tiled by the
#: host, ``n`` reaches the program as a rendered 32-chunk unroll.
MAX_ROWS = 30000
MAX_N = 4096

#: The XMEM rows an NX8 call can address.
XMEM_ROWS = 16384

FOLDER = Path(__file__).parent


def _registry() -> Registry:
    """The registry of the kernel tree, this family only."""
    return Registry.load(kernel_tree(), families=["zoo"])


def tiles(n: int) -> int:
    """The 128-lane chunks a row of ``n`` takes."""
    return -(-n // 128)


def rows_per_launch(n: int) -> int:
    """The largest ``rows`` the kernel takes in one launch at this ``n``.

    A launch owns x and y and nothing else (the numerators live in y's rows and
    the two scalars round-trip through y's last row), so it is 16384 / tiles.
    """
    return XMEM_ROWS // (2 * tiles(n))


def _rows(call: dict) -> int:
    """The XMEM rows a launch of ``call`` packs into: x and y, tiles rows each."""
    return 2 * call["rows"] * tiles(call["n"])


def test_every_call_routes_to_the_kernel():
    """Registry.resolve accepts each surveyed call as the host asks for it."""
    registry = _registry()
    for call in CALLS:
        verdict = registry.resolve("row_softmax", **call)
        assert verdict, f"{call}: {verdict.reason}"
        assert verdict.kernel_name == "row_softmax"


def test_every_call_runs_or_is_tiled_in_rows():
    """Each call fits one launch, or a tile of its rows does.

    ``rows`` is an independent dimension: the host may split it across
    launches; nothing else needs tiling.
    """
    for call in CALLS:
        assert call["rows"] <= MAX_ROWS, call
        assert call["n"] <= MAX_N, call
        if _rows(call) > XMEM_ROWS:
            assert rows_per_launch(call["n"]) >= 1, call
            # A tile of it is a call the kernel takes and one launch holds.
            tile = {**call, "rows": rows_per_launch(call["n"])}
            assert _rows(tile) <= XMEM_ROWS, tile
            assert _registry().resolve("row_softmax", **tile), tile


def test_a_call_beyond_the_domain_is_refused():
    """The kernel refuses what its loops and its footprint cannot take."""
    registry = _registry()
    beyond = (
        {**CALLS[1], "rows": MAX_ROWS + 1},
        {**CALLS[1], "rows": 0},
        {**CALLS[4], "rows": MAX_ROWS + 1},  # above the declared rows maximum
        {**CALLS[0], "n": MAX_N + 1},  # above the rendered unroll
        {**CALLS[0], "n": 0},
        {**CALLS[1], "dim": 1},  # unknown parameter
        {**CALLS[1], "act": "none"},  # nothing is fused
    )
    for call in beyond:
        verdict = registry.resolve("row_softmax", **call)
        assert not verdict, f"{call} is outside the domain but accepted: {verdict.reason}"


def test_the_domain_holds_the_largest_launch():
    """The maxima are shapes the kernel really runs, and a launch of each fits."""
    registry = _registry()
    for call in (
        {"rows": MAX_ROWS, "n": 1},
        {"rows": MAX_ROWS, "n": 128},
        {"rows": MAX_ROWS, "n": 2048},
        {"rows": rows_per_launch(MAX_N), "n": 2048},
        {"rows": rows_per_launch(MAX_N), "n": MAX_N},
        {"rows": 1, "n": MAX_N},
        {"rows": rows_per_launch(1500), "n": 1500},
        {"rows": rows_per_launch(MAX_N), "n": MAX_N},
    ):
        verdict = registry.resolve("row_softmax", **call)
        assert verdict, f"{call}: {verdict.reason}"
        if _rows(call) > XMEM_ROWS:
            call = {**call, "rows": rows_per_launch(call["n"])}
        assert _rows(call) <= XMEM_ROWS, call


def test_the_program_is_hardware_clean():
    """No emulator-only instruction, and the golden is the plain softmax."""
    text = (FOLDER / "row_softmax.asm").read_text(encoding="utf-8")
    assert "ACTIVATE.EXACT" not in text
    assert "BREAK" not in text
    assert "ACTIVATE.QUANTIZE" in text
    for fmt in load_manifest(FOLDER).formats:
        assert fmt.nx8, "an NX8-only kernel: no FP32 variant to hide an emulator store in"


def test_the_kernelgen_metadata_says_what_the_kernel_does():
    """kernelgen.toml reads, and agrees with the kernel's own declarations."""
    with (FOLDER / "kernelgen.toml").open("rb") as handle:
        gen = tomllib.load(handle)
    assert gen["kind"] == "approximation"
    assert gen["method"] == "exp2"
    assert gen["task"] == "row_softmax"
    assert gen["hw_clean"] is True, "every store is an ACTIVATE.QUANTIZE"
    assert gen["host_steps"] == [], "the goal is every layer on the IPU"
    assert gen["chain_in"] == "x" and gen["chain_out"] == "y"
    assert gen["unsupported"] == []
    with (FOLDER / "kernel.toml").open("rb") as handle:
        assert tomllib.load(handle)["kernel"]["op"] == gen["task"]


def test_a_second_run_reads_the_first_run_output():
    """Two steps on one XMEM: softmax(softmax(x)), the chip's case."""
    manifest = load_manifest(FOLDER)
    params = {"rows": 12, "n": 100}
    x = np.random.default_rng(3).uniform(-4.0, 4.0, (params["rows"], params["n"]))
    chain = Chain(variant("dynamic"))
    first = chain.run(manifest, params, {"x": x}, check=True)
    assert all(c.passed for c in first.result.comparisons), [
        c.describe() for c in first.result.comparisons
    ]
    second = chain.run(manifest, params, {"x": first.resident["y"]}, check=True)
    assert all(c.passed for c in second.result.comparisons), [
        c.describe() for c in second.result.comparisons
    ]


def test_the_chain_holds_over_shapes_and_kinds_of_input():
    """The shift must keep the exp2 argument <= 0 for any x a kernel writes.

    Each case runs twice on one XMEM, the second step reading the first step's
    ``y`` as its ``x``: probabilities (all in [0, 1], rows of them with a
    single dominant lane), uniform logits and all-negative ones -- the last is
    the row the relu floor exists for.
    """
    for rows, n, seed, (low, high) in (
        (12, 100, 3, (-4.0, 4.0)),  # the shape of test_a_second_run...
        (1, 1, 4, (-4.0, 4.0)),  # the narrowest chain
        (3, 128, 5, (-4.0, 4.0)),
        (5, 4096, 6, (-4.0, 4.0)),  # the widest row, chained
        (9, 64, 7, (0.0, 1.0)),  # probabilities: x = softmax outputs
        (9, 64, 8, (-4.0, -0.5)),  # all-negative logits: the relu floor's row
        (17, 129, 9, (-4.0, 4.0)),  # a ragged tail, chained
    ):
        x = np.random.default_rng(seed).uniform(low, high, (rows, n))
        chain = Chain(variant("dynamic"))
        manifest = load_manifest(FOLDER)
        first = chain.run(manifest, {"rows": rows, "n": n}, {"x": x}, check=True)
        assert all(c.passed for c in first.result.comparisons), (rows, n, span)
        try:
            second = chain.run(manifest, {"rows": rows, "n": n}, {"x": first.resident["y"]}, check=True)
        except Exception as e:
            raise AssertionError(f"chain failed for rows={rows} n={n} x=uniform({low},{high}) seed={seed}") from e
        assert all(c.passed for c in second.result.comparisons), (
            rows, n, span, [c.describe() for c in second.result.comparisons],
        )
