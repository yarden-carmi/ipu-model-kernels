{% set chunks = (in0_d2 + 127) // 128 %}
{% set skipfull = n // 128 %}
{% set shift = n % 128 %}
{% set tiles = (n + shift + 127) // 128 %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% macro fetch() %}INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0{% endmacro %}
{% macro mac(src, accum='ADD') %}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ accum }}
{%- endmacro %}
{% macro copy(qf, accum='ADD.FIRST') %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ qf }}.L ; ACC.{{ accum }}
{%- endmacro %}
{% macro store(base, offset, fn, ds) %}
    ACTIVATE.QUANTIZE {{ fn }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ base }} {{ offset }}
{%- endmacro %}

    # Transpose the skip tensor into pixel-major channel vectors.
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    INC LR5 2 ; SET LR8 CR0 ; SET LR12 CR0 ;;
    INC LR12 {{ in1_d2 }} ; SET LR13 CR0 ;;
    INC LR13 128 ;;
transpose_y:
    SET LR14 CR0 ; SET LR15 CR0 ; SET LR11 CR0 ;;
    INC LR11 {{ in1_d3 }} ;;
transpose_x:
    SET LR4 LR14 ; ADD LR6 LR15 LR8 ; SET LR7 CR0 ;;
    BLT.S LR6 LR13 transpose_in_row ;;
    SUB LR6 LR6 LR13 ; INC LR4 1 ;;
transpose_in_row:
    INC LR7 {{ n }} ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR10 CR0 ;;
    INC LR10 128 ;;
transpose_channel:
    LD.MULT R0 LR4 {{ cr.in1 }} ;;
    MULT.EE LR6 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR4 {{ (in1_d2 * in1_d3 + 127) // 128 }} ; DEC LR7 1 ; DEC LR10 1 ;;
    ADDBI LRD2 1 ; BEQ LR7 CR0 transpose_last ;;
    BNE LR10 CR0 transpose_channel ;;
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in1 }}.L {{ cr.tmp }} LR5 ;;
    INC LR5 1 ;;
    SET LR2 CR0 ; SET LR3 CR0 ; INC LR10 128 ; B transpose_channel ;;
transpose_last:
    ACTIVATE.QUANTIZE identity {{ cr.skip_tail }}.L {{ cr.qf_in1 }}.L {{ cr.tmp }} LR5 ;;
    INC LR5 1 ;;
    INC LR15 {{ in1_d2 }} ; DEC LR11 1 ;;
    BLT.S LR15 LR13 transpose_advance ;;
    SUB LR15 LR15 LR13 ; INC LR14 1 ;;
transpose_advance:
    BNE LR11 CR0 transpose_x ;;
transpose_next_y:
    INC LR8 1 ; DEC LR12 1 ; BNE LR12 CR1 transpose_y ;;

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR7 CR0 ;;
    INC LR3 2 ;;
    SET LR11 CR0 ; SET LR15 CR0 ;;
    INC LR15 {{ tiles }} ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR11 ;;
    INC LR11 1 ;;
{% endfor %}
pixel:
{% if skipfull %}
    SET LR10 CR0 ;;
    INC LR10 {{ skipfull }} ;;
skip_tile:
    LD.MULT R0 LR3 {{ cr.tmp }} ;;
    {{ copy(cr.qf_in1) }} ; {{ store(cr.out0, 'LR2', 'identity', cr.full) }} ;;
    INC LR3 1 ; INC LR2 1 ; DEC LR10 1 ; BNE LR10 CR1 skip_tile ;;
{% endif %}
    SET LR4 CR0 ; SET LR11 CR0 ;;
    DEC LR4 1 ;;
gemm_tile:
    SET LR5 LR1 ; SET LR6 LR7 ; SET LR10 CR0 ;;
    INC LR10 {{ k }} ; INC LR11 1 ; {{ fetch() }} ;;
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ fetch() }} ;;
    {{ mac('CR1') }} ; {{ fetch() }} ;;
{% if m % in0_d2 and m < in0_d2 %}
{% if chunks == 2 %}
    ADD LR8 LR5 CR1 ; LD.MULT R0 LR5 {{ cr.in0 }} ;;
    LD.MULT R1 LR8 {{ cr.in0 }} ;;
{% else %}
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
{% endif %}
channel_reuse:
    SET LR12 LR6 ; DEC LR10 1 ;;
    {{ mac('LR12') }} ; {{ fetch() }} ; INC LR6 {{ m }} ; BEQ LR10 CR0 last_channel ;;
    {{ mac('LR12') }} ; {{ fetch() }} ; BLT.S LR6 {{ cr.in0_d2 }} channel_reuse ;;
    SUB LR6 LR6 {{ cr.in0_d2 }} ; INC LR5 {{ chunks }} ;;
{% if chunks == 2 %}
    ADD LR8 LR5 CR1 ; LD.MULT R0 LR5 {{ cr.in0 }} ;;
    LD.MULT R1 LR8 {{ cr.in0 }} ; B channel_reuse ;;
{% else %}
    LD.MULT R0 LR5 {{ cr.in0 }} ; B channel_reuse ;;
{% endif %}
{% else %}
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
{% endif %}
last_channel:
{% set last_src = 'LR12' if m % in0_d2 else 'LR6' %}
{% if shift %}
    BEQ LR11 CR1 merge_skip ;;
{% endif %}
    {{ mac(last_src) }} ; BEQ LR11 LR15 final_tile ;;
    {{ store(cr.out0, 'LR2', act, cr.full) }} ;;
    INC LR2 1 ; B gemm_tile ;;
final_tile:
    {{ store(cr.out0, 'LR2', act, cr.tail) }} ;;
next_pixel:
    INC LR2 1 ; INC LR7 1 ; DEC LR9 1 ; BEQ LR9 CR1 done ;;
    BNE LR7 {{ cr.in0_d2 }} pixel ;;
    SET LR7 CR0 ; INC LR1 {{ chunks }} ; B pixel ;;
done:
    HALT ;;
{% if shift %}
merge_skip:
    {{ mac(last_src) }} ; {{ store(cr.tmp, 'LR0', act, cr.full) }} ; LD.MULT R0 LR3 {{ cr.tmp }} ;;
    {{ copy(cr.qf_in1) }} ; {{ store(cr.tmp, 'LR11', 'identity', cr.skip_tail) }} ; LD.MULT R0 LR0 {{ cr.tmp }} ;;
    {{ copy(cr.qf_out0) }} ; LD.MULT R0 LR11 {{ cr.tmp }} ;;
    {{ copy(cr.qf_out0, 'ADD') }} ; INC LR3 1 ;;
{% if tiles == 1 %}
    {{ store(cr.out0, 'LR2', 'identity', cr.tail) }} ; B next_pixel ;;
{% else %}
    {{ store(cr.out0, 'LR2', 'identity', cr.full) }} ;;
    INC LR2 1 ; B gemm_tile ;;
{% endif %}
{% endif %}
