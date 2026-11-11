"""The calls binary_div_row must serve, held to the domain it declares.

The two row-broadcast divisions facebook/detr-resnet-50 runs per forward are
the ``CALLS`` below (inner 16 over 256 elements and inner 128 over 32768);
this test asks the registry for every call as the coverage database queries
it, for the shapes just outside the declared domain, and checks that each
call fits in XMEM. It also runs the kernel twice back to back in one XMEM,
the second reading the first's y as its a, and reads the folder's
``kernelgen.toml``, the metadata the kernel generator writes.
"""

import json
from pathlib import Path

import numpy as np
import tomli as tomllib

from ipu_harness.chain import Chain
from ipu_harness.registry import Registry, kernel_tree

#: The calls found in facebook/detr-resnet-50, per forward at full depth.
CALLS = (
    {"op": "div", "broadcast": "row", "inner": 16, "numel": 256},
    {"op": "div", "broadcast": "row", "inner": 128, "numel": 32768},
)

#: The ops and broadcasts this kernel renders, and the widest call it takes.
OPS = ("div",)
BROADCASTS = ("row",)
INNERS = (16, 32, 64, 128)
MAX_NUMEL = 262144

#: The XMEM rows an NX8 call can address.
XMEM_ROWS = 16384


def _registry() -> Registry:
    """The registry of the kernel tree, this family only."""
    return Registry.load(kernel_tree(), families=["zoo"])


def _rows(call: dict) -> int:
    """The XMEM rows a call packs: a, y (one per 128 elements) and six one-row
    scratches (b, maskr, rcp, u, e, twos)."""
    return 2 * (-(-call["numel"] // 128)) + 6


def _operands(numel: int, inner: int, seed: int = 3):
    """The two operands of the case's shape, over float64."""
    rng = np.random.default_rng(seed)
    return rng.uniform(-1, 1, (numel,)), rng.uniform(0.25, 4, (inner,))


def test_every_call_routes_to_the_kernel():
    """Registry.resolve accepts each surveyed call as the host asks for it."""
    registry = _registry()
    for call in CALLS:
        verdict = registry.resolve("binary", **call)
        assert verdict, f"{call}: {verdict.reason}"
        assert verdict.kernel_name == "binary_div_row"


def test_every_call_fits_in_xmem():
    """The calls the domain accepts are calls the launch can actually hold."""
    for call in CALLS:
        rows = _rows(call)
        assert rows <= XMEM_ROWS, f"{call} needs {rows} XMEM rows"


def test_the_whole_domain_fits_in_xmem():
    """Every corner of the declared range, not only the surveyed calls."""
    for numel in (1, 2, 127, 128, 129, 256, 4096, MAX_NUMEL):
        for inner in INNERS:
            call = {"op": "div", "broadcast": "row", "inner": inner, "numel": numel}
            assert _registry().resolve("binary", **call), call
            assert _rows(call) <= XMEM_ROWS, call


def test_a_call_beyond_the_domain_is_refused():
    """The kernel refuses what its loops, its XMEM and its datapath cannot take."""
    registry = _registry()
    beyond = (
        {**CALLS[0], "numel": MAX_NUMEL + 1},  # above the declared maximum
        {**CALLS[0], "numel": 0},  # nothing to do, and rows - 1 would underflow
        {**CALLS[0], "numel": 262272},  # far above it
        {**CALLS[0], "op": "add"},  # another op (kernelgen.toml)
        {**CALLS[0], "op": "mul"},
        {**CALLS[0], "op": "min"},
        {**CALLS[0], "broadcast": "none"},  # elementwise div: binary_add_none's
        {**CALLS[0], "broadcast": "scalar"},  # a scalar b: binary_div_scalar's
        {**CALLS[0], "inner": 8},  # below the narrowest tiled row
        {**CALLS[0], "inner": 240},  # not a power of two: lanes would rotate
        {**CALLS[0], "inner": 256},  # more than one b row: no third load slot
        {**CALLS[0], "inner": 512},
        {**CALLS[0], "shapes": [256]},  # unknown parameter
    )
    for call in beyond:
        verdict = registry.resolve("binary", **call)
        assert not verdict, f"{call} is outside the domain but accepted: {verdict.reason}"


def test_the_domain_holds_the_largest_and_narrowest_calls():
    """The maxima are shapes the kernel really runs, and they are the maxima."""
    registry = _registry()
    for call in (
        {**CALLS[1], "numel": MAX_NUMEL},
        {**CALLS[0], "numel": 1},
        {**CALLS[0], "inner": 128, "numel": 129},
        {**CALLS[0], "inner": 128, "numel": 128},
    ):
        verdict = registry.resolve("binary", **call)
        assert verdict, f"{call}: {verdict.reason}"
        assert _rows(call) <= XMEM_ROWS, call


def test_the_kernel_runs_after_itself_in_one_xmem():
    """On the chip y is the next layer's input: a second run reads the first's rows.

    Both runs share one XMEM and one register file, so this is the chain the
    verifier builds: the second kernel's ``a`` is the first's ``y`` resident,
    exactly where and as it stored it, and nothing between them is a host step.
    The program sets every LR it reads and loads its own mask row, so the
    registers the first run left behind cannot matter.
    """
    numel, inner = 1000, 128  # eight rows, the last a short one
    a, b = _operands(numel, inner)
    for op in OPS:
        params = {"op": op, "broadcast": "row", "inner": inner, "numel": numel}
        chain = Chain("dynamic")
        first = chain.run("binary_div_row", params, {"a": a, "b": b}, check=True)
        assert first.result.passed, f"{op}: {first.result.describe()}"
        second = chain.run(
            "binary_div_row", params, {"a": first.resident["y"], "b": b}, check=True
        )
        assert second.result.passed, f"{op} chained: {second.result.describe()}"


def test_the_kernelgen_metadata_says_what_the_kernel_does():
    """kernelgen.toml reads, and agrees with the kernel's own declarations."""
    folder = Path(__file__).parent
    with (folder / "kernelgen.toml").open("rb") as handle:
        gen = tomllib.load(handle)
    assert gen["kind"] == "approximation"
    assert gen["method"] == "newton-reciprocal"
    assert gen["task"] == "binary_div_row"
    assert gen["hw_clean"] is True, "an NX8 kernel whose stores are ACTIVATE.QUANTIZE"
    assert gen["host_steps"] == [], "the goal is every layer on the IPU"
    assert gen["chain_in"] == "a" and gen["chain_out"] == "y"
    asm = (folder / "binary_div_row.asm").read_text(encoding="utf-8")
    assert "ACTIVATE.EXACT" not in asm
    assert "BREAK" not in asm
    assert "ACTIVATE.QUANTIZE" in asm, "the store is the hardware one"
    with (folder / "kernel.toml").open("rb") as handle:
        assert tomllib.load(handle)["kernel"]["op"] == "binary"
    for entry in gen["unsupported"]:
        head, sep, why = entry.partition("}: ")
        assert sep and why, entry
        params = json.loads(head + "}")
        assert params not in CALLS, entry  # every surveyed call is supported
        assert not _registry().resolve("binary", **params), entry
