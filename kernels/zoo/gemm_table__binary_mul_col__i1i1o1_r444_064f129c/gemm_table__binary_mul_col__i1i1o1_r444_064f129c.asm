{% macro part(src, op='ACC.ADD') %}
    LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1 ;;
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; {{ op }} ;;
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
{% macro product(ds) %}
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3
{%- endmacro %}
{% macro scan(ds, label, drain) %}
    ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_in1 }}.L {{ cr.s0 }} LR0 ;;
    SET LR2 LR6 ; SET LR3 LR6 ; LD.MULT.CYCLIC LR0 {{ cr.s0 }} LR0 ;;
    SUB LR2 LR2 LR14 ; SUB LR3 LR3 LR14 ; SET LR4 CR1 ;;
    LD.MULT R0 LR2 {{ cr.in1 }} ; ADD LR2 LR2 LR14 ; BEQ LR15 CR0 {{ drain }} ;;
{{ label }}:
    LD.MULT R0 LR2 {{ cr.in1 }} ; ADD LR2 LR2 LR14 ; {{ product(ds) }} ; ADD LR3 LR3 LR14 ; INC LR4 1 ; BLT.S LR4 LR15 {{ label }} ;;
{{ drain }}:
    {{ product(ds) }} ; ADD LR3 LR3 LR14 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR6 CR0 ; SET LR8 CR0 ;;
    SET LR10 CR0 ; SET LR11 CR0 ;;
    INC LR11 128 ; SUB LR5 LR14 CR1 ; DEC LR8 1 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR10 ;;
    INC LR10 1 ;;
{% endfor %}
block:
    SET LR2 CR0 ; SET LR7 CR0 ;;
    DEC LR2 1 ;;
    {{ part('CR1', 'ACC.ADD.FIRST') }}
    {{ part('CR1') }}
    BEQ LR7 LR12 tail ;;
full:
    {{ chunk('LR11', 'full_channels') }}
    INC LR7 1 ;;
    BLT.S LR7 LR12 full ;;
tail:
    {{ chunk('LR13', 'tail_channels') }}
    BEQ LR6 LR5 last ;;
    {{ scan(cr.valid, 'full_rows', 'full_drain') }}
    INC LR6 1 ; B block ;;
last:
    {{ scan(cr.lastv, 'last_rows', 'last_drain') }}
    HALT ;;
