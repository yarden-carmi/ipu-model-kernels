{#- Batched matrix multiply.
in0 [b, m, k] with k along the 128 lanes: rows (b, m, kchunk), declared
    [b, m, kchunks, 128]. One row holds k values kchunk*128 .. +127.
in1 [b, k, n] with k along the 128 lanes: rows (b, kchunk, n), declared
    [b, kchunks, n, 128]. One row holds the k values of one output column n.
out0 [b, m, n] with n along the 128 lanes: rows (b, m), declared
    [b, m, nchunks, 128] (n <= 64, so one row per (b, m)).

Per output row (b, m): for each k chunk, load the in0 row into R0, then for
each output lane n_i load in1's row (b, kchunk, n_i) into the cyclic register,
multiply element-wise and aggregate-sum the valid elements into R_ACC[n_i].
Chunk 0 uses AGG.SUM.FIRST (clean init per output row); later chunks use
AGG.SUM to add across chunks. Finally one ACTIVATE.QUANTIZE stores the row
with ds(n): lanes >= n are written 0. -#}
{%- set KC = (k + 127) // 128 -%}
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
    SET LR8 {{ cr.n }} ;;
inner{{ i }}:
    LD.MULT.CYCLIC LR3 {{ cr.in1 }} LR0 ; INC LR3 1 ; INC LR7 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.kd0 if i == 0 else (cr.kd1 if i == 1 else (cr.kd2 if i == 2 else cr.kd3)) }}.L {{ cr.qf }}.L ; AGG.SUM{% if i == 0 %}.FIRST{% endif %} LR7 {{ cr.kd0 if i == 0 else (cr.kd1 if i == 1 else (cr.kd2 if i == 2 else cr.kd3)) }}.L ; DEC LR8 1 ;;
    BNE LR8 CR0 inner{{ i }} ;;
{%- endfor %}
    ACTIVATE.QUANTIZE identity {{ cr.kdout }}.L {{ cr.qf }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.m }} m_loop ;;
    ADD LR10 LR10 {{ cr.kcn }} ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.b }} batch_loop ;;
    HALT ;;
