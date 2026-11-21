{% macro part(src, op='ACC.ADD', ctrl='') %}
    LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1 ;;
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; {{ op }} {{ ctrl }} ;;
{% endmacro %}
{% macro chunk(limit, label) %}
    INC LR2 1 ; SET LR9 CR0 ;;
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
{{ label }}:
    {{ part('LR9') }}
    {{ part('LR9') }}
    INC LR9 1 ;;
    BLT.S LR9 {{ limit }} {{ label }} ;;
{% endmacro %}
{% macro store(ds, ctrl='') %}
    ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 {{ ctrl }} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR10 CR0 ; SET LR3 CR0 ;;
    DEC LR3 1 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR10 ;;
    INC LR10 1 ;;
{% endfor %}
    SET LR5 CR0 ; SET LR4 CR0 ; SET LR11 CR0 ;;
    DEC LR5 1 ; INC LR11 128 ;;
row:
    SET LR8 CR0 ; SET LR6 CR0 ;;
    DEC LR8 1 ;;
block:
    SET LR2 LR5 ; SET LR7 CR0 ;;
    {{ part('CR1', 'ACC.ADD.FIRST') }}
    {{ part('CR1') }}
    BEQ LR7 {{ cr.full_chunks }} tail ;;
full:
    {{ chunk('LR11', 'full_channels') }}
    INC LR7 1 ;;
    BLT.S LR7 {{ cr.full_chunks }} full ;;
tail:
    {{ chunk(cr.tail, 'tail_channels') }}
    BLT.S LR6 {{ cr.full_blocks }} store_full ;;
    {{ store(cr.lastv) }}
    INC LR4 1 ; ADD LR5 LR5 {{ cr.ic }} ;;
    BLT.S LR4 {{ cr.rows }} row ;;
    HALT ;;
store_full:
    {{ store(cr.valid, '; INC LR6 1 ; B block') }}
