"""The calls reduce_rows must serve, held to the domain it declares.

The one reduction mobilevit_s cvnets_in1k runs per forward is the ``CALLS``
below (a mean over each of 640 rows of 64 values); it is far bigger than one
128-lane row, and the kernel takes the whole call in one launch -- its program
loops over the rows and, per row, over the row's 128-lane chunks. This test
asks the registry for every call as the coverage database queries it, for the
shapes just outside the declared domain, and it checks that each call really
fits in XMEM. It also runs a grid of the domain through the emulator, runs the
kernel twice back to back in one XMEM (the second reading the first's y as its
x) and reads the folder's ``kernelgen.toml``, the metadata the kernel
generator writes.
"""

import json
from pathlib import Path
from types import MappingProxyType

import numpy as np
import tomli as tomllib

from ipu_harness.chain import Chain
from ipu_harness.manifest import CaseDecl, load_manifest
from ipu_harness.packing import region_fill
from ipu_harness.params import plan_case
from ipu_harness.registry import Registry, kernel_tree

#: The calls found in the models surveyed, per forward at full depth.
CALLS = (
    {"kind": "mean", "n": 64, "rows": 640},
)

#: The kinds the program renders, and the corners of the two dimensions.
KINDS = ("sum", "mean", "max")
MAX_ROWS = 3072
MAX_N = 512

#: The XMEM rows an NX8 call can address.
XMEM_ROWS = 16384

#: The (rows, n) the test really runs through the emulator: the row-loop and
#: chunk corners -- a row of one lane, of one chunk, of a chunk and a lane, of
#: four chunks and a tail, one row, two rows and a group boundary -- every one
#: of them in all three kinds.
GRID = (
    (1, 1),
    (1, 128),
    (1, 129),
    (2, 2),
    (2, 256),
    (3, 511),
    (127, 64),
    (128, 1),
    (128, 128),
    (129, 63),
    (130, 130),
    (300, 200),
    (300, 384),
)


def _registry() -> Registry:
    """The registry of the kernel tree, this family only."""
    return Registry.load(kernel_tree(), families=["zoo"])


