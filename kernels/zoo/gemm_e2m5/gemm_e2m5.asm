{#- gemm_e2m5: out[m, n] = sum_k in0[m, k] * w[k, n] (+ bias[n] when bias).
Design: in0 rows hold 128 k-values along the lanes (row = m*K + kb). w is
stored physically transposed, [k, NB*128] flattened, so row k*NB + nb holds
w[k, nb*128:nb*128+128] with n along the lanes. For each output row (m, nb)
the accumulator runs over all k in blocks of 128. Per the register read
timing (ARCH 6.3) the LOAD/MULT stages read their LR operands at the END of
the cycle, so every address here is pre-decremented and post-incremented in
the same word: block entry sets LR4 = w-row of k-1 and LR3 = -1, the four
prologue loads then fetch w rows k=0..3 into the four R_CYCLIC slots (LR2
cycles 0/128/256/384, read after the same-word INC.MODP2), and body word kk
multiplies slot (kk+1)%4 -- w row kk, loaded four words earlier, data read
at cycle start -- by scalar R0[kk] (LR3 read after its INC), while
prefetching w row kk+4 with the pointer ending exactly at the next block's
start. No load ever steps outside w. Each k costs exactly one instruction
word. The accumulator is cleared once per output row by a multiply by CR0.
Bias (when present) is folded in with one extra vector-times-1.0 accumulate
before the store. Rows whose n-block is partial store with the tail DS half;
padding lanes of w and bias are zero, so the accumulator's padding lanes are
exactly zero.
Register map: LR0 = 0, LR2 cyclic slot, LR3 lane counter, LR4 w row - 1,
LR5 m counter, LR6 nb counter, LR7 out row, LR8 in0 row - 1, LR9 kb counter,
LR11 m*K base, LR12 NB-1. -#}
{%- set K = k // 128 -%}
{%- set NB = ((n + 127) // 128) -%}
{%- set has_tail = (n % 128) != 0 -%}
    SET LR0 CR0 ;;
    SET LR2 CR0 ;;
    SET LR11 CR0 ;;
    SET LR5 CR0 ;;
    SET LR12 {{ cr.NB }} ;;
    SUB LR12 LR12 CR1 ;;
    SET LR7 CR0 ;;
m_loop:
    SET LR6 CR0 ;;
nb_loop:
    SET LR4 LR6 ;;
    SUB LR4 LR4 {{ cr.NB }} ;;
    SET LR8 LR11 ;;
    SUB LR8 LR8 CR1 ;;
    SET LR3 CR0 ;;
    SUB LR3 LR3 CR1 ;;
    LD.MULT.CYCLIC LR6 {{ cr.w }} LR2 ;;
    MULT.RC.VE LR2 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for block in range((k + 127) // 128) %}
{% set count = [128, k - block * 128] | min %}
    LD.MULT R0 LR8 {{ cr.in0 }} ; INC LR8 1 ;;
    SET LR3 CR0 ;;
    SUB LR3 LR3 CR1 ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR2 ; ADD LR4 LR4 {{ cr.NB }} ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR2 ; ADD LR4 LR4 {{ cr.NB }} ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR2 ; ADD LR4 LR4 {{ cr.NB }} ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR2 ; ADD LR4 LR4 {{ cr.NB }} ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% for i in range(count - 4) %}
    MULT.RC.VE LR2 LR3 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR2 ; ADD LR4 LR4 {{ cr.NB }} ; INC LR3 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% for i in range(4) %}
    MULT.RC.VE LR2 LR3 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; INC LR3 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% endfor %}
{% if bias %}
    LD.MULT.CYCLIC LR6 {{ cr.b }} LR2 ;;
    MULT.RC.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
{% if has_tail %}
    BEQ LR6 LR12 nb_tail ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.NB }} nb_loop ;;
    ADD LR11 LR11 {{ cr.K }} ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.m }} m_loop ;;
    HALT ;;
nb_tail:
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.NB }} nb_loop ;;
    ADD LR11 LR11 {{ cr.K }} ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.m }} m_loop ;;
    HALT ;;
{% else %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.NB }} nb_loop ;;
    ADD LR11 LR11 {{ cr.K }} ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.m }} m_loop ;;
    HALT ;;
{% endif %}
