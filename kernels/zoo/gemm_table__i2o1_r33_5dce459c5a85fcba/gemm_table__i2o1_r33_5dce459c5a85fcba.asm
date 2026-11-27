{% macro store(ds) %}
    ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ; INC LR7 1 ;;
{% endmacro %}
{% macro dot() %}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM LR5 CR15.L
{%- endmacro %}
{% macro chunk_body(label) %}
    LD.MULT.CYCLIC LR1 {{ cr.w }} LR0 ; SET LR10 LR8 ; SET LR5 CR0 ; SET LR12 LR11 ;;
{% if in0_d1 % 128 == 0 %}
    LD.MULT R0 LR10 {{ cr.in0 }} ; DEC LR12 2 ; DEC LR5 1 ;;
{% else %}
    LD.MULT R0 LR10 {{ cr.in0 }} ; DEC LR12 1 ;;
    BEQ LR12 CR0 {{ label }}_final ;;
    DEC LR5 1 ; DEC LR12 1 ;;
{% endif %}
{{ label }}_row:
    LD.MULT R0 LR10 {{ cr.in0 }} ; {{ dot() }} ; ADD LR10 LR10 {{ cr.K }} ; INC LR5 1 ; DEC LR12 1 ; BNE LR12 CR0 {{ label }}_row ;;
    INC LR5 1 ;;
{{ label }}_final:
    {{ dot() }} ; INC LR8 1 ; INC LR1 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR1 ;;
    INC LR1 1 ;;
{% endfor %}
    SET LR14 CR0 ; SET LR15 CR0 ; SET LR7 CR0 ;;
    DEC LR7 1 ;;
batch:
    SET LR6 CR0 ; SET LR4 CR0 ;;
column:
    SET LR8 LR14 ; SET LR13 {{ cr.in0_d1 }} ;;
tile:
    SET LR11 LR2 ;;
{% if in0_d1 % 128 != 0 %}
    BGE.S LR13 LR2 init ;;
    SET LR11 LR13 ;;
{% endif %}
init:
{% if bias %}
    LD.MULT R0 LR6 {{ cr.b }} ;;
    MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% else %}
    MULT.EE LR0 CR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
    SET LR9 {{ cr.K }} ; SET LR1 LR4 ; SUB LR13 LR13 LR11 ;;
{% if k > 128 and k <= 256 %}
    {{ chunk_body('first_chunk') }}
    {{ chunk_body('second_chunk') }}
{% else %}
chunk:
    {{ chunk_body('runtime_chunk') }}
    DEC LR9 1 ;;
    BNE LR9 CR0 chunk ;;
{% endif %}
    SET LR8 LR10 ;;
    INC LR8 1 ; BEQ LR13 CR0 last_tile ;;
    {{ store('CR15') }}
    BEQ CR0 CR0 tile ;;
last_tile:
    {{ store(cr.tail) }}
    INC LR6 1 ; ADD LR4 LR4 {{ cr.K }} ;;
    BLT.S LR6 {{ cr.n }} column ;;
    SET LR14 LR8 ; INC LR15 1 ;;
    BLT.S LR15 {{ cr.in0_d0 }} batch ;;
    HALT ;;
