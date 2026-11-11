"""The calls layout_copy must serve, held to the domain it declares.

The one surveyed call (openai/whisper-large-v3, 32 elements) is `CALLS` below;
this test asks the registry for it as the coverage database queries it, checks
the domain's corners fit in XMEM, that calls beyond the domain are refused,
and runs the kernel twice back to back in one XMEM -- the second reading the
first's y as its x, which is how the verifier chains it. It also reads the
folder's ``kernelgen.toml``.
"""

import json
from pathlib import Path

import numpy as np
import tomli as tomllib

from ipu_harness.chain import Chain
from ipu_harness.registry import Registry, kernel_tree

#: The calls found in the models surveyed, per forward at full depth.
CALLS = (
    {"kind": "copy", "numel": 32},
)

#: The XMEM rows an NX8 call can address.
XMEM_ROWS = 16384


def _registry() -> Registry:
    """The registry of the kernel tree, this family only."""
    return Registry.load(kernel_tree(), families=["zoo"])


def _rows(call: dict) -> int:
    """The XMEM rows a call packs into: x, y (one row per 128 elements) and the mask."""
    return 2 * (-(-call["numel"] // 128)) + 1


def _operand(numel: int, seed: int = 3):
    """One operand of the case's shape, over float64."""
    rng = np.random.default_rng(seed)
    return rng.uniform(-1, 1, (numel,))


def test_every_call_routes_to_the_kernel():
    """Registry.resolve accepts the surveyed call as the host asks for it."""
    registry = _registry()
    for call in CALLS:
        verdict = registry.resolve("layout", **call)
        assert verdict, f"{call}: {verdict.reason}"
        assert verdict.kernel_name == "layout_copy"


def test_every_call_fits_in_xmem():
    """The calls the domain accepts are calls the launch can actually hold."""
    for call in CALLS:
        assert _rows(call) <= XMEM_ROWS, f"{call} needs {rows} XMEM rows"


def test_the_domain_holds_its_corners():
    """The maxima are shapes the kernel really runs, and they are the maxima."""
    registry = _registry()
    for call in (
        {"kind": "copy", "numel": 1},
        {"kind": "copy", "numel": 128},
        {"kind": "copy", "numel": 129},
        {"kind": "copy", "numel": 262144},
    ):
        verdict = registry.resolve("layout", **call)
        assert verdict, f"{call}: {verdict.reason}"
        assert _rows(call) <= XMEM_ROWS, call


def test_a_call_beyond_the_domain_is_refused():
    """The kernel refuses what its domain and its datapath cannot take."""
    registry = _registry()
    beyond = (
        {"kind": "copy", "numel": 262145},  # above the declared maximum
        {"kind": "copy", "numel": 0},  # nothing to move, rows - 1 underflows
        {"kind": "transpose", "numel": 15360},  # lane permutation across rows (kernelgen.toml)
        {"kind": "concat", "numel": 15360},  # two inputs and a split (kernelgen.toml)
        {"kind": "gather", "numel": 32},  # not a layout op at all
        {"kind": "copy", "numel": 32, "inner": 4},  # unknown parameter
    )
    for call in beyond:
        verdict = registry.resolve("layout", **call)
        assert not verdict, f"{call} is beyond the domain but accepted: {verdict.reason}"


def test_the_kernel_runs_after_itself_in_one_xmem():
    """On the chip y is the next layer's input: a second run reads the first's rows.

    Both runs share one XMEM and one register file, so this is the chain the
    verifier builds: the second kernel's ``x`` is the first's ``y`` resident,
    exactly where and as it stored it, and nothing between them is a host step.
    The program sets every LR it reads and loads its own mask row, so the
    registers the first run left behind cannot matter.
    """
    for numel in (32, 1, 128, 129, 1000):  # the surveyed call and the corners
        x = _operand(numel)
        params = {"kind": "copy", "numel": numel}
        chain = Chain("dynamic")
        first = chain.run("layout_copy", params, {"x": x}, check=True)
        assert first.result.passed, f"{numel}: {first.result.describe()}"
        second = chain.run("layout_copy", params, {"x": first.resident["y"]}, check=True)
        assert second.result.passed, f"{numel} chained: {second.result.describe()}"


def test_the_kernelgen_metadata_says_what_the_kernel_does():
    """kernelgen.toml reads, and agrees with the kernel's own declarations."""
    folder = Path(__file__).parent
    with (folder / "kernelgen.toml").open("rb") as handle:
        gen = tomllib.load(handle)
    assert gen["kind"] == "exact"
    assert gen["method"] == "exact"
    assert gen["task"] == "layout_copy"
    assert gen["hw_clean"] is True, "an NX8 kernel whose stores are ACTIVATE.QUANTIZE"
    assert gen["host_steps"] == [], "the goal is every layer on the IPU"
    assert gen["chain_in"] == "x" and gen["chain_out"] == "y"
    asm = (folder / "layout_copy.asm").read_text(encoding="utf-8")
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
