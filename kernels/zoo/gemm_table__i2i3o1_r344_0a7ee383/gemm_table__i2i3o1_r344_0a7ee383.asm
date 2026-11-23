{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% set copy_blocks = n // 128 %}
{% set copy_tail = n % 128 %}
{% set gemm_blocks = (out0_d1 + 127) // 128 - copy_blocks %}

{% macro store(fn) %}
    ACTIVATE.QUANTIZE {{ fn }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ;;
{% endmacro %}

# LR1 and LR3 hold the final bytes of the source/destination shuffle maps.
# One spatial lane is taken from each successive channel plane of in1.
{% macro gather(count, label) %}
    SUB LR3 LR0 LR15 ; SET LR9 CR0 ;;
    INC LR9 {{ count }} ;;
{{ label }}:
    LD.MULT R0 LR8 {{ cr.in1 }} ; DEC LR9 1 ; ADD LR3 LR3 LR15 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; ADD LR8 LR8 {{ cr.copy_stride }} ; BNE LR9 CR0 {{ label }} ;;
{% endmacro %}

{% macro bias_add(acc) %}
    LD.MULT R0 LR7 {{ cr.b }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ acc }} ; INC LR7 1 ;;
{% endmacro %}

{% macro tap(i) %}
{% set odd = m % 128 and i % 2 %}
{% set row = 'LR2' if odd else 'LR8' %}
{% set lane = 'LR3' if odd else 'LR5' %}
{% set stride = (2 * m if m % 128 else m) // 128 %}
    LD.MULT R0 {{ row }} {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR6 {{ cr.w }} LR0 ; INC LR6 1 ; INC {{ row }} {{ stride }}{% if i == 0 %} ; DEC LR10 1{% endif %} ;;
    MULT.RC.VE LR0 {{ lane }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR6 {{ cr.w }} LR11 ; INC LR6 1 ;;
    MULT.RC.VE LR11 {{ lane }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if i == 7 %} ; BNE LR10 CR0 k_group{% endif %} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR11 CR0 ; SET LR12 CR0 ;;
    SET LR14 CR0 ; INC LR11 128 ;;
    DEC LR14 1 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR14 ; INC LR14 1 ;;
{% endfor %}
    SET LR14 CR0 ;;
pixel:
{% if copy_blocks %}
    SET LR8 LR12 ; SET LR10 CR0 ;;
    INC LR10 {{ copy_blocks }} ;;
copy_block:
    DEC LR10 1 ;;
    {{ gather(128, 'copy_channel') }}
    {{ store('identity') }}
    INC LR14 1 ; BNE LR10 CR0 copy_block ;;
{% endif %}
    SET LR6 CR0 ; SET LR7 CR0 ; SET LR13 CR0 ;;
    INC LR13 {{ gemm_blocks }} ; DEC LR6 1 ;;
gemm_block:
    SET LR8 LR4 ; SET LR10 CR0 ;;
    INC LR10 {{ k // 8 }} ;;
{% if m % 128 %}
    SET LR2 LR4 ; SET LR3 LR5 ;;
    INC LR3 64 ;;
    BLT.S LR3 LR11 odd_ready ;;
    DEC LR3 128 ; INC LR2 1 ;;
odd_ready:
{% endif %}
{% if bias %}
    {{ bias_add('ACC.ADD.FIRST') }}
    {{ bias_add('ACC.ADD') }}
{% else %}
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
k_group:
{% for i in range(8) %}
    {{ tap(i) }}
{% endfor %}
    {{ store(act) }}
{% if copy_tail %}
    SET LR9 CR0 ;;
    INC LR9 {{ gemm_blocks }} ;;
    BNE LR13 LR9 block_done ;;
    # Recover the activated lanes, then overwrite only the skip-input prefix.
    LD.MULT R0 LR14 {{ cr.out0 }} ; ADD LR8 LR12 {{ cr.copy_prefix_rows }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
    {{ gather(copy_tail, 'tail_channel') }}
    {{ store('identity') }}
block_done:
{% endif %}
    INC LR14 1 ; DEC LR13 1 ;;
    BNE LR13 CR0 gemm_block ;;
    ADD LR1 LR1 LR15 ; INC LR5 1 ;;
    BNE LR1 {{ cr.spatial_wrap }} skip_spatial_wrap ;;
    SET LR1 CR0 ; INC LR12 1 ;;
skip_spatial_wrap:
    BNE LR5 LR11 next_pixel ;;
    SET LR5 CR0 ; INC LR4 1 ;;
next_pixel:
    BLT.S LR14 {{ cr.out_rows }} pixel ;;
    HALT ;;
