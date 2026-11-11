"""cos: Exact restructure with no range reduction: halve the argument a fixed 6 times, evaluate a short Taylor series for cos(x/64), then rebuild cos(x) via the Chebyshev doubling recurrence T_{2k}(t)=2t^2-1 applied five times (T_64(cos(x/64))=cos x), valid for |x|<=64.

kind: variation
hw: MULT/ACC Horner chain for the Taylor polynomial, one stored square u=x^2, five store+MULT+ACC doubling steps, final store
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 0.0001480579376220703, "mean_abs": 3.3609483754415415e-06, "sqnr_db": 97.14535153807658}, "dynamic": {"max_abs": 1.998586356639862, "mean_abs": 0.27797245488641825, "sqnr_db": 4.510864558788536}}
"""

def fn(x):
    # Valid for |x| <= 64 (fixed 6 halvings). No floor, no division, no LUT.
    # cos(x) = T_64(cos(x/64)) exactly; approximate cos(x/64) by Taylor (deg 10).
    t = x * (1.0 / 64.0)              # ACC: scalar scale
    u = t * t                         # MULT
    store(u)                          # u reused across Horner -> store
    # Taylor of cos in u: 1 + u*(-1/2 + u*(1/24 + u*(-1/720 + u*(1/40320 + u*(-1/3628800 + u*(1/479001600))))))
    # degree 10 (next term 1/12! ~ 2.1e-9 at |arg|<=1 -> ~1e-5 after T_64 amplification)
    acc = 1.0 / 479001600.0
    acc = acc * u + (-1.0 / 3628800.0)   # MULT+ACC chain (no store)
    acc = acc * u + (1.0 / 40320.0)
    acc = acc * u + (-1.0 / 720.0)
    acc = acc * u + (1.0 / 24.0)
    acc = acc * u + (-0.5)
    acc = acc * u + 1.0
    t = store(acc)                    # t = cos(x/64), stored once
    # Chebyshev doubling: T_2, T_4, T_8, T_16, T_32, T_64
    for _ in range(6):
        t = store(t)                  # t needed as operand of its own square
        t = 2.0 * (t * t) - 1.0       # MULT + ACC (chains)
    return store(t)
