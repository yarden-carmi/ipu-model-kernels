{#- gemm (linear): out0[m, n] = sum_k in1[m, k] * w[n, k] (+ bias[n] when bias).

in1 and out0 keep k / n along the 128 lanes (one row per m, padded); w is folded to
one row per tap: row t*k + 128*c + j holds w[n, 128*c + j] for the n of tile t
(n along the lanes), so one output row is k scalar-x-row multiplies: MULT.RC.VE
takes the scalar in1[m, k] straight out of R0 (one row of in1 loaded per chunk)
through its LR source select, while the w column row sits in R_CYCLIC one word
ahead: each j_loop body multiplies the previous body's load. LR7 holds the tap
index minus one and is read by the MULT after the same word's INC, while the
branch reads the cycle-start value, so the loop bound is taps - 2 and the last
tap runs inside the loop (its load is the next chunk's first row, or w's extra
zero row after the very last tap). The accumulator walks the n lanes of one
output row; the bias row initializes it per tile (or a zero multiply when bias
is off). k > 128 splits into chunks of 128 taps; n > 128 into tiles of 128
lanes, each stored as its own row. -#}
{% set is_fp32 = (format | default('')) == 'fp32' %}
{% set act = act_out0 | default('identity') %}
{% set store_act = 'ACTIVATE.EXACT ' ~ act if is_fp32 else 'ACTIVATE.QUANTIZE ' ~ act %}
    SET LR0 CR0 ;;
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR4 CR0 ; SET LR5 CR0 ;;
    DEC LR5 1 ;;
m_loop:
    SET LR1 CR0 ; SET LR3 CR0 ;;
tile_loop:
    SET LR6 {{ cr.chunks }} ;;
chunk_loop:
    SET LR7 CR0 ;;
    LD.MULT R0 LR2 {{ cr.in1 }} ; DEC LR7 1 ;;
    BNE LR6 {{ cr.chunks }} j_entry ;;
    {% if bias %}
    LD.MULT.CYCLIC LR3 {{ cr.b }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
    {% else %}
    MULT.RC.VE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
    {% endif %}
    LD.MULT.CYCLIC LR1 {{ cr.w }} LR0 ;;
j_entry:
    BNE LR6 CR1 full_bound ;;
    SET LR8 {{ cr.jbt }} ;;
    B j_loop ;;
full_bound:
    SET LR8 CR0 ;;
    INC LR8 126 ;;
j_loop:
    MULT.RC.VE LR0 LR7 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR1 {{ cr.w }} LR0 ; INC LR7 1 ; INC LR1 1 ; BLT.S LR7 LR8 j_loop ;;
    DEC LR6 1 ; INC LR2 1 ;;
    BNE LR6 CR0 chunk_loop ;;
    BNE LR3 {{ cr.lastt }} store_full ;;
    {{ store_act }} {{ cr.tailds }}.L {% if not is_fp32 %}{{ cr.qf_out0 }}.L {% endif %}{{ cr.out0 }} LR5 ; INC LR5 1 ; B tile_end ;;
store_full:
    {{ store_act }} {{ cr.full }}.L {% if not is_fp32 %}{{ cr.qf_out0 }}.L {% endif %}{{ cr.out0 }} LR5 ; INC LR5 1 ;;
tile_end:
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.tiles }} tile_loop ;;
    INC LR4 1 ;;
    BLT.S LR4 {{ cr.rows }} m_loop ;;
    HALT ;;
