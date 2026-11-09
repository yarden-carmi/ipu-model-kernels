import torch


def reference(
    a: torch.Tensor, b: torch.Tensor, *, numel: int, operands: str, broadcast: bool
) -> dict[str, torch.Tensor]:
    """y = a * b elementwise, or a * b[0] when operands is "scalar". A broadcast
    b arrives already expanded to a's shape, so broadcast changes nothing here.
    The product is exact; the harness rounds y to the variant of the run."""
    if operands == "scalar":
        return {"y": a * b.reshape(-1)[0]}
    return {"y": a * b}
