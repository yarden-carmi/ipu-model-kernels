{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.full ~ '.L' %}
{% set inputs = cin // groups %}
{% set outputs = cout // groups %}
{% set width = out0_d3 %}
{% macro increase(reg, value) %}
{% for start in range(0, value, 255) %}
    INC {{ reg }} {{ [255, value - start] | min }} ;;
{% endfor %}
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR6 CR0 ; SET LR7 CR0 ;;
    INC LR1 128 ; INC LR2 255 ;;
    INC LR2 1 ;;
    LD.MULT.CYCLIC LR0 {{ cr.weights }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.weights }} LR2 ;;
batch:
    SET LR15 CR1 ; SET LR14 CR0 ;;
channel:
    SET LR8 LR7 ; SET LR9 CR0 ;;
    DEC LR9 {{ padding }} ; DEC LR8 {{ padding }} ;;
row:
    SET LR5 LR15 ; SET LR13 LR8 ; SET LR12 CR0 ;;
    MULT.EE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
input_channel:
    LD.MULT R0 LR5 {{ cr.weights }} ;;
    LD.MULT R1 LR5 {{ cr.weights }} ; INC LR5 1 ;;
    MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR5 1 ;;
    MULT.EE LR1 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;;
    SET LR3 CR1 ; SET LR4 LR1 ;;
    SET LR10 LR9 ; SET LR11 LR13 ; INC LR4 1 ;;
ky:
    BLT.S LR10 CR0 skip_ky ;;
    SET LR2 CR0 ;;
    INC LR2 {{ in0_d2 }} ;;
    BGE.S LR10 LR2 skip_ky ;;
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR1 ;;
    SET LR2 LR1 ;;
    DEC LR2 {{ padding }} ;;
{% macro tap() %}
    MULT.RC.VE LR2 LR3 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;;
    MULT.RC.VE LR2 LR4 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR3 1 ;;
    INC LR4 1 ; INC LR2 1 ;;
{% endmacro %}
{% for x in range(kw) %}
    {{ tap() }}
{% endfor %}
    BEQ LR0 CR0 next_ky ;;
skip_ky:
    INC LR3 {{ kw }} ; INC LR4 {{ kw }} ;;
next_ky:
    INC LR10 1 ; INC LR11 1 ; SET LR2 LR9 ;;
    INC LR2 {{ kh }} ;;
    BLT.S LR10 LR2 ky ;;
    INC LR13 {{ in0_d2 }} ; INC LR12 1 ; SET LR2 CR0 ;;
    {{ increase('LR2', inputs) }}
    BLT.S LR12 LR2 input_channel ;;
    ADD LR2 LR6 LR6 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.line }} LR2 ;;
    LD.MULT.CYCLIC LR2 {{ cr.line }} LR1 ;;
    INC LR2 1 ;;
    MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qo }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.line }} LR2 ;;
    INC LR6 1 ; INC LR8 {{ stride }} ; INC LR9 {{ stride }} ;;
    SET LR2 CR0 ;;
{% if out0_d2 * stride >= padding %}
    {{ increase('LR2', out0_d2 * stride - padding) }}
{% else %}
    DEC LR2 {{ padding - out0_d2 * stride }} ;;
{% endif %}
    BLT.S LR9 LR2 row ;;
    SET LR15 LR5 ; INC LR14 1 ; SET LR2 CR0 ;;
    {{ increase('LR2', outputs) }}
    BLT.S LR14 LR2 same_group ;;
    SET LR14 CR0 ;;
    {# Advance by a group's input planes; break up the large product with a runtime loop. #}
    SET LR12 CR0 ; SET LR2 CR0 ;;
    {{ increase('LR2', inputs) }}
advance_group:
    INC LR7 {{ in0_d2 }} ; INC LR12 1 ;;
    BLT.S LR12 LR2 advance_group ;;
same_group:
    BLT.S LR15 {{ cr.weight_rows }} channel ;;
    BLT.S LR6 {{ cr.rows }} batch ;;

    {# Gather stride-selected samples into the consumer's packed row. #}
{% set capacity = 128 // width %}
{% set pack = capacity if out0_d2 % capacity == 0 or (out0_d2 * width == 64 and 128 % width == 0) else 1 %}
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR15 {{ cr.rows }} ;;
    ADD LR15 LR15 {{ cr.rows }} ;;
packed_row:
    SET LR10 LR4 ; SET LR11 CR1 ;;
gather_digit:
    MULT.EE LR6 CR0 0 LR6 {{ ds }} {{ qo }} ; ACC.ADD.FIRST ;;
    SET LR12 {{ cr.dst_lo }} ; SET LR13 {{ cr.dst_hi }} ; SET LR7 CR0 ;;
gather_line:
    ADD LR9 LR4 LR4 ;;
    ADD LR9 LR9 LR11 ; LD.MULT.CYCLIC LR9 {{ cr.line }} LR6 ;;
    SET LR0 {{ cr.src_lo }} ; SET LR1 {{ cr.src_hi }} ;;
    SET LR2 LR12 ; SET LR3 LR13 ;;
{% if width >= 8 %}
    SET LR8 CR0 ;;
    INC LR8 {{ width // 8 }} ;;
gather_eight:
    MULT.RC.VE LR6 CR1 0 LR6 {{ ds }} {{ qo }} ; ACC.RESHAPE LRD0 LRD2 0 ;;
    ADDBI LRD0 {{ 8 * stride }} ; ADDBI LRD2 8 ; DEC LR8 1 ;;
    BLT.S LR6 LR8 gather_eight ;;
{% endif %}
{% if width % 8 %}
    ADDBI LRD0 {{ (width % 8 - 8) * stride }} ; ADDBI LRD2 {{ width % 8 - 8 }} ;;
    MULT.RC.VE LR6 CR1 0 LR6 {{ ds }} {{ qo }} ; ACC.RESHAPE LRD0 LRD2 {{ 8 - width % 8 }} ;;
{% endif %}
    INC LR4 1 ;;
{% if pack > 1 %}
    BGE.S LR4 {{ cr.rows }} store ;;
    INC LR7 1 ; SET LR8 CR0 ;;
    INC LR8 {{ pack }} ;;
    BGE.S LR7 LR8 store ;;
    ADDBI LRD12 {{ width }} ; BEQ LR6 CR0 gather_line ;;
{% endif %}
store:
    BEQ LR11 CR0 store_output ;;
    ACTIVATE.QUANTIZE identity {{ cr.packed }}.L {{ qo }} {{ cr.line }} LR15 ;;
    SET LR4 LR10 ; SET LR11 CR0 ; BEQ LR6 CR0 gather_digit ;;
store_output:
    LD.MULT.CYCLIC LR15 {{ cr.line }} LR6 ;;
    NOP ;;
    MULT.RC.VE LR6 CR1 0 LR6 {{ ds }} {{ qo }} ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.packed }}.L {{ qo }} {{ cr.out0 }} LR5 ;;
    INC LR5 1 ; BLT.S LR4 {{ cr.rows }} packed_row ;;
    HALT ;;
