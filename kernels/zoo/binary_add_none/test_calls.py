"""The calls binary must serve, held to the domain it declares.

The four elementwise adds mobilevit_s cvnets_in1k runs per forward are the
``CALLS`` below (15360, 49152, 147456 and 262144 elements); each is far bigger
than one 128-lane row, and the kernel takes a whole call in one launch -- its
program loops over the rows. This test asks the registry for every call as the
coverage database queries it, for the shapes just outside the declared domain,
and it checks that each call really fits in XMEM. It also runs the kernel twice
back to back in one XMEM, the second reading the first's y as its a, and reads
the folder's ``kernelgen.toml``, the metadata the kernel generator writes.
"""

import json
from pathlib import Path

import numpy as np
import tomli as tomllib

from ipu_harness.chain import Chain
from ipu_harness.registry import Registry, kernel_tree

#: The calls found in the models surveyed, per forward at full depth.
CALLS = (
    {"op": "add", "broadcast": "none", "inner": 0, "numel": 15360},
    {"op": "add", "broadcast": "none", "inner": 0, "numel": 49152},
    {"op": "add", "broadcast": "none", "inner": 0, "numel": 147456},
    {"op": "add", "broadcast": "none", "inner": 0, "numel": 262144},
)

#: The ops the program renders, and the widest call it takes in one launch.
OPS = ("add", "sub", "mul", "max")
MAX_NUMEL = 262144

#: The XMEM rows an NX8 call can address.
XMEM_ROWS = 16384


def _registry() -> Registry:
    """The registry of the kernel tree, this family only."""
    return Registry.load(kernel_tree(), families=["zoo"])


def _rows(call: dict) -> int:
    """The XMEM rows a call packs into: a, b, y (one row per 128 elements) and the mask."""
    return 3 * (-(-call["numel"] // 128)) + 1


def _operands(numel: int, seed: int = 3):
    """Two operands of the case's shape, over float64."""
    rng = np.random.default_rng(seed)
    return rng.uniform(-1, 1, (numel,)), rng.uniform(-1, 1, (numel,))


def test_every_call_routes_to_the_kernel():
    """Registry.resolve accepts each surveyed call as the host asks for it."""
    registry = _registry()
    for call in CALLS:
        verdict = registry.resolve("binary", **call)
        assert verdict, f"{call}: {verdict.reason}"
        assert verdict.kernel_name == "binary_add_none"


def test_every_call_fits_in_xmem():
    """The calls the domain accepts are calls the launch can actually hold."""
    for call in CALLS:
        rows = _rows(call)
        assert rows <= XMEM_ROWS, f"{call} needs {rows} XMEM rows"


def test_the_whole_domain_fits_in_xmem():
    """Every corner of the declared range, not only the surveyed calls."""
    for numel in (1, 2, 127, 128, 129, 256, 4096, MAX_NUMEL):
        for op in OPS:
            call = {"op": op, "broadcast": "none", "inner": 0, "numel": numel}
            assert _registry().resolve("binary", **call), call
            assert _rows(call) <= XMEM_ROWS, call


def test_a_call_beyond_the_domain_is_refused():
    """The kernel refuses what its loops, its XMEM and its datapath cannot take."""
    registry = _registry()
    beyond = (
        {**CALLS[0], "numel": MAX_NUMEL + 1},  # above the declared maximum
        {**CALLS[0], "numel": 0},  # nothing to do, and rows - 1 would underflow
        {**CALLS[0], "op": "div"},  # no exact reciprocal (kernelgen.toml)
        {**CALLS[0], "op": "min"},  # no ACC.MIN and no negation to build one
        {**CALLS[0], "op": "and"},  # not an arithmetic op at all
        {**CALLS[0], "broadcast": "row", "inner": 240},  # b's row pointer cannot cycle
        {**CALLS[0], "broadcast": "col", "inner": 64},  # one scalar per row of a
        {**CALLS[0], "broadcast": "scalar", "inner": 1},  # one value
        {**CALLS[0], "inner": 128},  # inner takes 0 only, with nothing broadcast
        {**CALLS[0], "shapes": [15360]},  # unknown parameter
    )
    for call in beyond:
        verdict = registry.resolve("binary", **call)
        assert not verdict, f"{call} is above the domain but accepted: {verdict.reason}"


def test_the_domain_holds_the_largest_call():
    """The maxima are shapes the kernel really runs, and they are the maxima."""
    registry = _registry()
    for call in (
        {**CALLS[0], "numel": MAX_NUMEL},
        {**CALLS[0], "numel": 1},
        {**CALLS[0], "numel": 129, "op": "mul"},
        {**CALLS[0], "numel": 128, "op": "max"},
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
    numel = 1000  # eight rows, the last a short one
    a, b = _operands(numel)
    for op in OPS:
        params = {"op": op, "broadcast": "none", "inner": 0, "numel": numel}
        chain = Chain("dynamic")
        first = chain.run("binary_add_none", params, {"a": a, "b": b}, check=True)
        assert first.result.passed, f"{op}: {first.result.describe()}"
        second = chain.run(
            "binary_add_none", params, {"a": first.resident["y"], "b": b}, check=True
        )
        assert second.result.passed, f"{op} chained: {second.result.describe()}"


def test_the_kernelgen_metadata_says_what_the_kernel_does():
    """kernelgen.toml reads, and agrees with the kernel's own declarations."""
    folder = Path(__file__).parent
    with (folder / "kernelgen.toml").open("rb") as handle:
        gen = tomllib.load(handle)
    assert gen["kind"] == "exact"
    assert gen["method"] == "exact"
    assert gen["task"] == "binary_add_none"
    assert gen["hw_clean"] is True, "an NX8 kernel whose stores are ACTIVATE.QUANTIZE"
    assert gen["host_steps"] == [], "the goal is every layer on the IPU"
    assert gen["chain_in"] == "a" and gen["chain_out"] == "y"
    asm = (folder / "binary_add_none.asm").read_text(encoding="utf-8")
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
