{% set chunks = (in0_d2 + 127) // 128 %}
{% set span = in1_d1 * in1_d2 %}
{% set aligned = span % 128 == 0 %}
{% set rem = s0_m % 128 %}
{% macro integer(reg, value) %}
    SET {{reg}} CR0 ;;
{% for shift in [24,16,8,0] %}
{% if value // (2 ** (shift+8)) %}
{% for bit in range(8) %}
    ADD {{reg}} {{reg}} {{reg}} ;;
{% endfor %}
{% endif %}
{% if (value // (2 ** shift)) % 256 %}
    INC {{reg}} {{(value // (2 ** shift)) % 256}} ;;
{% endif %}
{% endfor %}
{% endmacro %}
{% macro dot(slot) -%}
MULT.RC.VV {{slot}} R0 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; AGG.SUM LR2 {{cr.full}}.L
{%- endmacro %}
{% macro store(ds) -%}
ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{ds}}.L {{cr.qf_out0}}.L {{cr.out0}} LR1 ; INC LR1 1
{%- endmacro %}

    SET LR0 CR0 ; DEC LR1 1 ; SET LR3 CR0 ;;
    SET LR5 CR0 ; SET LR11 CR0 ; SET LR12 {{cr.width}} ;;
    INC LR5 {{out0_d0}} ; ADD LR13 LR12 {{cr.width}} ;;
    ADD LR14 LR13 {{cr.width}} ;;
{% if not aligned %}
{{ integer('LR9', (span + 127) // 128) }}
{% endif %}
batch:
    SET LR4 {{cr.positions}} ; SUB LR2 LR0 CR1 ; SET LR10 CR0 ;;
    INC LR10 {{out0_d0}} {% if aligned %}; SET LR9 CR0{% endif %} ;;
    SUB LR10 LR10 LR5 ;;
position:
    SUB LR6 LR0 CR1 ; SET LR8 LR10 {% if aligned %}; SET LR7 LR9{% else %}; SET LR7 LR10{% endif %} ;;
{% if chunks <= 4 %}
{% for i in range(chunks) %}
    LD.MULT.CYCLIC LR3 {{cr.in0}} LR{{11+i}} ;;
    INC LR3 1 ;;
{% endfor %}
{% endif %}
channel:
{% if aligned %}
    LD.MULT R0 LR7 {{cr.in1}} ;;
{% else %}
    SET LR8 LR7 ; SET LR15 CR0 ;;
res_batch:
    BLT.S LR8 {{cr.residual_step}} res_row ;;
    SUB LR8 LR8 {{cr.residual_step}} ; ADD LR15 LR15 LR9 ; B res_batch ;;
res_row:
    BLT.S LR8 {{cr.width}} res_load ;;
    SUB LR8 LR8 {{cr.width}} ; INC LR15 1 ; B res_row ;;
res_load:
    LD.MULT R0 LR15 {{cr.in1}} ;;
{% endif %}
    MULT.EE LR8 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in1}}.L ; AGG.SUM.FIRST LR2 {{cr.one}}.L ; INC LR2 1 ; LD.MULT R0 LR6 {{cr.w}} ; INC LR6 1 ;;
    MULT.EE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; AGG.SUM LR2 {{cr.one}}.L ; LD.MULT R0 LR6 {{cr.w}} ; INC LR6 1 ;;
{% if chunks <= 4 %}
{% for i in range(chunks) %}
    {{dot('LR' ~ (11+i))}} {% if i+1 < chunks %}; LD.MULT R0 LR6 {{cr.w}} ; INC LR6 1{% endif %} ;;
{% endfor %}
{% else %}
    SUB LR12 LR3 CR1 ; SET LR13 CR0 ;;
    INC LR13 {{chunks - 1}} ;;
dot_next:
    LD.MULT.CYCLIC LR12 {{cr.in0}} LR0 ; INC LR12 1 ; BEQ LR13 CR0 dot_last ;;
    {{dot('LR0')}} ; DEC LR13 1 ; LD.MULT R0 LR6 {{cr.w}} ; INC LR6 1 ; B dot_next ;;
dot_last:
    {{dot('LR0')}} ;;
{% endif %}
    INC LR2 1 ;;
    BLT.S LR2 {{cr.width}} no_store ; DEC LR2 1 ;;
    {{store(cr.full)}} ; SUB LR2 LR0 CR1 ;;
no_store:
    BEQ LR6 {{cr.end}} position_end ;;
{% if aligned %}
    ADD LR7 LR7 {{cr.residual_step}} {% if rem %}; INC LR8 {{rem}}{% endif %} {% if not rem %}; B channel{% endif %} ;;
{% if rem %}
    BLT.S LR8 {{cr.width}} channel ;;
    SUB LR8 LR8 {{cr.width}} ; INC LR7 1 ; B channel ;;
{% endif %}
{% else %}
{{ integer('LR15', s0_m) }}
    ADD LR7 LR7 LR15 ; B channel ;;
{% endif %}
position_end:
{% if chunks > 4 %}
    INC LR3 {{chunks}} ;;
{% endif %}
    DEC LR4 1 ; INC LR10 {{out0_d0}} ;;
    BEQ LR4 CR0 batch_end ;;
{% if aligned %}
    BLT.S LR10 {{cr.width}} position ;;
    SUB LR10 LR10 {{cr.width}} ; INC LR9 1 ;;
{% endif %}
    B position ;;
batch_end:
{% if out0_d1 * out0_d2 % 128 %}
    {{store(cr.tail)}} ;;
{% endif %}
    DEC LR5 1 ;;
    BNE LR5 CR0 batch ;;
    HALT ;;
