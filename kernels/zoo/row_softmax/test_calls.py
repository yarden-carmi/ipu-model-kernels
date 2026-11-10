"""The calls row_softmax must serve, and what a launch of it must fit.

The three surveyed mobilevit_s.cvnets_in1k signatures are routed by the
registry, the largest single launch they need is checked against the 16384
addressable NX8 rows (``rows`` is the dimension the host tiles when a call does
not fit in one), and the folder's ``kernelgen.toml`` is read. The last test
runs the kernel twice on one XMEM, the second step reading the first step's
``y`` as its ``x`` -- what it is like between two other kernels on the chip.
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
    {"rows": 4096, "n": 256},  # x2 per forward
    {"rows": 1024, "n": 64},  # x4 per forward
    {"rows": 256, "n": 16},  # x3 per forward
)

#: The largest values the program's loops and its XMEM footprint take.
MAX_ROWS = 4096
MAX_N = 256

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
        {**CALLS[0], "n": MAX_N + 1},
        {**CALLS[0], "n": 0},
        {**CALLS[1], "dim": 1},  # unknown parameter
        {**CALLS[1], "act": "none"},  # nothing is fused
    )
    for call in beyond:
        verdict = registry.resolve("row_softmax", **call)
        assert not verdict, f"{call} is outside the domain but accepted: {verdict.reason}"


def test_the_domain_holds_the_largest_launch():
    """The maxima are shapes the kernel really runs."""
    registry = _registry()
    for call in (
        {"rows": MAX_ROWS, "n": 1},
        {"rows": MAX_ROWS, "n": 128},
        {"rows": rows_per_launch(256), "n": MAX_N},
        {"rows": 1, "n": MAX_N},
    ):
        verdict = registry.resolve("row_softmax", **call)
        assert verdict, f"{call}: {verdict.reason}"
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
