"""The calls gemm must serve, held to the domain it declares.

The surveyed mobilevit_s CVNets calls are the ``CALLS`` below. Each is bigger
than one tile of the kernel in some dimension (tokens, output channels), so the
host launches the kernel once per tile of those; this test asks the registry for
every tile of every call, and for the oversized whole call, which the kernel
must refuse rather than pretend to take. It also reads the folder's
``kernelgen.toml``, the metadata the kernel generator writes.
"""

import json
from pathlib import Path

import tomli as tomllib

from ipu_harness.registry import Registry, kernel_tree

#: The calls found in the models surveyed, per forward at full depth.
CALLS = (
    {"act": "none", "bias": False, "k": 64, "m": 4096, "n": 256},
    {"act": "none", "bias": False, "k": 1728, "m": 1024, "n": 96},
    {"act": "none", "bias": False, "k": 36, "m": 256, "n": 256},
    {"act": "none", "bias": True, "k": 144, "m": 1024, "n": 432},
    {"act": "none", "bias": True, "k": 192, "m": 256, "n": 576},
    {"act": "none", "bias": False, "k": 864, "m": 1024, "n": 96},
    {"act": "none", "bias": False, "k": 2880, "m": 64, "n": 160},
    {"act": "none", "bias": True, "k": 640, "m": 1, "n": 1000},
    {"act": "none", "bias": True, "k": 144, "m": 1024, "n": 288},
    {"act": "none", "bias": True, "k": 288, "m": 1024, "n": 144},
    {"act": "none", "bias": True, "k": 192, "m": 256, "n": 384},
    {"act": "none", "bias": True, "k": 384, "m": 256, "n": 192},
)

#: The largest tile the kernel takes in one call, per dimension.
TILE_M = 128
TILE_N = 128


def _registry() -> Registry:
    """The registry of the kernel tree, this family only."""
    return Registry.load(kernel_tree(), families=["zoo"])


def _tiles(size: int, tile: int) -> list[int]:
    """The sizes of the tiles of ``size``, the last one possibly short."""
    return [min(tile, size - i) for i in range(0, size, tile)]


def test_every_tile_of_every_call_routes_to_the_kernel():
    """Registry.resolve accepts each launch the host makes for the calls."""
    registry = _registry()
    for call in CALLS:
        for m in _tiles(call["m"], TILE_M):
            for n in _tiles(call["n"], TILE_N):
                tile = {**call, "m": m, "n": n}
                verdict = registry.resolve("gemm", **tile)
                assert verdict, f"{tile}: {verdict.reason}"
                assert verdict.kernel_name == "gemm"


def test_a_call_wider_than_the_tile_is_refused():
    """The kernel does not claim a whole call it cannot hold in one launch."""
    registry = _registry()
    for call in CALLS:
        if call["m"] <= TILE_M and call["n"] <= TILE_N:
            continue
        verdict = registry.resolve("gemm", **call)
        assert not verdict, f"{call} is above the tile but accepted: {verdict.reason}"


def test_the_domain_holds_the_largest_tile():
    """The maxima are a tile the kernel really runs: m 128, n 128, k 2944."""
    verdict = _registry().resolve("gemm", act="none", bias=True, k=2944, m=128, n=128)
    assert verdict, verdict.reason
    assert not _registry().resolve("gemm", act="none", bias=False, k=2945, m=1, n=1)


def test_the_kernelgen_metadata_says_what_the_kernel_does():
    """kernelgen.toml reads, and agrees with the kernel's own declarations."""
    folder = Path(__file__).parent
    with (folder / "kernelgen.toml").open("rb") as handle:
        gen = tomllib.load(handle)
    assert gen["kind"] == "exact"
    assert gen["method"] == "exact"
    assert gen["task"] == "gemm"
    assert gen["hw_clean"] is True
    assert gen["host_steps"] == [], "the goal is every layer on the IPU"
    assert "ACTIVATE.EXACT" not in (folder / "gemm.asm").read_text(encoding="utf-8")
    with (folder / "kernel.toml").open("rb") as handle:
        assert tomllib.load(handle)["kernel"]["op"] == gen["task"]
    for entry in gen["unsupported"]:
        head, sep, why = entry.partition("}: ")
        assert sep and why, entry
        params = json.loads(head + "}")
        assert params in CALLS, entry  # the surveyed calls, and only they
