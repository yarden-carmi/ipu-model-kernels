"""The calls conv2d must serve, held to the domain it declares.

The four depthwise convolutions mobilevit_s cvnets_in1k runs per forward are the
``CALLS`` below: 128 channels at a 128x128 grid, 256 at 64x64, 384 at 32x32 and
512 at 16x16, each 3x3, stride 2, same padding, with a bias. Each is far bigger
than one 128-lane row in every dimension, and the kernel takes a whole call in
one launch -- its program loops over the output rows, the pixels of a row and
the channel chunks, and the shape reaches it through CRs only. This test asks
the registry for every call as the coverage database queries it, for the
signatures just outside the declared domain, checks that each call really fits
in the XMEM rows an FP32 program addresses, runs the kernel twice back to back
in one XMEM (the second launch reading the first's y as its x), and reads the
folder's ``kernelgen.toml``, the metadata the kernel generator writes.
"""

import json
from pathlib import Path

import numpy as np
import tomli as tomllib

from ipu_harness.chain import Chain
from ipu_harness.registry import Registry, kernel_tree

#: The calls found in the models surveyed, per forward at full depth.
CALLS = (
    {
        "bias": True,
        "cin": 128,
        "cout": 128,
        "groups": 128,
        "h": 128,
        "kh": 3,
        "kw": 3,
        "padding": 1,
        "stride": 2,
        "w": 128,
    },
    {
        "bias": True,
        "cin": 256,
        "cout": 256,
        "groups": 256,
        "h": 64,
        "kh": 3,
        "kw": 3,
        "padding": 1,
        "stride": 2,
        "w": 64,
    },
    {
        "bias": True,
        "cin": 384,
        "cout": 384,
        "groups": 384,
        "h": 32,
        "kh": 3,
        "kw": 3,
        "padding": 1,
        "stride": 2,
        "w": 32,
    },
    {
        "bias": True,
        "cin": 512,
        "cout": 512,
        "groups": 512,
        "h": 16,
        "kh": 3,
        "kw": 3,
        "padding": 1,
        "stride": 2,
        "w": 16,
    },
)

#: The widest window, stride and padding the program renders, and the channel ceiling.
MAX_HW = 128
MAX_CIN = 512
MAX_KH = 3
MAX_STRIDE = 4
MAX_PADDING = 2

#: The XMEM rows a call can address in FP32 (512 MB of 512-byte rows). The same
#: program in NX8 addresses 16384, which the widest call's x alone fills.
XMEM_ROWS = 1048576


def _registry() -> Registry:
    """The registry of the kernel tree, this family only."""
    return Registry.load(kernel_tree(), families=["zoo"])


