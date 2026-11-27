{% macro coeff() -%}
LD.MULT R0 LR8 {{ cr.coeff }} ; INC LR8 1
{%- endmacro %}
{% macro bias(op) -%}
MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; {{ op }} ; {{ coeff() }}
{%- endmacro %}
{% macro product(slot) -%}
MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L
{%- endmacro %}
{% macro store(ds) -%}
ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1
{%- endmacro %}

    SET LR0 CR0 ; SET LR3 CR0 ; SET LR8 CR0 ;;
    DEC LR3 1 ; DEC LR8 1 ;;
{% if m == 1 %}
{# Each product loads the next coefficient. Peel the final output channel
   so its final product never speculatively reads past the coefficient bank. #}
{% set tiles = (k + 127) // 128 %}
{% set resident = [tiles, 4] | min if tiles <= 5 else 3 %}
{% set groups = (n + 127) // 128 %}
{% set slots = ['LR0', 'LR1', 'LR11', 'LR12'] %}
{% macro dot_channel(again, tag) %}
{% for j in range(tiles) %}
{% set slot = slots[[j, 3] | min] %}
{% if tiles == 5 and j == 4 %}
{# The fifth input lives in R1. Borrow cyclic slot zero for its two
   coefficients and restore the first input on the second product. #}
    MULT.RC.VV LR0 R1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR6 {{ cr.full_ds }}.L ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1 ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR6 {{ cr.full_ds }}.L ; LD.MULT.CYCLIC LR0 {{ cr.in0 }} LR0 ;;
{% if again %}
    {{ coeff() }} ; BLT.S LR6 LR7 {{ tag }} ;;
{% endif %}
{% else %}
{% if j >= resident %}
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR12 ; INC LR2 1 ;;
{% endif %}
{% for half in range(2) %}
    {{ product(slot) }} ; AGG.SUM LR6 {{ cr.full_ds }}.L {% if tiles == 5 and j == 3 and half == 1 %}; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1{% elif again or j + 1 != tiles or half == 0 %}; {{ coeff() }}{% endif %} {% if j == 0 and half == 0 %}; INC LR6 1 {% if tiles > 5 %}; SET LR2 CR1{% endif %}{% elif j == 0 and half == 1 and tiles > 5 %}; INC LR2 1{% endif %} {% if again and j + 1 == tiles and half == 1 %}; BLT.S LR6 LR7 {{ tag }}{% endif %} ;;
{% endfor %}
{% endif %}
{% endfor %}
{% endmacro %}
{% macro dot_body(count, ds, tag) %}
    {{ coeff() }} ; SUB LR6 LR0 CR1 ; SET LR7 CR0 ;;
    {{ bias('ACC.ADD.FIRST') }} {% if count > 1 %}; INC LR7 {{ count - 2 }}{% endif %} ;;
    {{ bias('ACC.ADD') }} ;;
{% if count > 1 %}
{{ tag }}:
    {{ dot_channel(true, tag) }}
{% endif %}
    {{ dot_channel(false, tag) }}
    {{ store(ds) }} ;;
{% endmacro %}
    SET LR1 CR0 ; SET LR11 CR0 ; SET LR12 CR0 ;;
    INC LR1 128 ; INC LR11 128 ; INC LR12 128 ;;
    INC LR11 128 ; INC LR12 128 ; SET LR2 CR0 ;;
    INC LR12 128 ; SET LR5 {{ cr.last }} ;;
{% for j in range(resident) %}
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} {{ slots[j] }} {% if j %}; INC LR2 1{% endif %} ;;
{% endfor %}
{% if tiles == 5 %}
    LD.MULT R1 LR2 {{ cr.in0 }} ; INC LR2 1 ;;
{% endif %}
{% if groups > 1 %}
dot_full:
    {{ dot_body(128, cr.full_ds, 'dot_full_channel') }}
    DEC LR5 1 ; BNE LR5 CR1 dot_full ;;
{% endif %}
    {{ dot_body(n - (groups - 1) * 128, cr.tail_ds, 'dot_tail_channel') }}
{% else %}
{# A cyclic shift aligns one channel diagonal across all packed pixels.
   Coefficient zeros suppress lanes crossing the input bundle boundary. #}
{% set p = [4, 128 // in0_d3] | min %}
{% set regs = ['LR1', 'LR7', 'LR10', 'LR11', 'LR12', 'LR13', 'LR14'] %}
{% macro diagonal(last, label, ds, next_bundle) %}
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} {{ regs[p - 1] }} ; INC LR2 1 ;;
{% for j in range(2 * p - 1) %}
    {{ product(regs[j]) }} ; ACC.ADD ; {{ coeff() }} ;;
    {{ product(regs[j]) }} ; ACC.ADD {% if not last or j < 2 * p - 2 or next_bundle %}; {{ coeff() }}{% endif %} {% if j == 2 * p - 2 %}{% if not last %}; DEC LR4 1 ; BNE LR4 CR1 {{ label }}{% else %}; {{ store(ds) }} {% if next_bundle %}; DEC LR6 1 ; BNE LR6 CR1 spatial_bundle{% endif %}{% endif %}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro bundle(ds, label, next_bundle) %}
    {{ bias('ACC.ADD.FIRST') }} ; SUB LR2 LR5 CR1 ; SET LR4 {{ cr.in_groups }} ;;
    {{ bias('ACC.ADD') }} ; DEC LR4 1 ; BEQ LR4 CR1 {{ label }}_last ;;
{{ label }}:
    {{ diagonal(false, label, ds, false) }}
{{ label }}_last:
    {{ diagonal(true, label, ds, next_bundle) }}
{% endmacro %}
{% for j in range(2 * p - 1) %}
    SET {{ regs[j] }} CR0 ;;
    INC {{ regs[j] }} {{ 128 + (j - p + 1) * in0_d3 }} ;;
{% endfor %}
    SET LR5 CR0 ; SET LR9 {{ cr.spatial_rows }} ;;
spatial_row:
    SET LR6 {{ cr.out_groups }} ; SUB LR8 LR0 CR1 ;;
    {{ coeff() }} {% if n > p %}; DEC LR6 1{% endif %} ;;
{% if n > p %}
spatial_bundle:
    {{ bundle(cr.width_ds, 'full_diagonal', true) }}
{% endif %}
    {{ bundle(cr.last_ds, 'tail_diagonal', false) }}
    ADD LR5 LR5 {{ cr.in_groups }} ; DEC LR9 1 ; BNE LR9 CR1 spatial_row ;;
{% endif %}
    HALT ;;
