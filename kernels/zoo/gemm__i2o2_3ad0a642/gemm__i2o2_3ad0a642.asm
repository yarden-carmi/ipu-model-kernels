{#- gemm: out[m, n] = sum_k x[m, k] * w[n, k] + bias[n], k = H*D, with the merge view
    x[m, j*D + d] = stored row (D*((H*m + j) // S) + d), lane (H*m + j) % S
    (stored [1, H, S, D]: row = h*D + d, lane = s; the view is the flat storage read as [m, k]).
    Walk q = H*m + j (one lane/row-block step per j): lane LR12 and row base LR11 are kept per q,
    stepped by one per j, and the m-block start (LR13, LR14) advances by H per m.
    Weights: fold rows c*k + K, lanes n%128. Output row m*nc + c. -#}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR7 CR0 ;;
    SET LR13 CR0 ; SET LR14 CR0 ;;
mloop:
    SET LR8 CR0 ; SET LR6 CR0 ;;
cloop:
    SET LR4 LR6 ; SET LR12 LR13 ; SET LR11 LR14 ;;
    SET LR9 CR0 ;;
    LD.MULT R0 LR8 {{ cr.bvec }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
jloop:
    SET LR1 LR11 ; SET LR3 LR12 ; SET LR2 LR4 ;;
    SET LR10 CR0 ;;
kloop:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR2 {{ cr.w }} LR0 ; INC LR1 1 ; INC LR10 1 ;;
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR2 1 ; BLT.S LR10 {{ cr.in0_d3 }} kloop ;;
    ADD LR4 LR4 {{ cr.in0_d3 }} ; INC LR9 1 ;;
    INC LR12 1 ;;
    BNE LR12 {{ cr.in0_d2 }} jnw ;;
    SET LR12 CR0 ; ADD LR11 LR11 {{ cr.in0_d3 }} ;;
jnw:
    BLT.S LR9 {{ cr.in0_d1 }} jloop ;;
    ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ; ADD LR6 LR6 {{ cr.k }} ; INC LR8 1 ;;
    BLT.S LR8 {{ cr.nc }} cloop ;;
    SET LR15 CR0 ;;
madv:
    INC LR13 1 ;;
    BNE LR13 {{ cr.in0_d2 }} mnw ;;
    SET LR13 CR0 ; ADD LR14 LR14 {{ cr.in0_d3 }} ;;
mnw:
    INC LR15 1 ;;
    BLT.S LR15 {{ cr.in0_d1 }} madv ;;
    INC LR7 1 ;;
    BLT.S LR7 {{ cr.m }} mloop ;;
    HALT ;;
