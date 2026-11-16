{#- Batched matrix multiply (fp8_e2m5).
in0 [b, m, k] with k along the 128 lanes: rows (b, m, kchunk), declared
    [b, m, kchunks, 128]. One row holds k values kchunk*128 .. +127.
in1 [b, k, n] with k along the 128 lanes: rows (b, kchunk, n), declared
    [b, kchunks, n, 128]. One row holds the k values of one output column n.
    in1 does not depend on m, so LR3 restarts at the batch base (LR10) for
    every (b, m); LR10 advances by kchunks*n per batch (unrolled ADDs of n).
out0 [b, m, n] with n along the 128 lanes: rows (b, m, nchunk), declared
    [b, m, nchunks, 128].

R_ACC has 128 slots, so when n > 128 the output row is done in two passes:
pass 0 computes lanes 0..w0-1 (w0 = min(n,128)) and stores, pass 1 computes
lanes 128..n-1 (w1 = n-128 of them, AGG slots 0..w1-1 since pass 0 was
already stored) and stores. Each pass loops over the k chunks, reloading the
same in0 rows (LR1 rewinds by kchunks between passes). Within a pass over
two k chunks the in1 blocks of one k chunk are separated by the other
chunk's block: pass 0 skips w1 rows between k chunks, pass 1 skips w0 rows
(= 128); pass 1 also rewinds LR3 by n after pass 0 when both k chunks exist.
Each pass starts with AGG.SUM.FIRST (clean init); later k chunks use
AGG.SUM. Stores use per-chunk ds so lanes past n are written 0.

The inner loop is two words per output column: the load word does
LD.MULT.CYCLIC + DEC LR8 (loop counter) + INC LR3/LR7 (three LR slots); the
mult word does MULT.RC.VV + AGG.SUM + BNE in the cond slot (cond reads LR at
cycle start, so the DEC written by the previous word is visible). -#}
{%- set KC = (k + 127) // 128 -%}
{%- set NC = (n + 127) // 128 -%}
    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SUB LR1 LR1 CR1 ;;
    SET LR2 CR0 ;;
    SET LR5 CR0 ;;
    SET LR10 CR0 ;;
batch_loop:
    SET LR6 CR0 ;;
m_loop:
    SET LR3 LR10 ;;
    SUB LR3 LR3 CR1 ;;
{%- for i in range(KC) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR1 1 ;;
    SET LR7 CR0 ;;
    SUB LR7 LR7 CR1 ;;
    SET LR8 {{ cr.n if NC == 1 else cr.w0 }} ;;
inner0_{{ i }}:
    LD.MULT.CYCLIC LR3 {{ cr.in1 }} LR0 ; INC LR3 1 ; INC LR7 1 ; DEC LR8 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.kd0 if i == 0 else cr.kd1 }}.L {{ cr.qf }}.L ; AGG.SUM{% if i == 0 %}.FIRST{% endif %} LR7 {{ cr.kd0 if i == 0 else cr.kd1 }}.L ; BNE LR8 CR0 inner0_{{ i }} ;;
    {%- if NC == 2 and i < KC - 1 %}
    ADD LR3 LR3 {{ cr.w1 }} ;;
    {%- endif %}
{%- endfor %}
    ACTIVATE.QUANTIZE identity {{ cr.kdout0 }}.L {{ cr.qf }}.L {{ cr.out0 }} LR2 ;;
{%- if NC == 2 %}
    INC LR2 1 ;;
    SUB LR1 LR1 {{ cr.kchunks }} ;;
    {%- if KC == 2 %}
    SUB LR3 LR3 {{ cr.n }} ;;
    {%- endif %}
{%- for i in range(KC) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR1 1 ;;
    SET LR7 CR0 ;;
    SUB LR7 LR7 CR1 ;;
    SET LR8 {{ cr.w1 }} ;;
inner1_{{ i }}:
    LD.MULT.CYCLIC LR3 {{ cr.in1 }} LR0 ; INC LR3 1 ; INC LR7 1 ; DEC LR8 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.kd0 if i == 0 else cr.kd1 }}.L {{ cr.qf }}.L ; AGG.SUM{% if i == 0 %}.FIRST{% endif %} LR7 {{ cr.kd0 if i == 0 else cr.kd1 }}.L ; BNE LR8 CR0 inner1_{{ i }} ;;
    {%- if i < KC - 1 %}
    ADD LR3 LR3 {{ cr.w0 }} ;;
    {%- endif %}
{%- endfor %}
    ACTIVATE.QUANTIZE identity {{ cr.kdout1 }}.L {{ cr.qf }}.L {{ cr.out0 }} LR2 ;;
{%- endif %}
    INC LR2 1 ;;
    INC LR6 1 ;;
    BLT.S LR6 {{ cr.m }} m_loop ;;
{%- for i in range(KC) %}
    ADD LR10 LR10 {{ cr.n }} ;;
{%- endfor %}
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.b }} batch_loop ;;
    HALT ;;
