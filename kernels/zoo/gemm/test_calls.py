"""The calls gemm must serve, held to the domain it declares.

The surveyed calls are the ``CALLS`` below: whisper-large-v3's eleven gemm
shapes (the FFN, the Q/K/V/O projections, the LM head at 51866 channels and the
1500-frame k=64 attention scores), the clip, t5 and MiniLM FFNs and the
mobilevit_s calls. Every loop of the program is dynamic, so each is one launch
at its real shape -- the program is a fixed ~15 words, the shape reaches it
through CRs only and XMEM is transparent, so a call's row count is not a
constraint on the program. This test asks the registry for every call exactly
as the coverage database queries it, for the shapes just outside the declared
domain, and it checks that the refusals are the declared ones. It also reads
the folder's ``kernelgen.toml``, the metadata the kernel generator writes.
"""

import json
from pathlib import Path

import tomli as tomllib

from ipu_harness.registry import Registry, kernel_tree

#: The calls found in the models surveyed, per forward at full depth. The
#: whisper set is the must-cover list; the rest are the other surveyed models'
#: whole-layer calls (or, for the largest, the host's tile of m).
CALLS = (
    {"act": "none", "bias": True, "k": 1280, "m": 1500, "n": 1280},   # whisper FFN in
    {"act": "none", "bias": True, "k": 1280, "m": 1500, "n": 5120},   # whisper FFN out
    {"act": "none", "bias": True, "k": 5120, "m": 1500, "n": 1280},   # whisper FFN down
    {"act": "none", "bias": False, "k": 1280, "m": 1500, "n": 1280},  # whisper O proj
    {"act": "none", "bias": False, "k": 64, "m": 1500, "n": 1500},    # whisper K @ Q
    {"act": "none", "bias": True, "k": 1280, "m": 32, "n": 1280},     # whisper 30 s tile
    {"act": "none", "bias": True, "k": 1280, "m": 32, "n": 5120},
    {"act": "none", "bias": True, "k": 5120, "m": 32, "n": 1280},
    {"act": "none", "bias": False, "k": 1280, "m": 32, "n": 51866},   # the LM head
    {"act": "none", "bias": False, "k": 64, "m": 32, "n": 1500},
    {"act": "none", "bias": False, "k": 1280, "m": 32, "n": 1280},
    {"act": "relu", "bias": True, "k": 1280, "m": 32, "n": 5120},     # the fused activation
    {"act": "none", "bias": True, "k": 768, "m": 50, "n": 3072},      # clip FFN in
    {"act": "none", "bias": True, "k": 3072, "m": 50, "n": 768},      # clip FFN down
    {"act": "none", "bias": False, "k": 512, "m": 64, "n": 2048},     # t5 FFN
    {"act": "none", "bias": True, "k": 384, "m": 256, "n": 1536},     # MiniLM FFN
    {"act": "none", "bias": False, "k": 36, "m": 4096, "n": 256},     # mobilevit_s stem
    {"act": "none", "bias": False, "k": 36, "m": 256, "n": 256},
    {"act": "none", "bias": True, "k": 144, "m": 1024, "n": 432},
    {"act": "none", "bias": True, "k": 192, "m": 256, "n": 576},
    {"act": "none", "bias": True, "k": 144, "m": 1024, "n": 144},
    {"act": "none", "bias": True, "k": 288, "m": 1024, "n": 144},
    {"act": "none", "bias": False, "k": 2880, "m": 64, "n": 160},     # mobilevit_s SE
    {"act": "none", "bias": True, "k": 640, "m": 1, "n": 1000},       # mobilevit_s classifier
    {"act": "none", "bias": True, "k": 192, "m": 256, "n": 384},
    {"act": "none", "bias": True, "k": 384, "m": 256, "n": 192},
    {"act": "none", "bias": True, "k": 144, "m": 1024, "n": 288},
    {"act": "none", "bias": False, "k": 96, "m": 1024, "n": 384},
    {"act": "none", "bias": True, "k": 512, "m": 256, "n": 2048},
    # The other surveyed models' whole-layer calls, direct in and out.
    {"act": "none", "bias": True, "k": 3072, "m": 50, "n": 768},   # clip FFN down
    {"act": "none", "bias": False, "k": 512, "m": 256, "n": 2048},  # t5 FFN, m tiled
    {"act": "none", "bias": False, "k": 36, "m": 4096, "n": 256},   # mobilevit_s stem, whole
    {"act": "none", "bias": True, "k": 144, "m": 1024, "n": 432},
    {"act": "none", "bias": True, "k": 144, "m": 1024, "n": 144},
    {"act": "none", "bias": True, "k": 288, "m": 1024, "n": 144},
    {"act": "none", "bias": False, "k": 96, "m": 1024, "n": 384},
)

