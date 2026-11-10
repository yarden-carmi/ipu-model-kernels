"""The calls layout must serve, held to the domain it declares.

The three concats mobilevit_s cvnets_in1k runs per forward are the ``CALLS``
below (20480, 65536 and 196608 elements -- ``cat((x, out), dim=1)`` at the
transformer's three patch sizes); each is far bigger than one 128-lane row and
the kernel takes a whole call in one launch, its loop stepping one row per word.
This test asks the registry for every call as the coverage database queries it,
for the shapes just outside the declared domain, checks that each call fits in
XMEM, runs the kernel twice back to back in one XMEM (the second reading the
first's y as its a, which is how a layer runs on the chip) and reads the
folder's ``kernelgen.toml``, the metadata the kernel generator writes.
"""

import json
from pathlib import Path

import numpy as np
import tomli as tomllib

from ipu_harness.chain import Chain
from ipu_harness.registry import Registry, kernel_tree

#: The calls found in the models surveyed, per forward at full depth:
#: cat((x, out), dim=1) over the 8x8x160, 16x16x128 and 32x32x96 patches.
CALLS = (
    {"kind": "concat", "numel": 20480},
    {"kind": "concat", "numel": 65536},
    {"kind": "concat", "numel": 196608},
)

#: The kinds the program renders, and the widest call it takes in one launch.
KINDS = ("concat", "copy")
MAX_NUMEL = 698880

#: The XMEM rows an NX8 call can address.
XMEM_ROWS = 16384


def _registry() -> Registry:
    """The registry of the kernel tree, this family only."""
    return Registry.load(kernel_tree(), families=["zoo"])


def _rows(call: dict) -> int:
    """The XMEM rows a call packs into: a, b and y (one row per 128 elements) and the mask."""
    return 3 * (-(-call["numel"] // 128)) + 1


def _operands(numel: int, seed: int = 3):
    """Two operands of the case's shape, over float64."""
    rng = np.random.default_rng(seed)
    return rng.uniform(-1, 1, (numel,)), rng.uniform(-1, 1, (numel,))


def test_every_call_routes_to_the_kernel():
    """Registry.resolve accepts each surveyed call as the host asks for it."""
    registry = _registry()
    for call in CALLS:
        verdict = registry.resolve("layout", **call)
        assert verdict, f"{call}: {verdict.reason}"
        assert verdict.kernel_name == "layout_concat"


def test_every_call_fits_in_xmem():
    """The calls the domain accepts are calls the launch can actually hold."""
    for call in CALLS:
        rows = _rows(call)
        assert rows <= XMEM_ROWS, f"{call} needs {rows} XMEM rows"


def test_the_whole_domain_fits_in_xmem():
    """Every corner of the declared range, not only the surveyed calls."""
    for numel in (256, 512, 1280, 4096, 20480, MAX_NUMEL):
        for kind in KINDS:
            call = {"kind": kind, "numel": numel}
            assert _registry().resolve("layout", **call), call
            assert _rows(call) <= XMEM_ROWS, call


def test_a_call_beyond_the_domain_is_refused():
    """The kernel refuses what its rows, its XMEM and its datapath cannot take."""
    registry = _registry()
    beyond = (
        {**CALLS[0], "numel": MAX_NUMEL + 256},  # above the declared maximum
        {**CALLS[0], "numel": 0},  # nothing to do, and the loop bound would underflow
        {**CALLS[0], "numel": 128},  # one row, which two operands cannot share
        {**CALLS[0], "numel": 1025},  # not a multiple of 256: the split leaves a row
        {**CALLS[1], "kind": "transpose"},  # a lane permutation the rows cannot make
        {**CALLS[1], "kind": "permute"},  # nor any other kind
        {**CALLS[1], "axis": 1},  # unknown parameter
        {**CALLS[1], "shapes": [20480]},  # unknown parameter
    )
    for call in beyond:
        verdict = registry.resolve("layout", **call)
        assert not verdict, f"{call} is above the domain but accepted: {verdict.reason}"


def test_the_domain_holds_the_largest_call():
    """The maxima are shapes the kernel really runs, and they are the maxima."""
    registry = _registry()
    for call in (
        {**CALLS[0], "numel": MAX_NUMEL},
        {**CALLS[0], "numel": 256},
        {**CALLS[0], "kind": "copy", "numel": MAX_NUMEL},
        {**CALLS[0], "kind": "copy", "numel": 256},
    ):
        verdict = registry.resolve("layout", **call)
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
    numel = 1024  # eight rows: four from each operand
    a, b = _operands(numel)
    for kind in KINDS:
        params = {"kind": kind, "numel": numel}
        chain = Chain("dynamic")
        first = chain.run("layout_concat", params, {"a": a, "b": b}, check=True)
        assert first.result.passed, f"{kind}: {first.result.describe()}"
        second = chain.run("layout_concat", params, {"a": first.resident["y"], "b": b}, check=True)
        assert second.result.passed, f"{kind} chained: {second.result.describe()}"


def test_the_rows_are_moved_end_to_end():
    """What y's rows must hold, read back from XMEM rather than from the report.

    The concat puts a's leading ``numel/2`` values first and b's after them, the
    copy a's ``numel`` values alone; either way y is the chip's activation
    layout, one row per 128 lanes, so the next kernel can read it as it stands.
    """
    numel = 512
    a, b = _operands(numel, seed=11)
    for kind in KINDS:
        chain = Chain("dynamic")
        step = chain.run("layout_concat", {"kind": kind, "numel": numel}, {"a": a, "b": b})
        assert step.result.passed, step.result.describe()
        stored = chain.read(step.resident["y"]).reshape(-1)[:numel]
        taken = numel if kind == "copy" else numel // 2
        want = [np.asarray(a, dtype=np.float64).reshape(-1)[:taken]]
        if kind == "concat":
            want.append(np.asarray(b, dtype=np.float64).reshape(-1)[:taken])
        want = np.concatenate((*want, np.zeros(numel - taken * len(want))))
        # The rows are stored in NX8, so the comparison is to one step of a
        # row's grid (a row of values in [-1, 1] has a step near 2^-7).
        assert np.abs(stored - want).max() < 0.05, kind


def test_the_kernelgen_metadata_says_what_the_kernel_does():
    """kernelgen.toml reads, and agrees with the kernel's own declarations."""
    folder = Path(__file__).parent
    with (folder / "kernelgen.toml").open("rb") as handle:
        gen = tomllib.load(handle)
    assert gen["kind"] == "exact"
    assert gen["method"] == "exact"
    assert gen["task"] == "layout_concat"
    assert gen["hw_clean"] is True, "an NX8 kernel whose stores are ACTIVATE.QUANTIZE"
    assert gen["host_steps"] == [], "the goal is every layer on the IPU"
    assert gen["chain_in"] == "a" and gen["chain_out"] == "y"
    asm = (folder / "layout_concat.asm").read_text(encoding="utf-8")
    assert "ACTIVATE.EXACT" not in asm
    assert "BREAK" not in asm
    assert "ACTIVATE.QUANTIZE" in asm, "the store is the hardware one"
    with (folder / "kernel.toml").open("rb") as handle:
        assert tomllib.load(handle)["kernel"]["op"] == "layout"
    for entry in gen["unsupported"]:
        head, sep, why = entry.partition("}: ")
        assert sep and why, entry
        params = json.loads(head + "}")
        assert params not in CALLS, entry  # every surveyed call is supported
        assert not _registry().resolve("layout", **params), entry
