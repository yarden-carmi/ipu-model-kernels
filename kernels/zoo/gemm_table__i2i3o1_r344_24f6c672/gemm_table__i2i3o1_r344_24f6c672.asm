{% set chunks = (in0_d2 + 127) // 128 %}
{% set skipfull = n // 128 %}
{% set shift = n % 128 %}
{% set tiles = (n + shift + 127) // 128 %}
{% set rem = m % in0_d2 %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% macro fetch() %}INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0{% endmacro %}
{% macro mac(src, accum='ADD') -%}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ accum }}
{%- endmacro %}
{% macro store(fn, ds) -%}
    ACTIVATE.QUANTIZE {{ fn }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}

# Gather one pixel from successive skip channels into the output lane tile.
{% macro gather(tag, count) %}
    SET LR10 CR0 ; SET LR8 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; INC LR8 {{ count }} ;;
{{ tag }}:
    LD.MULT R0 LR14 {{ cr.in1 }} ; DEC LR8 1 ;;
    LD.MULT.CYCLIC LR10 {{ cr.basis }} LR0 ; INC LR14 {{ in1_d2 }} ;;
    MULT.RC.VE LR0 LR13 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; INC LR10 1 ; BNE LR8 CR0 {{ tag }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR7 CR0 ; SET LR13 CR0 ;;
    SET LR10 CR0 ;;
{% for i in range(5) %}
    {% if i %}INC LR10 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR10 ;;
{% endfor %}
pixel:
    SET LR14 LR3 ;;
{% if skipfull %}
    SET LR15 CR0 ;;
    INC LR15 {{ skipfull }} ;;
skip_tile:
    {{ gather('skip_lane', 128) }}
    {{ store('identity', cr.full) }} ;;
    INC LR2 1 ; DEC LR15 1 ; BNE LR15 CR1 skip_tile ;;
{% endif %}
    SET LR4 CR0 ; SET LR11 CR0 ;;
    INC LR11 {{ tiles }} ; DEC LR4 1 ;;
gemm_tile:
    SET LR5 LR1 ; SET LR6 LR7 ; SET LR10 LR12 ;;
    {{ fetch() }} ;;
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ fetch() }} ;;
    {{ mac('CR1') }} ; {{ fetch() }} ;;
channel:
{% if chunks == 2 %}
    ADD LR8 LR5 CR1 ; LD.MULT R1 LR8 {{ cr.in0 }} ;;
{% endif %}
    LD.MULT R0 LR5 {{ cr.in0 }} ; DEC LR10 1{% if rem %} ; SET LR8 LR6{% endif %} ;;
{% set src = 'LR8' if rem else 'LR6' %}
    {{ mac(src) }} ; {{ fetch() }}{% if rem %} ; INC LR6 {{ rem }}{% endif %} ; BEQ LR10 CR0 last_channel ;;
    {{ mac(src) }} ; {{ fetch() }} ; ADD LR5 LR5 {{ cr.stride }} ; {{ 'BLT.S LR6 ' ~ cr.in0_d2 ~ ' channel' if rem else 'B channel' }} ;;
{% if rem %}
    SUB LR6 LR6 {{ cr.in0_d2 }} ; INC LR5 {{ chunks }} ; B channel ;;
{% endif %}
last_channel:
    {{ mac(src) }} ;;
{% if shift %}
    SET LR15 CR0 ;;
    INC LR15 {{ tiles }} ;;
    BNE LR11 LR15 direct_store ;;
    {{ store(act, cr.tail if tiles == 1 else cr.full) }} ;;
    {{ gather('merge_lane', shift) }}
    LD.MULT R0 LR2 {{ cr.out0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.ADD ; {{ store('identity', cr.tail if tiles == 1 else cr.full) }} ;;
    B {{ 'next_pixel' if tiles == 1 else 'next_tile' }} ;;
direct_store:
{% endif %}
    BEQ LR11 CR1 final_tile ;;
    {{ store(act, cr.full) }} ;;
next_tile:
    INC LR2 1 ; DEC LR11 1 ; B gemm_tile ;;
final_tile:
    {{ store(act, cr.tail) }} ;;
next_pixel:
    INC LR2 1 ; INC LR7 1 ; INC LR13 1 ;;
    DEC LR9 1 ; BEQ LR9 CR1 done ;;
    BNE LR7 {{ cr.in0_d2 }} advance_x ;;
    SET LR7 CR0 ; INC LR1 {{ chunks }} ;;
advance_x:
    BNE LR13 {{ cr.in1_d3 }} pixel ;;
    SET LR13 CR0 ; INC LR3 1 ; B pixel ;;
done:
    HALT ;;
