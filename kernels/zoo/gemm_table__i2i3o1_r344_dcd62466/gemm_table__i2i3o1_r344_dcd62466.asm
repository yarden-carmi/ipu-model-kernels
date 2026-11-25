{% set chunks = (in0_d2 + 127) // 128 %}
{% set shift = n % 128 %}
{% set tiles = (n + shift + 127) // 128 %}
{% set group = (128 // in1_d3) * in1_d3 %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% macro fetch() %}INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0{% endmacro %}
{% macro mac(src, accum='ADD') %}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ accum }}
{%- endmacro %}
{% macro store(base, offset, fn, ds) %}
    ACTIVATE.QUANTIZE {{ fn }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ base }} {{ offset }}
{%- endmacro %}
{% macro gather(tag, count) %}
    SET LR12 CR0 ; SET LR13 CR0 ; SET LR8 CR0 ; LD.MULT R0 LR3 {{ cr.in1 }} ;;
    INC LR8 {{ count }} ;;
{{ tag }}:
    MULT.EE LR14 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD12 7 ; ADD LR3 LR3 {{ cr.skip_rows }} ; DEC LR8 1 ;;
    ADDBI LRD12 1 ; BEQ LR8 CR0 {{ tag }}_done ;;
    LD.MULT R0 LR3 {{ cr.in1 }} ; B {{ tag }} ;;
{{ tag }}_done:
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR7 CR0 ; SET LR11 CR0 ; SET LR14 CR0 ;;
    SET LR15 CR0 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR11 ;;
    INC LR11 1 ;;
{% endfor %}
pixel:
    SET LR3 LR15 ; SET LR11 CR0 ; SET LR4 CR0 ;;
    DEC LR4 1 ;;
{% if n >= 128 %}
    INC LR11 {{ n // 128 }} ;;
skip_tile:
    {{ gather('skip_channel', 128) }}
    {{ store(cr.out0, 'LR2', 'identity', cr.full) }} ; DEC LR11 1 ;;
    INC LR2 1 ; BNE LR11 CR0 skip_tile ;;
{% endif %}
gemm_tile:
    SET LR5 LR1 ; SET LR6 LR7 ; SET LR10 CR0 ;;
    INC LR10 {{ k }} ; INC LR11 1 ; {{ fetch() }} ;;
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ fetch() }} ;;
    {{ mac('CR1') }} ; {{ fetch() }} ;;
channel:
{% if chunks == 2 %}
    ADD LR8 LR5 CR1 ; LD.MULT R1 LR8 {{ cr.in0 }} ;;
{% endif %}
    LD.MULT R0 LR5 {{ cr.in0 }} ; DEC LR10 1 {% if m % in0_d2 %}; SET LR12 LR6{% endif %} ;;
{% if m % in0_d2 %}
    {{ mac('LR12') }} ; {{ fetch() }} ; INC LR6 {{ m % in0_d2 }} ; BEQ LR10 CR0 last_channel ;;
    {{ mac('LR12') }} ; {{ fetch() }} ; ADD LR5 LR5 {{ cr.stride }} ; BLT.S LR6 {{ cr.in0_d2 }} channel ;;
    SUB LR6 LR6 {{ cr.in0_d2 }} ; INC LR5 {{ chunks }} ; B channel ;;
{% else %}
    {{ mac('LR6') }} ; {{ fetch() }} ; BEQ LR10 CR0 last_channel ;;
    {{ mac('LR6') }} ; {{ fetch() }} ; ADD LR5 LR5 {{ cr.stride }} ; B channel ;;
{% endif %}
last_channel:
    {{ mac('LR12' if m % in0_d2 else 'LR6') }} ;;
{% if shift %}
    BEQ LR11 CR1 merge_skip ;;
{% endif %}
{% if tiles > 1 %}
    SET LR8 CR0 ;;
    INC LR8 {{ tiles }} ;;
    BEQ LR11 LR8 final_tile ;;
    {{ store(cr.out0, 'LR2', act, cr.full) }} ;;
    INC LR2 1 ; B gemm_tile ;;
final_tile:
{% endif %}
    {{ store(cr.out0, 'LR2', act, cr.tail) }} ;;
next_pixel:
    INC LR2 1 ; INC LR7 1 ; DEC LR9 1 ; BEQ LR9 CR1 done ;;
    INC LR14 1 ;;
    SET LR8 CR0 ;;
    INC LR8 {{ group }} ;;
    BNE LR14 LR8 advance_in0 ;;
    SET LR14 CR0 ; INC LR15 1 ;;
advance_in0:
    BNE LR7 {{ cr.in0_d2 }} pixel ;;
    SET LR7 CR0 ; INC LR1 {{ chunks }} ; B pixel ;;
done:
    HALT ;;
{% if shift %}
merge_skip:
    {{ store(cr.tmp, 'LR0', act, cr.full) }} ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
    {{ gather('merge_channel', shift) }}
{% if tiles == 1 %}
    {{ store(cr.out0, 'LR2', 'identity', cr.tail) }} ; B next_pixel ;;
{% else %}
    {{ store(cr.out0, 'LR2', 'identity', cr.full) }} ;;
    INC LR2 1 ; B gemm_tile ;;
{% endif %}
{% endif %}
