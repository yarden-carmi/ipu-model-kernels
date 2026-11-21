{#- gemm_hardswish_e2m5: out[m, n] = hardswish(sum_k in0[m, k] * w[k, n] + bias[n]).

in0 is declared as the flat vector of its m*k elements (the previous kernel
leaves exactly ceil(m*k/128) XMEM rows), so element (m, k) sits at lane
(m*k_stride + k) mod 128 of XMEM row floor(m*k_stride / 128). With
k <= 128 a row's k-run spans at most two XMEM rows. Per output row m we load
R0 <- row floor(m*k/128) and, when the k-run crosses a row boundary
(r = m*k mod 128 >= 112), R1 <- the next row; MULT.RC.VE's LR scalar selector
reads R0[idx] for idx < 128 and R1[idx-128] for idx >= 128, so one monotone
LR3 = r-1 .. r+k-1 walks the run across both rows with no mid-loop branch.

r = m*k mod 128 only takes multiples of 8; per-m housekeeping at the loop
bottom: if r >= 104 the next m starts a new XMEM row (INC LR6); if
88 <= r < 104 the NEXT m's run will cross a boundary, so R1 <- row+1 is
preloaded here (the row does not advance between them). LR3 is carried across
iterations as r-1 and fixed with INC / INC.MODP2 / DEC, which also maps
r = 104 (LR3 = 127) to -1 for the next r' = 0.

Weights are folded transposed to [k, 128] (n along lanes, zero padding), bias
[128] padded. The proven cyclic prefetch schedule runs the k-loop: each word
multiplies w row kk (loaded four words earlier into the R_CYCLIC slot selected
by LR2 after its same-word INC.MODP2 +128 mod 512) by scalar R0/R1[LR3] (read
after the same-word INC), and needs k ≡ 0 (mod 4) so LR2 returns to its
start-of-row value. The accumulator is cleared by a multiply by CR0; bias
folds in with a vector-times-1.0 accumulate; the store applies hardswish
through the LUT with the tail DS half (n of 128 lanes active).

Register map: LR0 = 0, LR1 LUT offset, LR2 cyclic slot index, LR3 x lane
selector (r-1), LR4 w row pointer, LR5 out row / m counter, LR6 in0 XMEM row
pointer, LR8 temp. CRs: in0, w, out0, b, lut, m, qf, tail, c128, c111, c127. -#}
    SET LR0 CR0 ;;
    SET LR2 CR0 ;;
    SET LR6 CR0 ;;
    SET LR5 CR0 ;;
    SET LR1 CR0 ;;
    SET LR3 CR0 ;;
    SUB LR3 LR3 CR1 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR1 ;;
    INC LR1 1 ;;
{% endfor %}
m_loop:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    SET LR4 CR0 ;;
    SUB LR4 LR4 CR1 ;;
    LD.MULT.CYCLIC LR0 {{ cr.w }} LR2 ;;
    MULT.RC.VE LR2 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for i in range(4) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR2 ; INC LR4 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% for i in range(k - 4) %}
    MULT.RC.VE LR2 LR3 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR2 ; INC LR4 1 ; INC LR3 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% for i in range(4) %}
    MULT.RC.VE LR2 LR3 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; INC LR3 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% if bias %}
    LD.MULT.CYCLIC LR0 {{ cr.b }} LR2 ;;
    MULT.RC.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
    ACTIVATE.QUANTIZE generic {{ cr.tail }}.L {{ cr.qf }}.L {{ cr.out0 }} LR5 ;;
    BGE.S LR3 {{ cr.c127 }} incrow ;;
    BGE.S LR3 {{ cr.c111 }} loadr1 ;;
    INC LR3 1 ;;
    INC.MODP2 LR3 CR0 7 ;;
    DEC LR3 1 ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.m }} m_loop ;;
    HALT ;;
incrow:
    INC LR6 1 ;;
    ADD LR8 LR6 CR1 ;;
    LD.MULT R1 LR8 {{ cr.in0 }} ;;
    INC LR3 1 ;;
    INC.MODP2 LR3 CR0 7 ;;
    DEC LR3 1 ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.m }} m_loop ;;
    HALT ;;
loadr1:
    ADD LR8 LR6 CR1 ;;
    LD.MULT R1 LR8 {{ cr.in0 }} ;;
    INC LR3 1 ;;
    INC.MODP2 LR3 CR0 7 ;;
    DEC LR3 1 ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.m }} m_loop ;;
    HALT ;;
