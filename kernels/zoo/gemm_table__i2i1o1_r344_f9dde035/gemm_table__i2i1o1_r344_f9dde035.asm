{% set chunks = (in0_d2 + 127) // 128 %}
{% set skipfull = n // 128 %}
{% set shift = n % 128 %}
{% set tiles = (n + shift + 127) // 128 %}
{% macro addimm(reg, value) %}
{% for block in range((value // 255 + 31) // 32) %}
{% for i in range([32, value // 255 - block * 32] | min) %}    INC {{ reg }} 255 ;;
{% endfor %}{% endfor %}
{% if value % 255 %}    INC {{ reg }} {{ value % 255 }} ;;
{% endif %}{% endmacro %}
{% macro fetch() %}INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0{% endmacro %}
{% macro mac(src, accum='ADD') %}MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ accum }}{% endmacro %}
{% macro copy(qf, accum='ADD.FIRST') %}MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ qf }}.L ; ACC.{{ accum }}{% endmacro %}
{% macro store(base, offset, fn, ds, qf) %}ACTIVATE.QUANTIZE {{ fn }} {{ ds }}.L {{ qf }}.L {{ base }} {{ offset }}{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ;;
    {{ addimm('LR3', in0_d0) }}
transpose_outer:
    SET LR4 LR1 ; SET LR5 CR0 ;;
    {{ addimm('LR5', in0_d1) }}
transpose_inner:
{% for c in range(chunks) %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    {{ copy(cr.qf_in0) }} ; {{ store(cr.stage, 'LR2', 'identity', cr.full, cr.qf_in0) }} ;;
    INC LR4 1 ; INC LR2 1 ;;
{% endfor %}
    {{ addimm('LR4', (in0_d0 - 1) * chunks) }}
    DEC LR5 1 ; BNE LR5 CR1 transpose_inner ;;
    INC LR1 {{ chunks }} ; DEC LR3 1 ; BNE LR3 CR1 transpose_outer ;;

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR7 CR0 ; SET LR11 CR0 ;;
    SET LR15 CR0 ;;
    {{ addimm('LR15', tiles) }}
{% for i in range(5) %}
    {% if i %}INC LR11 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR11 ;;
{% endfor %}
pixel:
{% if skipfull %}
    SET LR10 CR0 ;;
    {{ addimm('LR10', skipfull) }}
skip_tile:
    LD.MULT R0 LR3 {{ cr.in1 }} ;;
    {{ copy(cr.qf_in1) }} ; {{ store(cr.out0, 'LR2', 'identity', cr.full, cr.qf_out0) }} ;;
    INC LR3 1 ; INC LR2 1 ; DEC LR10 1 ; BNE LR10 CR1 skip_tile ;;
{% endif %}
    SET LR4 CR0 ; SET LR11 CR0 ;;
    DEC LR4 1 ;;
gemm_tile:
    SET LR5 LR1 ; SET LR6 LR7 ; SET LR10 CR0 ;;
    {{ addimm('LR10', k) }}
    INC LR11 1 ; {{ fetch() }} ;;
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ fetch() }} ;;
    {{ mac('CR1') }} ; {{ fetch() }} ;;
{% if m % in0_d2 and m < in0_d2 %}
{% if chunks == 2 %}
    ADD LR8 LR5 CR1 ; LD.MULT R0 LR5 {{ cr.stage }} ;;
    LD.MULT R1 LR8 {{ cr.stage }} ;;
{% else %}
    LD.MULT R0 LR5 {{ cr.stage }} ;;
{% endif %}
channel_reuse:
    SET LR12 LR6 ; DEC LR10 1 ;;
    {{ mac('LR12') }} ; {{ fetch() }} ; INC LR6 {{ m }} ; BEQ LR10 CR0 last_channel ;;
    {{ mac('LR12') }} ; {{ fetch() }} ; BLT.S LR6 {{ cr.in0_d2 }} channel_reuse ;;
    SUB LR6 LR6 {{ cr.in0_d2 }} ; INC LR5 {{ chunks }} ;;
{% if chunks == 2 %}
    ADD LR8 LR5 CR1 ; LD.MULT R0 LR5 {{ cr.stage }} ;;
    LD.MULT R1 LR8 {{ cr.stage }} ; B channel_reuse ;;
{% else %}
    LD.MULT R0 LR5 {{ cr.stage }} ; B channel_reuse ;;
{% endif %}
{% else %}
channel:
{% if chunks == 2 %}
    ADD LR8 LR5 CR1 ; LD.MULT R1 LR8 {{ cr.stage }} ;;
{% endif %}
    LD.MULT R0 LR5 {{ cr.stage }} ; DEC LR10 1 {% if m % in0_d2 %}; SET LR12 LR6{% endif %} ;;
{% if m % in0_d2 %}
    {{ mac('LR12') }} ; {{ fetch() }} ; INC LR6 {{ m % in0_d2 }} ; BEQ LR10 CR0 last_channel ;;
    {{ mac('LR12') }} ; {{ fetch() }} ;;
    {{ addimm('LR5', (m // in0_d2) * chunks) }}
    BLT.S LR6 {{ cr.in0_d2 }} channel ;;
    SUB LR6 LR6 {{ cr.in0_d2 }} ; INC LR5 {{ chunks }} ; B channel ;;
{% else %}
    {{ mac('LR6') }} ; {{ fetch() }} ; BEQ LR10 CR0 last_channel ;;
    {{ mac('LR6') }} ; {{ fetch() }} ;;
    {{ addimm('LR5', (m // in0_d2) * chunks) }}
    B channel ;;
{% endif %}
{% endif %}
last_channel:
{% set last_src = 'LR12' if m % in0_d2 else 'LR6' %}
{% if shift %}    BEQ LR11 CR1 merge_skip ;;{% endif %}
    {{ mac(last_src) }} ; BEQ LR11 LR15 final_tile ;;
    {{ store(cr.out0, 'LR2', 'generic', cr.full, cr.qf_out0) }} ;;
    INC LR2 1 ; B gemm_tile ;;
final_tile:
    {{ store(cr.out0, 'LR2', 'generic', cr.tail, cr.qf_out0) }} ;;
next_pixel:
    INC LR2 1 ; INC LR7 1 ; DEC LR9 1 ; BEQ LR9 CR1 done ;;
    BNE LR7 {{ cr.in0_d2 }} pixel ;;
    SET LR7 CR0 ; INC LR1 {{ chunks }} ; B pixel ;;
done:
    HALT ;;
{% if shift %}
merge_skip:
    {{ mac(last_src) }} ; {{ store(cr.tmp, 'LR0', 'generic', cr.full, cr.qf_out0) }} ; LD.MULT R0 LR3 {{ cr.in1 }} ;;
    {{ copy(cr.qf_in1) }} ; {{ store(cr.tmp, 'LR11', 'identity', cr.skip_tail, cr.qf_out0) }} ; LD.MULT R0 LR0 {{ cr.tmp }} ;;
    {{ copy(cr.qf_out0) }} ; LD.MULT R0 LR11 {{ cr.tmp }} ;;
    {{ copy(cr.qf_out0, 'ADD') }} ; INC LR3 1 ;;
{% if tiles == 1 %}
    {{ store(cr.out0, 'LR2', 'identity', cr.tail, cr.qf_out0) }} ; B next_pixel ;;
{% else %}
    {{ store(cr.out0, 'LR2', 'identity', cr.full, cr.qf_out0) }} ;;
    INC LR2 1 ; B gemm_tile ;;
{% endif %}
{% endif %}
