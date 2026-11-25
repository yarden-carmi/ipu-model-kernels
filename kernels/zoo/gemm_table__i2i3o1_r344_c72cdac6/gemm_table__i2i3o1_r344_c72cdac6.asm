{% set chunks = (in0_d2 + 127) // 128 %}
{% set skipfull = n // 128 %}
{% set shift = n % 128 %}
{% set tiles = (n + shift + 127) // 128 %}
{% set rem = m % in0_d2 %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% macro fetch() %}INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0{% endmacro %}
{% macro mac(src, accum='ADD') %}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ accum }}
{%- endmacro %}
{% macro vector(qf, scalar='CR1') %}
    MULT.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ qf }}.L ; ACC.ADD.FIRST
{%- endmacro %}
{% macro store(base, offset, fn, ds) %}
    ACTIVATE.QUANTIZE {{ fn }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ base }} {{ offset }}
{%- endmacro %}
{% macro gather(label, count) %}
    SET LR13 CR0 ; SET LR10 CR0 ;;
    LD.MULT R0 LR3 {{ cr.in1 }} ; INC LR10 {{ count }} ;;
{{ label }}:
    MULT.EE LR15 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD12 LRD12 7 ; INC LR3 1 ; DEC LR10 1 ; BEQ LR10 CR1 {{ label }}_end ;;
    ADDBI LRD12 1 ; LD.MULT R0 LR3 {{ cr.in1 }} ; B {{ label }} ;;
{{ label }}_end:
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR7 CR0 ; SET LR15 CR0 ; SET LR12 CR0 ;;
{% for i in range(5) %}
    {% if i %}INC LR12 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR12 ;;
{% endfor %}
    SET LR12 CR0 ; SET LR3 CR0 ;;
pixel:
{% if skipfull %}
    SET LR11 CR0 ;;
    INC LR11 {{ skipfull }} ;;
skip_tile:
    {{ vector(cr.qf_in1, 'CR0') }} ;;
    {{ gather('gather_full', 128) }}
    {{ store(cr.out0, 'LR2', 'identity', cr.full) }} ; DEC LR11 1 ;;
    INC LR2 1 ; BNE LR11 CR0 skip_tile ;;
{% endif %}
    SET LR4 CR0 ; SET LR11 CR0 ;;
    DEC LR4 1 ;;
gemm_tile:
    SET LR5 LR1 ; SET LR6 LR7 ; SET LR10 LR8 ;;
    INC LR11 1 ; {{ fetch() }} ;;
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ fetch() }} ;;
    {{ mac('CR1') }} ; {{ fetch() }} ;;
channel:
{% if chunks == 2 %}
    ADD LR12 LR5 CR1 ; LD.MULT R1 LR12 {{ cr.in0 }} ;;
{% endif %}
    LD.MULT R0 LR5 {{ cr.in0 }} ; DEC LR10 1 {% if rem %}; SET LR12 LR6{% endif %} ;;
    {{ mac('LR6') }} ; {{ fetch() }} ; BEQ LR10 CR0 last_channel ;;
    {{ mac('LR12' if rem else 'LR6') }} ; {{ fetch() }} ; ADD LR5 LR5 {{ cr.stride }} {% if rem %}; INC LR6 {{ rem }}{% endif %} ;;
{% if rem %}
    BLT.S LR6 {{ cr.in0_d2 }} channel ;;
    SUB LR6 LR6 {{ cr.in0_d2 }} ; INC LR5 {{ chunks }} ;;
{% endif %}
    B channel ;;
last_channel:
    {{ mac('LR6') }} {% if shift %}; BEQ LR11 CR1 merge_skip{% endif %} ;;
{% if tiles > 1 %}
    SET LR10 CR0 ;;
    INC LR10 {{ tiles }} ;;
    BEQ LR11 LR10 final_tile ;;
    {{ store(cr.out0, 'LR2', act, cr.full) }} ;;
    INC LR2 1 ; B gemm_tile ;;
{% endif %}
final_tile:
    {{ store(cr.out0, 'LR2', act, cr.tail) }} ; B next_pixel ;;
{% if shift %}
merge_skip:
    {{ store(cr.tmp, 'LR0', act, cr.full) }} ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    {{ vector(cr.qf_out0) }} ;;
    {{ gather('gather_mixed', shift) }}
    {{ store(cr.out0, 'LR2', 'identity', cr.tail if tiles == 1 else cr.full) }} ;;
{% if tiles > 1 %}
    INC LR2 1 ; B gemm_tile ;;
{% endif %}
{% endif %}
next_pixel:
    INC LR2 1 ; INC LR7 1 ; DEC LR9 1 ;;
    INC LR15 1 ; BEQ LR9 CR0 done ;;
    BNE LR15 {{ cr.in1_d3 }} same_y ;;
    SET LR15 CR0 ; B advance_input ;;
same_y:
    SUB LR3 LR3 LR14 ;;
advance_input:
    BNE LR7 {{ cr.in0_d2 }} pixel ;;
    SET LR7 CR0 ; INC LR1 {{ chunks }} ; B pixel ;;
done:
    HALT ;;
