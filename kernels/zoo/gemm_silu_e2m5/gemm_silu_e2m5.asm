# gemm_silu_e2m5: out[m,n] = silu(sum_k in0[m,k]*w[n,k] + bias[n]).
# in0: k along the 128 lanes (kp row-blocks per m row). w folded so that
# row j*nb+b holds w[b*128+lane, j*128+lane] (n along the lanes, one row
# per (k-block j, n-block b)). Per output row r: load the kp in0 rows into
# R_CYCLIC slots, then per n-block b and k-block j multiply the in0 slot by
# the w row in R0 and accumulate; the bias row b enters first.
# The n-block loop is unrolled so each store names the DS half for that
# block's valid lanes; inactive lanes are stored as 0.
# The test harness fills every declared input (w included) with random values
# in its range, so the w lanes past the real k (kv = j*128+lane >= k) hold
# garbage the reference's unfold leaves out of W. Prologue: each w row is
# copied through an identity multiply and stored back with the DS half for
# its k-block, which writes the lanes past that block's valid k as 0.
{%- set kp = ((k + 127) // 128) -%}
{%- set nb = ((n + 127) // 128) -%}
{%- set rem = n - (nb - 1) * 128 -%}
    SET LR0 CR0 ;;
    SET LR4 CR0 ;;
    SET LR5 CR0 ;;
    SET LR9 CR0 ;;
    SET LR8 CR0 ;;
    INC LR8 128 ;;
    LD.LUT 0 {{ cr.lut }} LR0 ;;
    LD.LUT 1 {{ cr.lut }} LR0 ;;
    LD.LUT 2 {{ cr.lut }} LR0 ;;
    LD.LUT 3 {{ cr.lut }} LR0 ;;
    LD.LUT 4 {{ cr.lut }} LR0 ;;
    SET LR10 CR0 ;;
{% for i in range(kp * nb) %}
{% set j = i // nb %}
    LD.MULT.CYCLIC LR10 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {% if j == 0 %}{{ cr.dsk0 }}.L{% else %}{{ cr.dsk1 }}.L{% endif %} {{ cr.qf }}.L {{ cr.w }} LR10 ;;
    INC LR10 1 ;;
{% endfor %}
row_loop:
{% for j in range(kp) %}
{% if j %}
    INC LR4 1 ;;
{% endif %}
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR{{ 0 if j == 0 else 8 }} ;;
{% endfor %}
    SET LR6 CR0 ;;
{% for b in range(nb) %}
    SET LR7 LR6 ;;
{% if bias %}
    LD.MULT R1 LR7 {{ cr.bias_vec }} ;;
    MULT.VE LR8 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% endif %}
{% for j in range(kp) %}
    LD.MULT R0 LR7 {{ cr.w }} ;;
    MULT.RC.VV LR{{ 0 if j == 0 else 8 }} R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ "" if bias else (".FIRST" if j == 0 else "") }} ; INC LR7 {{ nb }} ;;
{% endfor %}
    ACTIVATE.QUANTIZE generic {% if b == nb - 1 and rem != 128 %}{{ cr.dsn }}.L{% else %}CR15.L{% endif %} {{ cr.qf }}.L {{ cr.out0 }} LR9 ;;
    INC LR9 1 ;;
    INC LR6 1 ;;
{% endfor %}
    INC LR4 1 ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.m }} row_loop ;;
    HALT ;;
