import torch


def reference(
    x: torch.Tensor,
    gamma: torch.Tensor,
    beta: torch.Tensor,
    *,
    eps: float,
    **_params: object,
) -> dict[str, torch.Tensor]:
    """y = (x - mean) / sqrt(var + eps) * gamma + beta over the channels (the
    last axis) of each token, with the population variance, as
    torch.nn.LayerNorm computes it. The kernel's intermediate NX8 roundings
    (the hi + lo splits of 1 / channels, the mean, the centered values, the
    variance, rsqrt and the normalized values) are not modelled: the
    tolerance covers them. The harness rounds y to the variant of the run."""
    x64 = x.double()
    mean = x64.mean(dim=-1, keepdim=True)
    var = ((x64 - mean) ** 2).mean(dim=-1, keepdim=True)
    y = (x64 - mean) / torch.sqrt(var + eps) * gamma.double() + beta.double()
    return {"y": y}
