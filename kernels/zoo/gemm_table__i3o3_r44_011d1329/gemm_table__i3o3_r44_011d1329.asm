{% macro mult(src, acc='ADD') -%}
MULT.RC.VE {{ src }} CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.{{ acc }}
{%- endmacro %}
{% macro coeff(dest) -%}
LD.MULT {{ dest }} LR5 {{ cr.coeff }} ; INC LR5 1
{%- endmacro %}
{% macro dot(reg) -%}
MULT.RC.VV LR0 {{ reg }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{%- endmacro %}
{% set pack = 128 // out0_d3 %}
{% set vectors = cr.stage if pack > 1 else cr.in0 %}
    SET LR0 CR0 ; SET LR1 {{ cr.slot }} ; SET LR2 CR0 ;;
{% if pack > 1 %}
    MULT.VE LR0 CR0 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR3 {{ cr.input_rows }} ;;
    ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_in0 }}.L {{ cr.stage }} LR3 ;;
    LD.MULT.CYCLIC LR3 {{ cr.stage }} LR0 ;;
stage_row:
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR1 ; SET LR3 LR1 ;;
    {{ mult('LR1', 'ADD.FIRST') }} ; ACTIVATE.QUANTIZE identity {{ cr.width_ds }}.L {{ cr.qf_in0 }}.L {{ cr.stage }} LR2 ;;
    LD.MULT.CYCLIC LR2 {{ cr.stage }} LR1 ;;
    {{ mult('LR1', 'ADD.FIRST') }} ;;
{% macro replicate() -%}
    {{ mult('LR3') }} ; DEC LR3 {{ out0_d3 }} ;;
{%- endmacro %}
{% if pack <= 32 %}
{% for _ in range(pack - 1) %}
    {{ replicate() }}
{% endfor %}
{% else %}
    SET LR4 CR0 ;;
    INC LR4 {{ pack - 1 }} ;;
replicate_row:
    {{ mult('LR3') }} ; DEC LR3 {{ out0_d3 }} ; DEC LR4 1 ; BNE LR4 CR1 replicate_row ;;
{% endif %}
    ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_in0 }}.L {{ cr.stage }} LR2 ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.input_rows }} stage_row ;;
{% endif %}
    SET LR2 CR0 ; SET LR7 CR0 ; SET LR9 CR0 ;;
    DEC LR2 1 ; DEC LR7 1 ;;
{% for j in range(5) %}
    LD.LUT {{ j }} {{ cr.lut }} LR2 ; INC LR2 1 ;;
{% endfor %}
stripe:
    SET LR5 CR0 ; SET LR8 {{ cr.groups }} ; ADD LR10 LR9 {{ cr.k }} ;;
    DEC LR5 1 ; SUB LR11 LR10 CR1 ; SUB LR12 LR9 CR1 ;;
group:
    LD.MULT.CYCLIC LR5 {{ cr.coeff }} LR0 ; INC LR5 1 ; SET LR6 LR12 ;;
    {{ mult('LR0', 'ADD.FIRST') }} ; LD.MULT.CYCLIC LR5 {{ cr.coeff }} LR0 ; INC LR5 1 ;;
    {{ mult('LR0') }} ; LD.MULT.CYCLIC LR6 {{ vectors }} LR0 ; INC LR6 1 ;;
    {{ coeff('R0') }} ;;
tap:
    {{ dot('R0') }} ; {{ coeff('R1') }} ; BEQ LR6 LR11 finish_group ;;
    {{ dot('R1') }} ; LD.MULT.CYCLIC LR6 {{ vectors }} LR0 ; INC LR6 1 ;;
    {{ coeff('R0') }} ; B tap ;;
finish_group:
    {{ dot('R1') }} ; ACTIVATE.QUANTIZE {{ 'generic' if act_out0 == 'silu' else act_out0 }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ; INC LR7 1 ; DEC LR8 1 ; BNE LR8 CR1 group ;;
    SET LR9 LR10 ; BLT.S LR10 {{ cr.input_rows }} stripe ;;
    HALT ;;