#: The largest call the kernel takes in one launch, per dimension.
MAX_M = 4096
MAX_K = 5120
MAX_N = 51866


def _registry() -> Registry:
    """The registry of the kernel tree, this family only."""
    return Registry.load(kernel_tree(), families=["zoo"])


def test_every_call_routes_to_the_kernel():
    """Registry.resolve accepts each surveyed call as the host asks for it."""
    registry = _registry()
    for call in CALLS:
        verdict = registry.resolve("gemm", **call)
        assert verdict, f"{call}: {verdict.reason}"
        assert verdict.kernel_name == "gemm"


def test_every_call_fits_in_xmem():
    """Every call is one launch: the shape rides in CRs, not in the program."""
    for call in CALLS:
        verdict = _registry().resolve("gemm", **call)
        assert verdict, f"{call}: {verdict.reason}"


def test_the_whole_domain_fits_in_xmem():
    """Every corner of the declared range, not only the surveyed calls."""
    for m, k, n in ((1, 1, 1), (MAX_M, 1, 1), (1, MAX_K, 1), (1, 1, MAX_N),
                    (128, 128, 128), (MAX_M, MAX_K, MAX_N)):
        for bias in (False, True):
            call = {"act": "none", "bias": bias, "k": k, "m": m, "n": n}
            assert _registry().resolve("gemm", **call), call


def test_a_call_beyond_the_domain_is_refused():
    """The kernel refuses what its loops cannot take."""
    registry = _registry()
    beyond = (
        {**CALLS[0], "m": MAX_M + 1},  # above the declared maximum
        {**CALLS[0], "k": MAX_K + 1},
        {**CALLS[8], "n": MAX_N + 1},
        {**CALLS[0], "m": 0},  # nothing to do: the token loop's bound would underflow
        {**CALLS[0], "k": 0},
        {**CALLS[0], "n": 0},
        {**CALLS[0], "act": "silu"},  # not fused by this program (see kernelgen.toml)
        {**CALLS[0], "act": "gelu_tanh"},
        {"act": "none", "bias": False, "k": 1, "m": 1, "n": 1, "m_": 0},  # unknown parameter
        {**CALLS[0], "x_from": "heads:3:4:48"},  # arrangements (see kernelgen.toml)
        {**CALLS[0], "y_to": "patches:2"},
    )
    for call in beyond:
        verdict = registry.resolve("gemm", **call)
        assert not verdict, f"{call} is above the domain but accepted: {verdict.reason}"


def test_the_domain_holds_the_largest_call():
    """The maxima are shapes the kernel really runs, and they are the maxima."""
    registry = _registry()
    for call in (
        {"act": "none", "bias": False, "k": 128, "m": MAX_M, "n": 128},
        {"act": "none", "bias": True, "k": MAX_K, "m": 16, "n": 200},
        {"act": "none", "bias": False, "k": 1280, "m": 32, "n": MAX_N},
        {**CALLS[0], "m": MAX_M},  # the host's largest tile of the biggest call
    ):
        verdict = registry.resolve("gemm", **call)
        assert verdict, f"{call}: {verdict.reason}"
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
