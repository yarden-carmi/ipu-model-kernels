"""unary_abs's checks beyond the case runs: the must-cover call, and the chain.

The verifier runs the kernel twice in one XMEM, the second reading the first's
y as its x; this file checks the same thing locally, plus that the t5-small
call resolves to this kernel.
"""

import numpy as np

from ipu_harness.chain import Chain
from ipu_harness.registry import Registry, kernel_tree


def _operands(numel: int, seed: int = 3):
    rng = np.random.default_rng(seed)
    return rng.uniform(-1, 1, (numel,))


def test_the_must_cover_call_routes_to_the_kernel():
    registry = Registry.load(kernel_tree(), families=["zoo"])
    verdict = registry.resolve("unary", fn="abs", numel=65536)
    assert verdict, verdict.reason
    assert verdict.kernel_name == "unary_abs"


def test_the_kernel_runs_after_itself_in_one_xmem():
    """On the chip y is the next layer's input: a second run reads the first's rows.

    The program sets every LR it reads and loads its own mask row, so the
    registers the first run left behind cannot matter.
    """
    numel = 1000  # eight rows, the last a short one
    x = _operands(numel)
    chain = Chain("dynamic")
    first = chain.run("unary_abs", {"fn": "abs", "numel": numel}, {"x": x}, check=True)
    assert first.result.passed, first.result.describe()
    second = chain.run("unary_abs", {"fn": "abs", "numel": numel}, {"x": first.resident["y"]}, check=True)
    assert second.result.passed, second.result.describe()
