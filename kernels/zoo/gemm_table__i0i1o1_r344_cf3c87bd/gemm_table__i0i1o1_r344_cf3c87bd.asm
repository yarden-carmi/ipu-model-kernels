{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% set full_copy = n // 128 %}
{% set blocks = (out0_d1 + 127) // 128 - full_copy %}
{% set groups = in0_d0 %}
{% set mixed = (k // groups) % 8 == 4 %}

{% macro store(fn, base, row) %}
    ACTIVATE.QUANTIZE {{ fn }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ base }} {{ row }} ;;
{% endmacro %}
{% macro mixed_group(single=false, last=false) %}
    LD.MULT R0 LR8 {{ cr.in0 }} ; SET LR9 LR5{% if last %} ; DEC LR10 1{% endif %} ;;
{% for i in range(groups) %}
{% if not single %}
    MULT.RC.VE LR0 LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR6 1{% if not loop.first %} ; INC LR9 1{% endif %} ; LD.MULT.CYCLIC LR6 {{ cr.w }} LR11 ;;
    MULT.RC.VE LR11 LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.w }} LR0{% if loop.last %} ; INC LR8 {{ m // 8 }}{% if last %} ; BNE LR10 CR0 k_loop{% endif %}{% endif %} ;;
{% else %}
    MULT.RC.VE LR0 LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if not loop.first %} ; INC LR9 1{% endif %} ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.w }} LR0{% if loop.last %} ; INC LR8 {{ m // 8 }}{% if last %} ; BNE LR10 CR0 k_loop{% endif %}{% endif %} ;;
{% endif %}
{% endfor %}
{% endmacro %}
{% macro copy_add(acc) %}
    LD.MULT R0 LR2 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; {{ acc }} ; INC LR2 1 ;;
{% endmacro %}
# Each packed input item contains one tap from each leading-dimension slab.
# Read it once and stream both weight components for every tap in the item.
{% macro tap_group(final, single=false) %}
    LD.MULT R0 LR8 {{ cr.in0 }} ; SET LR9 LR5{% if not final %} ; DEC LR10 1{% endif %} ;;
{% for i in range(groups) %}
{% if not single %}
    MULT.RC.VE LR0 LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR6 1{% if not loop.first %} ; INC LR9 1{% endif %} ; LD.MULT.CYCLIC LR6 {{ cr.w }} LR11 ;;
    MULT.RC.VE LR11 LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if not final or not loop.last %} ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.w }} LR0{% endif %}{% if loop.last and not final %} ; INC LR8 {{ m // 8 }} ; BNE LR10 CR0 k_loop{% endif %} ;;
{% else %}
    MULT.RC.VE LR0 LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if not loop.first %} ; INC LR9 1{% endif %}{% if not final or not loop.last %} ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.w }} LR0{% endif %}{% if loop.last and not final %} ; INC LR8 {{ m // 8 }} ; BNE LR10 CR0 k_loop{% endif %} ;;
{% endif %}
{% endfor %}
{% endmacro %}
{% macro bias_add(index, acc) %}
    LD.MULT R0 LR7 {{ cr.b }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ acc }} ; INC LR7 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR11 CR0 ; SET LR14 CR0 ;;
    INC LR11 128 ; INC LR14 {{ groups * 8 }} ;;
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
    SET LR8 LR4 ; SET LR10 {{ cr.ki }} ;;
    {% if not mixed %}DEC LR10 1 ; {% endif %}INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.w }} LR0 ;;
{% if bias %}
    {{ bias_add(0, 'ACC.ADD.FIRST') }}
    {{ bias_add(1, 'ACC.ADD') }}
{% else %}
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
k_loop:
{% if mixed %}
    {{ mixed_group() }}
    {{ mixed_group() }}
    {{ mixed_group() }}
    {{ mixed_group(true, true) }}
{% else %}
{% if k // groups > 1 %}
    {{ tap_group(false) }}
{% endif %}
    {{ tap_group(true) }}
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
    INC LR3 1 ; INC LR5 {{ groups }} ;;
    BNE LR5 LR14 next_pixel ;;
    SET LR5 CR0 ; INC LR4 1 ;;
next_pixel:
    BLT.S LR3 {{ cr.mi }} pixel ;;
    HALT ;;
