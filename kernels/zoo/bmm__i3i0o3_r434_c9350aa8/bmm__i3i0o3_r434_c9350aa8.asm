{# Transpose the RHS into k-major panels. Keep a second quantized row
   per vector for the residual discarded by the shared scale. #}
{% macro store(base, act, qf, ptr, width, ds, label) %}
    BLT.S {{ width }} LR1 {{ label }}_tail ;;
    ACTIVATE.QUANTIZE {{ act }} {{ ds }}.L {{ qf }}.L {{ base }} {{ ptr }} ; B {{ label }} ;;
{{ label }}_tail:
    ACTIVATE.QUANTIZE {{ act }} {{ ds }}.H {{ qf }}.L {{ base }} {{ ptr }} ;;
{{ label }}:
{% endmacro %}
{% macro gather(qf, scalar, base, stride, label) %}
    LD.MULT R0 LR11 {{ base }} ; SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    MULT.EE {{ scalar }} CR0 0 LR0 {{ cr.ds_n }}.L {{ qf }}.L ; ACC.ADD.FIRST ; DEC LR13 1 ; BEQ LR13 CR1 {{ label }}_last ;;
{% for advance in [false,true] %}
{% if advance %}{{ label }}_next:{% endif %}
    MULT.EE {{ scalar }} CR1 0 LR0 {{ cr.ds_n }}.L {{ qf }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; LD.MULT R0 LR11 {{ base }} ; {{ stride }}{% if advance %} ; ADDBI LRD2 1{% endif %} ; DEC LR13 1 ; {% if advance %}BNE LR13 CR1 {{ label }}_next{% else %}BEQ LR13 CR1 {{ label }}_final{% endif %} ;;
{% endfor %}
{{ label }}_final:
    ADDBI LRD2 1 ;;
{{ label }}_last:
    MULT.EE {{ scalar }} CR1 0 LR0 {{ cr.ds_n }}.L {{ qf }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR1 128 ;;
{% endmacro %}

group:
    SET LR5 {{ cr.geometry }}.L ; SET LR6 {{ cr.start }}.L ;;
head:
    SET LR14 LR6 ; SET LR12 {{ cr.mn }}.H ; SET LR9 CR0 ;;
pack_tile:
    SET LR15 LR12 ; SET LR1 CR0 ;;
    INC LR1 128 ;;
    BLT.S LR15 LR1 pack_width ;;
    SET LR15 LR1 ;;
pack_width:
    SET LR10 {{ cr.k }} ;;
pack_k:
    SET LR11 LR14 ; SET LR13 LR15 ;;
    {{ gather(cr.qf_in1, 'LR4', cr.in1, 'ADD LR11 LR11 ' ~ cr.in1_d2, 'rhs') }}
    {{ store(cr.panel, 'identity', cr.qf_in1, 'LR9', 'LR15', cr.ds_n, 'pack_main') }}
    LD.MULT R0 LR9 {{ cr.panel }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.ds_n }}.L {{ cr.qf_in1 }}.L ; ACC.SUB ; INC LR9 1 ;;
    {{ store(cr.panel, 'identity', cr.qf_in1, 'LR9', 'LR15', cr.ds_n, 'pack_resid') }}
    INC LR9 1 ; INC LR14 1 ; DEC LR10 1 ; BNE LR10 CR1 pack_k ;;
    SUB LR12 LR12 LR15 ;;
    BEQ LR12 CR0 multiply ;;
    SUB LR14 LR14 {{ cr.k }} ;;
    ADD LR14 LR14 {{ cr.rhs_tile }} ; B pack_tile ;;

{% macro product(first_part, prefetch) %}
    MULT.RC.VE LR0 LR13 0 LR0 {{ cr.ds_n }}.L {{ cr.qf_in1 }}.L ; ACC.ADD{% if first_part %} ; INC LR13 1{% endif %}{% if prefetch %} ; INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.panel }} LR0{% endif %}
{%- endmacro %}
multiply:
    SET LR14 LR7 ; SET LR15 {{ cr.mn }}.L ; SET LR1 CR0 ;;
    INC LR1 128 ;;
output_row:
    LD.MULT R0 LR14 {{ cr.in0 }} ; SET LR12 {{ cr.mn }}.H ; SET LR9 CR0 ;;
output_tile:
    MULT.VE LR0 CR0 0 LR0 {{ cr.ds_n }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR10 {{ cr.k }} ; SET LR13 CR0 ;;
    LD.MULT.CYCLIC LR9 {{ cr.panel }} LR0 ; DEC LR13 1 ; DEC LR10 1 ;;
    BEQ LR10 CR0 reduce_last ;;
reduce:
    {{ product(true, true) }} ;;
    {{ product(false, true) }} ; DEC LR10 1 ; BNE LR10 CR1 reduce ;;
reduce_last:
    {{ product(true, true) }} ;;
    {{ product(false, false) }} ; INC LR9 1 ;;
    {{ store(cr.out0, act_out0 | default('identity'), cr.qf_out0, 'LR8', 'LR12', cr.ds_n, 'output_stored') }}
    INC LR8 1 ;;
    BLT.S LR1 LR12 next_output_tile ;;
    DEC LR15 1 ; BEQ LR15 CR1 head_advance ;;
    ADD LR14 LR14 {{ cr.geometry }}.L ; B output_row ;;
next_output_tile:
    DEC LR12 128 ; B output_tile ;;

head_advance:
    DEC LR5 1 ; BEQ LR5 CR1 group_advance ;;
    INC LR7 1 ; ADD LR6 LR6 {{ cr.k }} ; B head ;;
group_advance:
    ADD LR7 LR14 CR1 ; INC LR4 1 ;;
    BLT.S LR4 {{ cr.geometry }}.H group ;;
    HALT ;;
