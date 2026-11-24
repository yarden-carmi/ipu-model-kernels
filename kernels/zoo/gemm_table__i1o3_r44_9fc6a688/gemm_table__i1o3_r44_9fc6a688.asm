{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% set chunks = (k + 127) // 128 %}
{% macro mac_chunk(label, ds) %}
    LD.MULT R0 LR4 {{ cr.w }} ; INC LR4 1 ; SET LR7 LR8 ; SET LR9 LR6 ;;
    LD.MULT R1 LR4 {{ cr.w }} ; INC LR4 1 ; SET LR10 CR0 ;;
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ; INC LR10 {{ out0_d3 }} ;;
{{ label }}:
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR9 {{ ds }}.L ; DEC LR10 1 ;;
    BEQ LR10 CR0 {{ label }}_last ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR9 {{ ds }}.L ; LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ; INC LR7 {{ chunks }} ;;
    INC LR9 1 ; BNE CR1 CR0 {{ label }} ;;
{{ label }}_last:
    MULT.RC.VV LR0 R1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR9 {{ ds }}.L ; INC LR8 1 ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR1 128 ; SET LR3 CR0 ; SET LR15 CR0 ;;
    DEC LR0 1 ; DEC LR3 1 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR0 ; INC LR0 1 ;;
{% endfor %}
    SET LR0 CR0 ;;
stripe:
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR13 {{ cr.blocks }} ;;
    DEC LR4 1 ; DEC LR5 1 ;;
block:
    LD.MULT R0 LR5 {{ cr.b }} ; INC LR5 1 ; SET LR6 CR0 ; SET LR12 {{ cr.pack }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR5 {{ cr.b }} ; INC LR5 1 ;;
    MULT.VE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
channel:
    SET LR8 LR2 ;;
{% if k > 128 %}
    SET LR11 CR0 ;;
    INC LR11 {{ (k - 1) // 128 }} ;;
full_chunk:
    {{ mac_chunk('full_tap', cr.dot_full) }}
    DEC LR11 1 ; BNE LR11 CR1 full_chunk ;;
{% endif %}
    {{ mac_chunk('tail_tap', cr.dot_tail) }}
    INC LR6 {{ out0_d3 }} ; DEC LR12 1 ; BNE LR12 CR1 channel ;;
    DEC LR13 1 ; BEQ LR13 CR1 last_block ;;
    {{ store(cr.full) }}
    BNE CR1 CR0 block ;;
last_block:
    {{ store(cr.tail) }}
    INC LR2 {{ chunks * out0_d3 }} ; INC LR15 1 ;;
    BLT.S LR15 {{ cr.stripes }} stripe ;;
    HALT ;;
