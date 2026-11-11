"""The calls binary_add_row must serve, held to the domain it declares.

The bias adds of the surveyed models are the ``CALLS`` below (t5-small/clip
4096-wide, whisper-large-v3 1024-wide); each spans many rows of a and many
repeats of b, and the kernel takes a whole call in one launch. This test asks
the registry for every call as the coverage database queries it, for shapes
just outside the declared domain, and checks that each call fits in XMEM. It
also runs the kernel twice back to back in one XMEM, the second reading the
first's y as its a, and reads the folder's ``kernelgen.toml``.
"""

import json
from pathlib import Path

import numpy as np
import tomli as tomllib

from ipu_harness.chain import Chain
from ipu_harness.registry import Registry, kernel_tree

#: The calls found in the models surveyed, per forward at full depth.
CALLS = (
    {"op": "add", "broadcast": "row", "inner": 4096, "numel": 32768},
    {"op": "add", "broadcast": "row", "inner": 1024, "numel": 20480},
)

#: The ops the program renders, and the widest call it takes in one launch.
OPS = ("add", "sub", "mul", "max")
MAX_NUMEL = 262144
INNER_CHOICES = (128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 262144)

#: The XMEM rows an NX8 call can address.
XMEM_ROWS = 16384


def _registry() -> Registry:
    return Registry.load(kernel_tree(), families=["zoo"])


def _rows(call: dict) -> int:
    """a's, y's and b's rows plus the mask row."""
    return 2 * (-(-call["numel"] // 128)) + -(-call["inner"] // 128) + 1


def _operands(numel, inner, seed=3):
    rng = np.random.default_rng(seed)
    return rng.uniform(-1, 1, (numel,)), rng.uniform(-1, 1, (inner,))


def test_every_call_routes_to_the_kernel():
    registry = _registry()
    for call in CALLS:
        verdict = registry.resolve("binary", **call)
        assert verdict, f"{call}: {verdict.reason}"
        assert verdict.kernel_name == "binary_add_row"


def test_every_call_fits_in_xmem():
    for call in CALLS:
        assert _rows(call) <= XMEM_ROWS, call


def test_the_domain_holds_the_corners():
    registry = _registry()
    for call in (
        {"op": "add", "broadcast": "row", "inner": 128, "numel": 1},
        {"op": "add", "broadcast": "row", "inner": 128, "numel": 128},
        {"op": "add", "broadcast": "row", "inner": 4096, "numel": 1},
        {"op": "max", "broadcast": "row", "inner": 262144, "numel": MAX_NUMEL},
        {"op": "mul", "broadcast": "row", "inner": 4096, "numel": 32768},
    ):
        verdict = registry.resolve("binary", **call)
        assert verdict, f"{call}: {verdict.reason}"


def test_a_call_beyond_the_domain_is_refused():
    registry = _registry()
    beyond = (
        {**CALLS[0], "numel": MAX_NUMEL + 1},
        {**CALLS[0], "numel": 0},
        {**CALLS[0], "op": "div"},
        {**CALLS[0], "op": "min"},
        {**CALLS[0], "op": "and"},
        {**CALLS[0], "broadcast": "none", "inner": 0},
        {**CALLS[0], "broadcast": "col", "inner": 64},
        {**CALLS[0], "broadcast": "scalar", "inner": 1},
        {**CALLS[0], "inner": 384},  # three rows: no non-power-of-two wrap
        {**CALLS[0], "inner": 0},
        {**CALLS[0], "shapes": [15360]},
    )
    for call in beyond:
        verdict = registry.resolve("binary", **call)
        assert not verdict, f"{call} is outside the domain but accepted: {verdict.reason}"


def test_the_kernel_runs_after_itself_in_one_xmem():
    """The second run reads the first's y as its a, in the same registers."""
    numel, inner = 1000, 256
    a, b = _operands(numel, inner)
    for op in OPS:
        params = {"op": op, "broadcast": "row", "inner": inner, "numel": numel}
        chain = Chain("dynamic")
        first = chain.run("binary_add_row", params, {"a": a, "b": b}, check=True)
        assert first.result.passed, f"{op}: {first.result.describe()}"
        second = chain.run(
            "binary_add_row", params, {"a": first.resident["y"], "b": b}, check=True
        )
        assert second.result.passed, f"{op} chained: {second.result.describe()}"


def test_the_kernelgen_metadata_says_what_the_kernel_does():
    folder = Path(__file__).parent
    with (folder / "kernelgen.toml").open("rb") as handle:
        gen = tomllib.load(handle)
    assert gen["kind"] == "exact"
    assert gen["method"] == "exact"
    assert gen["task"] == "binary_add_row"
    assert gen["hw_clean"] is True
    assert gen["host_steps"] == []
    assert gen["chain_in"] == "a" and gen["chain_out"] == "y"
    asm = (folder / "binary_add_row.asm").read_text(encoding="utf-8")
    assert "ACTIVATE.EXACT" not in asm
    assert "BREAK" not in asm
    assert "ACTIVATE.QUANTIZE" in asm
    with (folder / "kernel.toml").open("rb") as handle:
        assert tomllib.load(handle)["kernel"]["op"] == "binary"
    registry = _registry()
    for entry in gen["unsupported"]:
        head, sep, why = entry.partition("}: ")
        assert sep and why, entry
        params = json.loads(head + "}")
        assert params not in CALLS, entry
        assert not registry.resolve("binary", **params), entry
