"""The calls gemm must serve, held to the domain it declares.

The surveyed mobilevit_s CVNets calls are the ``CALLS`` below: each is bigger
than one 128 x 128 tile in tokens, output channels or both, and the kernel
takes a whole call in one launch (its program loops over the tokens, the
output-channel tiles and the k chunks). This test asks the registry for every
call as the coverage database queries it, for the shapes just outside the
declared domain, and it checks that each call really fits in XMEM. It also
reads the folder's ``kernelgen.toml``, the metadata the kernel generator writes.
"""

import json
from pathlib import Path

import tomli as tomllib

from ipu_harness.registry import Registry, kernel_tree

#: The calls found in the models surveyed, per forward at full depth.
CALLS = (
    {"act": "none", "bias": False, "k": 64, "m": 4096, "n": 256},
    {"act": "none", "bias": False, "k": 36, "m": 256, "n": 256},
    {"act": "none", "bias": True, "k": 144, "m": 1024, "n": 432},
    {"act": "none", "bias": True, "k": 192, "m": 256, "n": 576},
    {"act": "none", "bias": True, "k": 144, "m": 1024, "n": 288},
    {"act": "none", "bias": True, "k": 288, "m": 1024, "n": 144},
    {"act": "none", "bias": False, "k": 2880, "m": 64, "n": 160},
    {"act": "none", "bias": True, "k": 640, "m": 1, "n": 1000},
    {"act": "none", "bias": True, "k": 192, "m": 256, "n": 384},
    {"act": "none", "bias": True, "k": 384, "m": 256, "n": 192},
    {"act": "none", "bias": True, "k": 144, "m": 1024, "n": 144},
    {"act": "none", "bias": False, "k": 96, "m": 1024, "n": 384},
)

#: The largest call the kernel takes in one launch, per dimension.
MAX_M = 4096
MAX_K = 2944
MAX_N = 1024

#: The XMEM rows an NX8 call can address.
XMEM_ROWS = 16384


def _registry() -> Registry:
    """The registry of the kernel tree, this family only."""
    return Registry.load(kernel_tree(), families=["zoo"])


def _rows(call: dict) -> int:
    """The XMEM rows a call packs into: a, w, b and y, each row-granular."""
    m, k, n = call["m"], call["k"], call["n"]
    chunks = -(-k // 128)  # a's rows per token
    wtiles = -(-(n + 1) // 128)  # w's rows per input (the +1 column pads the tile)
    ytiles = -(-n // 128)  # y's rows per token (one per channel tile)
    rows = m * chunks + (k + 1) * wtiles + m * ytiles
    return rows + (ytiles if call["bias"] else 0)


def test_every_call_routes_to_the_kernel():
    """Registry.resolve accepts each surveyed call as the host asks for it."""
    registry = _registry()
    for call in CALLS:
        verdict = registry.resolve("gemm", **call)
        assert verdict, f"{call}: {verdict.reason}"
        assert verdict.kernel_name == "gemm"


def test_every_call_fits_in_xmem():
    """The calls the domain accepts are calls the launch can actually hold."""
    for call in CALLS:
        rows = _rows(call)
        assert rows <= XMEM_ROWS, f"{call} needs {rows} XMEM rows"


def test_a_call_beyond_the_domain_is_refused():
    """The kernel refuses what its loops and XMEM cannot take."""
    registry = _registry()
    beyond = (
        {**CALLS[0], "m": MAX_M + 1},
        {**CALLS[6], "k": MAX_K + 1},
        {**CALLS[7], "n": MAX_N + 1},
        {"act": "none", "bias": False, "k": 1, "m": 1, "n": 1, "m_": 0},  # unknown parameter
        {**CALLS[0], "act": "relu"},  # nothing is fused
    )
    for call in beyond:
        verdict = registry.resolve("gemm", **call)
        assert not verdict, f"{call} is above the domain but accepted: {verdict.reason}"


def test_the_domain_holds_the_largest_call():
    """The maxima are shapes the kernel really runs, and they are the maxima."""
    registry = _registry()
    # The widest call the default- and nightly-tier cases run, one per dimension.
    for call in (
        {"act": "none", "bias": False, "k": 128, "m": MAX_M, "n": 128},
        {"act": "none", "bias": True, "k": MAX_K, "m": 16, "n": 200},
        {"act": "none", "bias": False, "k": 64, "m": 4096, "n": 256},
    ):
        verdict = registry.resolve("gemm", **call)
        assert verdict, f"{call}: {verdict.reason}"
        assert _rows(call) <= XMEM_ROWS, call
    assert not registry.resolve("gemm", act="none", bias=False, k=MAX_K + 1, m=1, n=1)
    assert not registry.resolve("gemm", act="none", bias=False, k=1, m=1, n=0)


def test_the_kernelgen_metadata_says_what_the_kernel_does():
    """kernelgen.toml reads, and agrees with the kernel's own declarations."""
    folder = Path(__file__).parent
    with (folder / "kernelgen.toml").open("rb") as handle:
        gen = tomllib.load(handle)
    assert gen["kind"] == "exact"
    assert gen["method"] == "exact"
    assert gen["task"] == "gemm"
    assert gen["hw_clean"] is True, "an NX8 variant with ACTIVATE.QUANTIZE stores"
    assert gen["host_steps"] == [], "the goal is every layer on the IPU"
    assert "ACTIVATE.EXACT" not in (folder / "gemm.asm").read_text(encoding="utf-8")
    assert "BREAK" not in (folder / "gemm.asm").read_text(encoding="utf-8")
    with (folder / "kernel.toml").open("rb") as handle:
        assert tomllib.load(handle)["kernel"]["op"] == gen["task"]
    for entry in gen["unsupported"]:
        head, sep, why = entry.partition("}: ")
        assert sep and why, entry
        params = json.loads(head + "}")
        assert params not in CALLS, entry  # every surveyed call is supported
        assert not _registry().resolve("gemm", **params), entry