def _rows(call: dict) -> int:
    """The XMEM rows a call packs into: x (one row per 128 values), y (one per
    row of the matrix) and the 1/n and mask scratch rows."""
    return call["rows"] * (-(-call["n"] // 128)) + call["rows"] + 2


def _values(rows: int, n: int, seed: int = 3):
    """A (rows, n) matrix of the case's shape, over float64."""
    return np.random.default_rng(seed).uniform(-1, 1, (rows, n))


def _run(params: dict, seed: int = 3):
    """One call through the chain's model, held to the kernel's reference."""
    step = Chain("dynamic").run(
        "reduce_rows_mean", params, {"x": _values(params["rows"], params["n"], seed)}, check=True
    )
    assert step.result.passed, f"{params}: {step.result.describe()}"


def test_every_call_routes_to_the_kernel():
    """Registry.resolve accepts each surveyed call as the host asks for it."""
    registry = _registry()
    for call in CALLS:
        verdict = registry.resolve("reduce_rows", **call)
        assert verdict, f"{call}: {verdict.reason}"
        assert verdict.kernel_name == "reduce_rows_mean"


def test_every_call_fits_in_xmem():
    """The calls the domain accepts are calls the launch can actually hold."""
    for call in CALLS:
        rows = _rows(call)
        assert rows <= XMEM_ROWS, f"{call} needs {rows} XMEM rows"


def test_the_whole_domain_fits_in_xmem():
    """Every corner of the declared rectangle, not only the surveyed calls."""
    for rows in (1, 128, 129, MAX_ROWS):
        for n in (1, 64, 128, 129, MAX_N):
            for kind in KINDS:
                call = {"kind": kind, "rows": rows, "n": n}
                assert _registry().resolve("reduce_rows", **call), call
                assert _rows(call) <= XMEM_ROWS, call


def test_a_call_beyond_the_domain_is_refused():
    """The kernel refuses what its loops, its XMEM and its datapath cannot take."""
    registry = _registry()
    beyond = (
        {**CALLS[0], "rows": MAX_ROWS + 1},  # above the declared maximum
        {**CALLS[0], "n": MAX_N + 1},  # five chunks would need a longer unroll
        {**CALLS[0], "rows": 0},  # nothing to reduce, and the bound would underflow
        {**CALLS[0], "n": 0},  # an empty reduction: max of nothing
        {**CALLS[0], "kind": "min"},  # the accumulator has ADD, MAX and SUB only
        {**CALLS[0], "kind": "prod"},  # no product in the accumulator
        {**CALLS[0], "kind": "sum", "axis": 1},  # unknown parameter
    )
    for call in beyond:
        verdict = registry.resolve("reduce_rows", **call)
        assert not verdict, f"{call} is above the domain but accepted: {verdict.reason}"


def test_the_domain_holds_the_largest_call():
    """The maxima are shapes the kernel really runs, and they are the maxima."""
    registry = _registry()
    for call in (
        {"kind": "mean", "rows": MAX_ROWS, "n": MAX_N},
        {"kind": "sum", "rows": 1, "n": 1},
        {"kind": "max", "rows": 129, "n": 129},
    ):
        verdict = registry.resolve("reduce_rows", **call)
        assert verdict, f"{call}: {verdict.reason}"
        assert _rows(call) <= XMEM_ROWS, call


def test_the_kernel_runs_the_domain():
    """Every kind over the row-loop and chunk corners of the declared domain."""
    for i, (rows, n) in enumerate(GRID):
        for kind in KINDS:
            _run({"kind": kind, "rows": rows, "n": n}, seed=i)


def _words(params: dict) -> int:
    """The words the program retires for a call: the prologue, one word per x
    row of the loop, the last entity's straight-line chunks and the ``HALT``."""
    chunks = -(-params["n"] // 128)
    prologue = 3 + (1 if params["kind"] == "mean" else 0)
    loop = (params["rows"] - 1) * chunks if params["rows"] >= 2 else 0
    return prologue + loop + chunks + 1


def test_the_row_loop_is_one_word_per_row():
    """Every x row costs exactly one word: no separate load, reduce or store word.

    This also pins the loop's bound: one group too many would leave the last
    entity's chunks to a straight-line tail that stores past y's rows (the
    program loads one row ahead and stores what it multiplies).
    """
    for params in (
        {"kind": "mean", "rows": 640, "n": 64},
        {"kind": "sum", "rows": 1, "n": 511},
        {"kind": "max", "rows": 2, "n": 129},
        {"kind": "mean", "rows": 8, "n": 129},
        {"kind": "sum", "rows": 129, "n": 256},
    ):
        step = Chain("dynamic").run(
            "reduce_rows_mean",
            params,
            {"x": _values(params["rows"], params["n"])},
            check=True,
        )
        assert step.result.passed, f"{params}: {step.result.describe()}"
        assert step.result.cycles == _words(params), (
            params,
            step.result.cycles,
            _words(params),
        )


def test_the_program_writes_only_its_own_rows():
    """Nothing but y's rows changes: the prefetch stays inside x and no store
    lands on the scratch rows or on what the next kernel will read.

    A row outside y's region still holds what the harness wrote there (the
    inputs and the scratch fills), and every row no region owns is still the
    zero an empty XMEM holds.
    """
    params = {"kind": "mean", "rows": 40, "n": 100}
    chain = Chain("dynamic")
    step = chain.run("reduce_rows_mean", params, {"x": _values(40, 100)}, check=True)
    assert step.result.passed, step.result.describe()
    manifest = load_manifest(Path(__file__).parent)
    plan = plan_case(
        manifest,
        params,
        "dynamic",
        case=CaseDecl("canary", MappingProxyType(dict(params))),
    )
    placement = step.result.placement
    row_bytes = chain.format.row_bytes
    model = chain.model
    own = set()
    for tensor in plan.manifest.tensors.values():
        region = placement.region(tensor.name)
        own.update(range(region.base_row, region.end_row))
        if tensor.section == "scratch":
            want = region_fill(tensor, plan, region.rows)
            got = bytes(model.read_xmem(region.base_row * row_bytes, region.rows * row_bytes))
            assert got == want.data, f"{tensor.name}: the kernel wrote its scratch row"
    y = placement.region("y")
    for row in range(0, max(own) + 1):
        if row in own or row in range(y.base_row, y.end_row):
            continue
        assert bytes(model.read_xmem(row * row_bytes, row_bytes)) == b"\x00" * row_bytes, row


def test_the_kernel_reduces_what_the_rows_hold():
    """The reduced value is of the ``n`` stored lanes, and only of those."""
    rows, n = 3, 130  # two chunks, the last a lane short of a pair
    x = np.full((rows, n), 0.25)
    x[1, :] = -0.5
    x[2, 129] = 0.75  # the one lane past the first chunk
    params = {"kind": "max", "rows": rows, "n": n}
    step = Chain("dynamic").run("reduce_rows_mean", params, {"x": x}, check=True)
    assert step.result.passed, step.result.describe()
    got = np.asarray(step.result.outputs["y"]).reshape(-1)
    assert got[0] == 0.25 and got[1] == -0.5 and got[2] == 0.75, got


def test_the_kernel_runs_after_itself_in_one_xmem():
    """On the chip y is the next layer's input: a second run reads the first's rows.

    Both runs share one XMEM and one register file, so this is the chain the
    verifier builds: the second kernel's ``x`` is the first's ``y`` resident,
    exactly where and as it stored it, and nothing between them is a host step.
    The program sets every LR it reads, seeds R_ACC with the .FIRST accumulate
    of every row and loads its own mask row, so the registers the first run
    left behind cannot matter.
    """
    params = {"kind": "mean", "rows": 640, "n": 64}  # the surveyed call, one chunk per row
    x = _values(params["rows"], params["n"], seed=11)
    chain = Chain("dynamic")
    first = chain.run("reduce_rows_mean", params, {"x": x}, check=True)
    assert first.result.passed, first.result.describe()
    second = chain.run("reduce_rows_mean", params, {"x": first.resident["y"]}, check=True)
    assert second.result.passed, f"chained: {second.result.describe()}"


def test_the_program_is_hardware_clean():
    """Every store is the hardware one and no emulator-only instruction is used."""
    asm = (Path(__file__).parent / "reduce_rows_mean.asm").read_text(encoding="utf-8")
    assert "ACTIVATE.EXACT" not in asm
    assert "BREAK" not in asm
    assert "ACTIVATE.QUANTIZE" in asm
    assert "MULT.RC" in asm and "AGG." in asm


def test_the_kernelgen_metadata_says_what_the_kernel_does():
    """kernelgen.toml reads, and agrees with the kernel's own declarations."""
    folder = Path(__file__).parent
    with (folder / "kernelgen.toml").open("rb") as handle:
        gen = tomllib.load(handle)
    assert gen["kind"] == "exact"
    assert gen["method"] == "exact"
    assert gen["task"] == "reduce_rows_mean"
    assert gen["hw_clean"] is True, "an NX8 kernel whose stores are ACTIVATE.QUANTIZE"
    assert gen["host_steps"] == [], "the goal is every layer on the IPU"
    assert gen["chain_in"] == "x" and gen["chain_out"] == "y"
    with (folder / "kernel.toml").open("rb") as handle:
        assert tomllib.load(handle)["kernel"]["op"] == "reduce_rows"
    for entry in gen["unsupported"]:
        head, sep, why = entry.partition("}: ")
        assert sep and why, entry
        params = json.loads(head + "}")
        assert params not in CALLS, entry  # every surveyed call is supported
        assert not _registry().resolve("reduce_rows", **params), entry
