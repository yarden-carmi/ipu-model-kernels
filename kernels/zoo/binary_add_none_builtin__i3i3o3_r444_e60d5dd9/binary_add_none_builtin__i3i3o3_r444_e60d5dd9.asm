    # out0 = relu(in0 + in1). All tensors have rows ordered [d0,d2,d1],
    # with d3 on the lanes. Each row group has K = ceil(d3/128) rows.
    # The outer loop traverses row groups; K is unrolled so each row's
    # mask (full, or tail on the group's
    # last row) is known at build time. Steady state: 2 words per row.
    #   word1: in0 row x 1.0 -> ACC.FIRST ; load in1 row into R_CYCLIC slot 0
    #   word2: in1 row x 1.0 -> ACC.ADD ; store relu row ; load in0 row+1
    # Loads and AAQ read their LR operands at end of cycle: LR5 (in rows) is
    # INC'd in the same word as the load of row r+1; LR6 holds r-1 at word
    # start (starts at -1) and is INC'd in the same word as the AQ that stores
    # row r. LR0 = 0 (Ra base, mask shift), LR7 = 0 (R_CYCLIC slot 0).
{% set K = ((out0_d3 + 127) // 128) %}
{% set channels = out0_d0 * out0_d1 * out0_d2 %}
{% macro half_row(mask, load, branch=false) %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_mask }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR5 {{ cr.in1 }} LR7 ;;
    MULT.RC.VE LR7 CR1 0 LR0 {{ cr.full_mask }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ mask }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; {% if load %}LD.MULT R0 LR5 {{ cr.in0 }} ; {% endif %}INC LR5 1 ; INC LR6 1 {% if branch %}; BLT.S LR5 {{ cr.loop_bound }} channel_loop{% endif %} ;;
{% endmacro %}
{% set full = cr.full_mask %}
{% set tail = cr.tail_mask %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR7 CR0 ;;
    DEC LR6 1 ;;
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
{% if channels > 1 %}
channel_loop:
{% for p in range(K) %}
    {{ half_row(tail if p == K - 1 else full, true, branch=(p == K - 1)) }}
{% endfor %}
{% endif %}
{% for p in range(K) %}
    {{ half_row(tail if p == K - 1 else full, p < K - 1) }}
{% endfor %}
    HALT ;;
