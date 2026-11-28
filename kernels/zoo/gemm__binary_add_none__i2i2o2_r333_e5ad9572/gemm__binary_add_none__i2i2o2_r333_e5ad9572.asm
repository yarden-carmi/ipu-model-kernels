{% set span = in1_d1 * in1_d2 %}
{% set fast = span % 128 == 0 %}
{% set stride = s0_m % 128 %}
{% set packed = out0_d2 > 144 %}
{% set limit = (s0_k - 1) % 128 %}
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
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{ds}}.L {{cr.qf_out0}}.L {{cr.out0}} LR3 ; INC LR3 1 ; SUB LR5 LR0 CR1 ;;
{% endmacro %}
{% macro mac(src) -%}
    MULT.RC.VE LR0 {{src}} 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD
{%- endmacro %}
{% macro weight() -%}
    LD.MULT.CYCLIC LR4 {{cr.w}} LR0 ; INC LR4 1
{%- endmacro %}
{% macro residual(index) -%}
    MULT.EE {{index}} CR1 0 LR0 {{cr.full}}.L {{cr.qf_in1}}.L ; AGG.SUM.FIRST LR5 {{cr.scalar}}.L ; INC LR5 1 ; DEC LR6 1
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ;;
    SUB LR2 LR0 CR1 ; SUB LR3 LR0 CR1 ; SUB LR5 LR0 CR1 ;;
batch:
    SUB LR4 LR0 CR1 ;;
{{ integer('LR15', out0_d1) }}
token:
    SET LR6 {{cr.s0_n}} ; SET LR12 LR1 ; SET LR13 CR0 ;;
{{ integer('LR14', out0_d1) }}
batch_index:
    BLT.S LR12 LR14 interleave ;;
    SUB LR12 LR12 LR14 ; INC LR13 1 ; B batch_index ;;
interleave:
    SET LR8 LR12 ;;
{% for bit in range(17) %}
    {% if out0_d0 // (2 ** bit) % 2 %}ADD LR13 LR13 LR8 ;;{% endif %}
    {% if out0_d0 // (2 ** (bit + 1)) %}ADD LR8 LR8 LR8 ;;{% endif %}
{% endfor %}
{% if fast %}
    SET LR12 CR0 ; SET LR14 CR0 ;;
    INC LR14 128 ;;
origin:
    BLT.S LR13 LR14 segment ;;
    SUB LR13 LR13 LR14 ; INC LR12 1 ; B origin ;;
{% else %}
    SET LR12 LR13 ;;
{% endif %}
segment:
    ADD LR7 LR5 LR6 ; SET LR8 CR0 ;;
    INC LR8 127 ;;
    BLT.S LR7 LR8 segment_size ;;
    SET LR7 LR8 ;;
segment_size:
{% if fast %}
{{ integer('LR11', s0_m // 128) }}
{% if stride %}
    SET LR14 CR0 ;;
    INC LR14 128 ;;
{% endif %}
gather_load:
    LD.MULT R0 LR12 {{cr.in1}} ;;
gather:
    {{residual('LR13')}} ; ADD LR12 LR12 LR11 ;;
{% if stride %}
    INC LR13 {{stride}} ;;
    BLT.S LR13 LR14 gather_next ;;
    SUB LR13 LR13 LR14 ; INC LR12 1 ;;
gather_next:
{% endif %}
    BLT.S LR5 LR7 gather_load ;;
{% else %}
    DEC LR7 1 ;;
{{ integer('LR8', span) }}
{{ integer('LR9', s0_m) }}
{{ integer('LR10', (span + 127) // 128) }}
{{ integer('LR11', 128) }}
gather_load:
    SET LR13 LR12 ; SET LR14 CR0 ;;
res_batch:
    BLT.S LR13 LR8 res_row ;;
    SUB LR13 LR13 LR8 ; ADD LR14 LR14 LR10 ; B res_batch ;;
res_row:
    BLT.S LR13 LR11 res_load ;;
    SUB LR13 LR13 LR11 ; INC LR14 1 ; B res_row ;;
res_load:
    LD.MULT R0 LR14 {{cr.in1}} ;;
    {{residual('LR13')}} ; ADD LR12 LR12 LR9 ; BLT.S LR5 LR7 gather_load ;;
{% endif %}
    {{weight()}} ; SET LR8 LR2 ; SET LR10 {{cr.chunks}} ;;
    {{mac('CR1')}} ; {{weight()}} ;;
chunk:
    LD.MULT R0 LR8 {{cr.in0}} ; INC LR8 1 ; SUB LR9 LR0 CR1 ; DEC LR10 1 ;;
    SET LR11 CR0 {% if limit != 127 %}; BEQ LR10 CR0 last_limit {% endif %} ;;
    INC LR11 125 {% if limit != 127 %}; B lane {% endif %} ;;
{% if limit != 127 %}
last_limit:
    {% if limit > 2 %}INC LR11 {{limit - 2}} ;;{% elif limit == 1 %}DEC LR11 1 ;;{% endif %}
    {% if not limit %}B final_product ;;{% endif %}
{% endif %}
lane:
    {{mac('LR9')}} ; {{weight()}} ; INC LR9 1 ; BLT.S LR9 LR11 lane ;;
    BEQ LR10 CR0 final_product ;;
    {{mac('LR9')}} ; INC LR9 1 ; {{weight()}} ; B chunk ;;
final_product:
    {{mac('LR9')}} ; INC LR9 1 ;;
    SET LR14 CR0 ;;
    INC LR14 127 ;;
    BNE LR5 LR14 segment_done ;;
    {{store(cr.full)}}
segment_done:
    BNE LR6 CR0 segment ;;
{% if not packed %}
    BLT.S LR5 CR0 token_done ;;
    {{store(cr.tail)}}
token_done:
{% endif %}
    INC LR1 1 ; ADD LR2 LR2 {{cr.chunks}} ; DEC LR15 1 ;;
    BEQ LR15 CR0 batch_done ;;
    BNE LR4 {{cr.weight_last}} token ;;
    SUB LR4 LR0 CR1 ; B token ;;
batch_done:
{% if packed %}
    BLT.S LR5 CR0 advance_batch ;;
    {{store(cr.tail)}}
advance_batch:
{% endif %}
    BLT.S LR1 {{cr.rows}} batch ;;
    HALT ;;
