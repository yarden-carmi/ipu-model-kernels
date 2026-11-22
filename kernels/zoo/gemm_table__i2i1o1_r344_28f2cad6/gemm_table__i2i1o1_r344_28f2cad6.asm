{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% set full_copy = n // 128 %}
{% set blocks = (out0_d1 + 127) // 128 - full_copy %}
{% set paired = m % 128 == 64 %}
{% set pipelined = m % 64 == 0 %}

{% macro store(fn, base, row) %}
    ACTIVATE.QUANTIZE {{ fn }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ base }} {{ row }} ;;
{% endmacro %}
{% macro copy_add(acc) %}
    LD.MULT R0 LR2 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; {{ acc }} ; INC LR2 1 ;;
{% endmacro %}
# Keep the coarse preload live across the backedge. The final group
# suppresses the last preload so it does not read past the weight tensor.
{% macro tap_group(final) %}
{% for i in range(8) %}
{% set odd = paired and i % 2 %}
{% set row = 'LR14' if odd else 'LR8' %}
{% set lane = 'LR9' if odd else 'LR5' %}
{% set stride = (2 * m if paired else m) // 128 %}
    LD.MULT R0 {{ row }} {{ cr.in0 }}{% if i == 0 and not final %} ; DEC LR10 8{% endif %} ;;
    MULT.RC.VE LR0 {{ lane }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC {{ row }} {{ stride }} ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.w }} LR11 ;;
    MULT.RC.VE LR11 {{ lane }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{% if not final or i < 7 %}
    ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.w }} LR0
{% endif %}
{% if i == 7 and not final %}
    ; BNE LR10 CR0 k_loop
{% endif %}
    ;;
{% endfor %}
{% endmacro %}
{% macro mac(i) %}
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    # Consume the coarse row while loading the correction. The correction
    # multiply in turn preloads the next tap's coarse row, except at tile end.
    LD.MULT.CYCLIC LR6 {{ cr.w }} LR11 ; MULT.RC.VE LR0 LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR6 1 ;;
    MULT.RC.VE LR11 LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{% if i < 7 %}
    ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.w }} LR0
{% endif %}
{% if m % 128 %}
    ; BLT.S LR9 LR12 lane_ok_{{ i }} ;;
    DEC LR9 128 ; INC LR8 1 ;;
lane_ok_{{ i }}:
    INC LR9 {{ m % 128 }}
{% if m >= 128 %}
    ; INC LR8 {{ m // 128 }}
{% endif %}
    ;;
{% else %}
    ; INC LR8 {{ m // 128 }} ;;
{% endif %}
{% endmacro %}
{% macro bias_add(index, acc) %}
    LD.MULT R0 LR7 {{ cr.b }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ acc }} ; INC LR7 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR11 CR0 ;;
    INC LR11 128 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR0 ;;
    INC LR0 1 ;;
{% endfor %}
    SET LR0 CR0 ;;
pixel:
{% if full_copy %}
    SET LR13 CR0 ;;
    INC LR13 {{ full_copy }} ;;
copy_block:
    {{ copy_add('ACC.ADD.FIRST') }}
    {{ store('identity', cr.out0, 'LR1') }}
    INC LR1 1 ; DEC LR13 1 ;;
    BNE LR13 CR0 copy_block ;;
{% endif %}
    SET LR6 CR0 ; SET LR7 CR0 ; SET LR13 CR0 ;;
    INC LR13 {{ blocks }} ; DEC LR6 1 ;;
gemm_block:
{% if pipelined %}
    SET LR8 LR4 ; SET LR10 {{ cr.ki }}{% if paired %} ; SET LR14 LR4{% endif %} ;;
    DEC LR10 8 ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.w }} LR0 ;;
{% if paired %}
# The even and odd taps each advance by an integral number of rows.
    SET LR9 LR5 ; SET LR12 CR0 ;;
    INC LR12 64 ; INC LR9 64 ;;
    BLT.S LR5 LR12 pair_ready ;;
    DEC LR9 128 ; INC LR14 1 ;;
pair_ready:
{% endif %}
{% else %}
    SET LR8 LR4 ; SET LR9 LR5 ; SET LR10 {{ cr.ki }} ;;
{% if m % 128 %}
    SET LR12 CR0 ;;
    INC LR12 {{ 128 - m % 128 }} ;;
{% endif %}
{% endif %}
{% if bias %}
    {{ bias_add(0, 'ACC.ADD.FIRST') }}
    {{ bias_add(1, 'ACC.ADD') }}
{% else %}
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
k_loop:
{% if pipelined %}
    {{ tap_group(false) }}
    {{ tap_group(true) }}
{% else %}
    INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.w }} LR0 ;;
{% for i in range(8) %}
    {{ mac(i) }}
{% endfor %}
    DEC LR10 8 ;;
    BNE LR10 CR0 k_loop ;;
{% endif %}
{% if n % 128 %}
    SET LR12 CR0 ;;
    INC LR12 {{ blocks }} ;;
    BNE LR13 LR12 direct ;;
    {{ store(act, cr.out0, 'LR1') }}
    {{ copy_add('ACC.ADD.FIRST') }}
    ACTIVATE.QUANTIZE identity {{ cr.copy_tail }}.L {{ cr.qf_in1 }}.L {{ cr.copy }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.copy }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
    LD.MULT R0 LR1 {{ cr.out0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.ADD ;;
    {{ store('identity', cr.out0, 'LR1') }}
    BEQ LR0 CR0 block_done ;;
direct:
{% endif %}
    {{ store(act, cr.out0, 'LR1') }}
block_done:
    INC LR1 1 ; DEC LR13 1 ;;
    BNE LR13 CR0 gemm_block ;;
    INC LR3 1 ; INC LR5 1 ;;
    BNE LR5 LR11 next_pixel ;;
    SET LR5 CR0 ; INC LR4 1 ;;
next_pixel:
    BLT.S LR3 {{ cr.mi }} pixel ;;
    HALT ;;