def _rows(call: dict) -> int:
    """The XMEM rows a call packs into: x, y, the taps' weight rows, the bias
    row, the mask row and the zeros row."""
    chunks = -(-call["cin"] // 128)
    out_h = (call["h"] + 2 * call["padding"] - call["kh"]) // call["stride"] + 1
    out_w = (call["w"] + 2 * call["padding"] - call["kw"]) // call["stride"] + 1
    return chunks * (call["h"] * call["w"] + out_h * out_w + call["kh"] * call["kw"] + 1) + 2


def _operands(call: dict, seed: int = 3):
    """x, the weights and the bias of the case's shape, over float64."""
    rng = np.random.default_rng(seed)
    cin, cout, groups = call["cin"], call["cout"], call["groups"]
    shape = (call["h"], call["w"], cin)
    return (
        rng.uniform(-1, 1, shape),
        rng.uniform(-1, 1, (cout, cin // groups, call["kh"], call["kw"])),
        rng.uniform(-1, 1, (1, cout)),
    )


def test_every_call_routes_to_the_kernel():
    """Registry.resolve accepts each surveyed call as the host asks for it."""
    registry = _registry()
    for call in CALLS:
        verdict = registry.resolve("conv2d", **call)
        assert verdict, f"{call}: {verdict.reason}"
        assert verdict.kernel_name == "conv2d_depthwise"


def test_every_call_fits_in_xmem():
    """The calls the domain accepts are calls the launch can actually hold.

    A 128x128 grid of 128-channel pixels is the widest surveyed call: its x is
    16384 rows and its y 4096 more, 20492 of the 1048576 FP32 rows the addressable
    space holds. The same call has no placement in NX8, where a program addresses
    16384 rows (2 MB) in total and the x alone is that many -- the reason the
    kernel declares ``formats = ["fp32"]`` -- so the assertion here is that every
    surveyed call needs no tiling at all: one launch, its own loops.
    """
    for call in CALLS:
        rows = _rows(call)
        assert rows <= XMEM_ROWS, f"{call} needs {rows} XMEM rows"


def test_the_whole_domain_fits_in_xmem():
    """Every corner of the declared range that XMEM holds, not only the surveyed calls."""
    registry = _registry()
    for cin in (1, 128, 256, 512):
        for h, w in ((1, 1), (7, 5), (16, 16), (32, 32)):
            call = {
                "bias": True,
                "cin": cin,
                "cout": cin,
                "groups": cin,
                "h": h,
                "kh": 3,
                "kw": 3,
                "padding": 1,
                "stride": 2,
                "w": w,
            }
            assert registry.resolve("conv2d", **call), call
            assert _rows(call) <= XMEM_ROWS, call


def test_a_call_beyond_the_domain_is_refused():
    """The kernel refuses what its loops, its XMEM and its datapath cannot take."""
    registry = _registry()
    base = CALLS[3]
    beyond = (
        {**base, "h": MAX_HW + 1},  # above the declared maximum
        {**base, "w": 0},  # nothing to convolve
        {**base, "cin": MAX_CIN + 1},  # a fifth rendered chunk: over the 1024-word program
        {**base, "kh": MAX_KH + 1},  # a window the taps of this program do not cover
        {**base, "kw": 0},
        {**base, "stride": MAX_STRIDE + 1},
        {**base, "padding": MAX_PADDING + 1},
        {**base, "stride": 1, "padding": 2},  # two taps clamp: padding > stride
        {**base, "groups": 1},  # a dense conv: cin / groups > 1
        {**base, "groups": 256},  # a grouped conv: not one filter per channel
        {**base, "cout": 256},  # cout != cin: not depthwise
        {**base, "cin": 256, "groups": 256},  # ... the same from the other side
        {**base, "dtype": "fp16"},  # unknown parameter
    )
    for call in beyond:
        verdict = registry.resolve("conv2d", **call)
        assert not verdict, f"{call} is above the domain but accepted: {verdict.reason}"


def test_the_domain_holds_the_largest_call():
    """The maxima are shapes the kernel really runs, and they are the maxima."""
    registry = _registry()
    for call in (
        {**CALLS[3], "h": MAX_HW, "w": 1, "cin": MAX_CIN, "cout": MAX_CIN, "groups": MAX_CIN},
        {**CALLS[0], "h": 1, "w": 1, "kh": 1, "kw": 1, "stride": MAX_STRIDE, "padding": 0},
        {**CALLS[2], "cin": 1, "cout": 1, "groups": 1, "bias": False},
    ):
        verdict = registry.resolve("conv2d", **call)
        assert verdict, f"{call}: {verdict.reason}"


def test_the_kernel_runs_after_itself_in_one_xmem():
    """On the chip y is the next layer's input: a second run reads the first's rows.

    Both runs share one XMEM and one register file, so this is the chain the
    verifier builds: the second kernel's ``x`` is the first's ``y`` resident,
    exactly where and as it stored it, with no repack between them. The 16x16
    grid at stride 2 gives an 8x8 grid, which is the second launch's input grid,
    so the two calls chain without a host step. The program sets every LR it
    reads, opens every output row with an ``ACC.*.FIRST`` and loads its own mask
    and zero rows, so the registers the first run left behind cannot matter.
    """
    wide = {"kh": 3, "kw": 3, "stride": 2, "padding": 1, "bias": True}
    for first, second in ((16, 8), (12, 6), (9, 5)):
        for cin in (128, 300):
            a = {**wide, "h": first, "w": first, "cin": cin, "cout": cin, "groups": cin}
            b = {**wide, "h": second, "w": second, "cin": cin, "cout": cin, "groups": cin}
            assert (a["h"] + 2 - a["kh"]) // a["stride"] + 1 == b["h"], (
                f"{first}x{first} at stride 2 is not {second}x{second}"
            )
            x, wt, bias = _operands(a)
            x2, wt2, bias2 = _operands(b, seed=7)
            chain = Chain("fp32")
            step1 = chain.run("conv2d_depthwise", a, {"x": x, "wt": wt, "b": bias}, check=True)
            assert step1.result.passed, f"{cin}/{first}: {step1.result.describe()}"
            step2 = chain.run(
                "conv2d_depthwise",
                b,
                {"x": step1.resident["y"], "wt": wt2, "b": bias2},
                check=True,
            )
            assert step2.result.passed, f"{cin}/{first} chained: {step2.result.describe()}"


def test_the_surveyed_calls_chain_at_their_real_shape():
    """Each surveyed call runs, and the layer after it reads its rows in place.

    This is the verifier's own check at the calls' real shapes: one launch per
    call in a shared XMEM, then a second launch whose ``x`` is the first's ``y``
    where and as it stored it (the output grid of the first is the input grid of
    the second, at stride 2), with no host step between them.
    """
    for call in CALLS:
        out_h = (call["h"] + 2 * call["padding"] - call["kh"]) // call["stride"] + 1
        out_w = (call["w"] + 2 * call["padding"] - call["kw"]) // call["stride"] + 1
        x, wt, bias = _operands(call)
        follow = {**call, "h": out_h, "w": out_w}
        x2, wt2, bias2 = _operands(follow, seed=11)
        chain = Chain("fp32")
        first = chain.run("conv2d_depthwise", call, {"x": x, "wt": wt, "b": bias}, check=True)
        assert first.result.passed, f"{call}: {first.result.describe()}"
        second = chain.run(
            "conv2d_depthwise",
            follow,
            {"x": first.resident["y"], "wt": wt2, "b": bias2},
            check=True,
        )
        assert second.result.passed, f"{call} chained: {second.result.describe()}"


def test_the_same_call_chains_twice_verbatim():
    """The verifier's own shape of chain: the same call, its y read back as x.

    A conv changes the grid, so this is only shape-consistent where out_h == h
    and out_w == w (stride 1 with a 1x1 window); the call below is that corner,
    and it is chained exactly as the coverage verifier chains it -- the second
    launch's ``x`` pinned where the first wrote ``y``.
    """
    call = {
        "bias": True,
        "cin": 128,
        "cout": 128,
        "groups": 128,
        "h": 12,
        "w": 12,
        "kh": 1,
        "kw": 1,
        "padding": 0,
        "stride": 1,
    }
    x, wt, bias = _operands(call)
    chain = Chain("fp32")
    first = chain.run("conv2d_depthwise", call, {"x": x, "wt": wt, "b": bias}, check=True)
    assert first.result.passed, first.result.describe()
    second = chain.run(
        "conv2d_depthwise",
        call,
        {"x": first.resident["y"], "wt": wt, "b": bias},
        check=True,
    )
    assert second.result.passed, f"verbatim chain: {second.result.describe()}"


def test_the_kernelgen_metadata_says_what_the_kernel_does():
    """kernelgen.toml reads, and agrees with the kernel's own declarations."""
    folder = Path(__file__).parent
    with (folder / "kernelgen.toml").open("rb") as handle:
        gen = tomllib.load(handle)
    assert gen["kind"] == "exact"
    assert gen["method"] == "exact"
    assert gen["task"] == "conv2d_depthwise"
    assert gen["hw_clean"] is True, "an FP32 kernel whose stores are ACTIVATE.QUANTIZE"
    assert gen["host_steps"] == [], "the goal is every layer on the IPU"
    assert gen["chain_in"] == "x" and gen["chain_out"] == "y"
    asm = (folder / "conv2d_depthwise.asm").read_text(encoding="utf-8")
    assert "ACTIVATE.EXACT" not in asm
    assert "BREAK" not in asm
    assert "ACTIVATE.QUANTIZE" in asm, "the store is the hardware one"
    with (folder / "kernel.toml").open("rb") as handle:
        assert tomllib.load(handle)["kernel"]["op"] == "conv2d"
    for entry in gen["unsupported"]:
        head, sep, why = entry.partition("}: ")
        assert sep and why, entry
        params = json.loads(head + "}")
        assert params not in CALLS, entry  # every surveyed call is supported
        assert not _registry().resolve("conv2d", **params), entry
