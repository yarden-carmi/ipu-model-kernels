"""The calls unary_gelu must serve, held to the domain it declares.

The must-cover call is sentence-transformers/all-MiniLM-L6-v2's gelu (393216
elements, x6 per forward); the kernel takes a whole call in one launch -- its
program loops over the rows. This test asks the registry for that call, for the
corners of the declared domain, and it checks that the call fits in XMEM. It
also runs the kernel twice back to back in one XMEM, the second reading the
first's y as its x, and reads the folder's ``kernelgen.toml``.
"""

import tomli as tomllib
from pathlib import Path

import numpy as np

from ipu_harness.chain import Chain
from ipu_harness.registry import Registry, kernel_tree

#: The must-cover call.
CALL = {"fn": "gelu", "numel": 393216}

#: The XMEM rows an NX8 call can address.
XMEM_ROWS = 16384

MAX_NUMEL = 524160  # 4095 rows: 4*rows + 2 <= 16384


def _registry() -> Registry:
    """The registry of the kernel tree, this family only."""
    return Registry.load(kernel_tree(), families=["zoo"])


def _rows(numel: int) -> int:
    """The XMEM rows a call packs into: x, y and the two row registers."""
    return 4 * (-(-numel // 128)) + 2


def test_the_call_routes_to_the_kernel():
    verdict = _registry().resolve("unary", **CALL)
    assert verdict, f"{CALL}: {verdict.reason}"
    assert verdict.kernel_name == "unary_gelu"


def test_the_domain_corners_resolve():
    for numel in (1, 127, 128, 129, 4096, MAX_NUMEL):
        call = {"fn": "gelu", "numel": numel}
        assert _registry().resolve("unary", **call), call
        assert _rows(numel) <= XMEM_ROWS, call


def test_a_call_beyond_the_domain_is_refused():
    registry = _registry()
    for call in (
        {"fn": "gelu", "numel": MAX_NUMEL + 1},
        {"fn": "gelu", "numel": 0},
        {"fn": "erf", "numel": 1000},
    ):
        verdict = registry.resolve("unary", **call)
        assert not verdict, f"{call} is outside the domain but accepted: {verdict.reason}"


def test_the_kernel_runs_after_itself_in_one_xmem():
    """On the chip y is the next layer's input: a second run reads the first's rows."""
    numel = 1000  # eight rows, the last a short one
    x = np.random.default_rng(3).uniform(-1, 1, (numel,))
    chain = Chain("dynamic")
    first = chain.run("unary_gelu", {"fn": "gelu", "numel": numel}, {"x": x}, check=True)
    assert first.result.passed, first.result.describe()
    second = chain.run(
        "unary_gelu", {"fn": "gelu", "numel": numel}, {"x": first.resident["y"]}, check=True
    )
    assert second.result.passed, second.result.describe()


def test_the_kernelgen_metadata_says_what_the_kernel_does():
    folder = Path(__file__).parent
    with (folder / "kernelgen.toml").open("rb") as handle:
        gen = tomllib.load(handle)
    assert gen["kind"] == "estimation"
    assert gen["method"] == "tanh_exp2"
    assert gen["task"] == "unary_gelu"
    assert gen["hw_clean"] is True
    assert gen["host_steps"] == []
    assert gen["chain_in"] == "x" and gen["chain_out"] == "y"
    asm = (folder / "unary_gelu.asm").read_text(encoding="utf-8")
    assert "ACTIVATE.EXACT" not in asm
    assert "BREAK" not in asm
    assert "ACTIVATE.QUANTIZE" in asm
    with (folder / "kernel.toml").open("rb") as handle:
        assert tomllib.load(handle)["kernel"]["op"] == "unary"
