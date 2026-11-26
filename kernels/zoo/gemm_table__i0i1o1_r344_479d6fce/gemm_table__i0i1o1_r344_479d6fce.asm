{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% set full_copy = n // 128 %}
{% set groups = in0_d0 %}
{% set pack = [in0_d1, 128 // groups] | min %}
{% set chunks = (in0_d1 + pack - 1) // pack %}
{% set dx = m // in0_d2 %}
{% set dy = m % in0_d2 %}
{% set blocks = (out0_d1 + 127) // 128 - full_copy %}
{% set fast = groups == 4 and dy > 0 and dy <= 255 and dx % pack * groups >= groups - 1 and dx % pack * groups - (groups - 1) <= 255 %}

{% macro store(fn) %}
    ACTIVATE.QUANTIZE {{ fn }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}
{% macro copy_add(acc) %}
    LD.MULT R0 LR2 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; {{ acc }} ; INC LR2 1 ;;
{% endmacro %}
{% macro bias_add(acc) %}
    LD.MULT R0 LR7 {{ cr.b }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ acc }} ; INC LR7 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR11 CR0 ; SET LR14 CR0 ;;
    INC LR11 128 ;;
{% for segment in range(5) %}
    LD.LUT {{ segment }} {{ cr.lut }} LR0 ;;
    INC LR0 1 ;;
{% endfor %}
    SET LR0 CR0 ;;
pixel:
{% if full_copy %}
    SET LR13 CR0 ;;
    INC LR13 {{ full_copy }} ;;
copy_block:
    {{ copy_add('ACC.ADD.FIRST') }}
    {{ store('identity') }}
    INC LR1 1 ; DEC LR13 1 ; BNE LR13 CR1 copy_block ;;
{% endif %}
    SET LR6 CR0 ; SET LR7 CR0 ; SET LR13 CR0 ;;
    INC LR13 {{ blocks }} ; DEC LR6 1 ;;
gemm_block:
    SET LR8 LR4 ; SET LR9 LR5 ; SET LR15 LR14 ;;
    SET LR10 CR0 ; SET LR12 CR0 ;;
    INC LR10 {{ k // groups }} ; INC LR12 {{ pack * groups }} ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.w }} LR0 ;;
{% if bias %}
    {{ bias_add('ACC.ADD.FIRST') }}
    {{ bias_add('ACC.ADD') }}
{% else %}
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}

# LR8 is the packed row, LR9 the lane of the first slab and LR15 the
# inner coordinate of the flat view index within a slab. Taps at equal
# indices in different slabs share the row and occupy consecutive lanes.
tap:
    LD.MULT R0 LR8 {{ cr.in0 }} ; DEC LR10 1 ;;
{% for g in range(groups) %}
    MULT.RC.VE LR0 LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR6 1{% if not loop.first %} ; INC LR9 1{% endif %} ; LD.MULT.CYCLIC LR6 {{ cr.w }} LR11 ;;
    MULT.RC.VE LR11 LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if not loop.last %} ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.w }} LR0{% else %} ; BEQ LR10 CR0 taps_done{% endif %}{% if fast and loop.index == 1 %} ; INC LR15 {{ dy }}{% endif %}{% if fast and loop.index == 2 and dx // pack + dy * chunks %} ; ADD LR8 LR8 {{ cr.pixel_step }}.H{% endif %} ;;
{% endfor %}
    INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.w }} LR0{% if fast and dx % pack * groups - (groups - 1) %} ; INC LR9 {{ dx % pack * groups - (groups - 1) }}{% endif %} ;;
{% if groups > 1 and not fast %}
    DEC LR9 {{ groups - 1 }} ;;
{% endif %}
{% if dx // pack + dy * chunks and not fast %}
    ADD LR8 LR8 {{ cr.pixel_step }}.H ;;
{% endif %}
{% if dx % pack and not fast %}
    INC LR9 {{ (dx % pack) * groups }} ;;
{% endif %}
{% if dy %}
    {% for i in range(0 if fast else (dy + 254) // 255) %}
    INC LR15 {{ [255, dy - i * 255] | min }} ;;
    {% endfor %}
    BLT.S LR15 {{ cr.row_period }}.L tap_lane ;;
    SUB LR15 LR15 {{ cr.row_period }}.L ; SUB LR8 LR8 {{ cr.row_period }}.H ; INC LR9 {{ groups }} ;;
tap_lane:
{% endif %}
    BLT.S LR9 LR12 tap ;;
    SUB LR9 LR9 LR12 ; INC LR8 1 ; BEQ LR0 CR0 tap ;;

taps_done:
{% if n % 128 %}
    SET LR12 CR0 ;;
    INC LR12 {{ blocks }} ;;
    BNE LR13 LR12 direct ;;
    {{ store(act) }}
    {{ copy_add('ACC.ADD.FIRST') }}
    ACTIVATE.QUANTIZE identity {{ cr.copy_tail }}.L {{ cr.qf_in1 }}.L {{ cr.copy }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.copy }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
    LD.MULT R0 LR1 {{ cr.out0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.ADD ;;
    {{ store('identity') }}
    BEQ LR0 CR0 block_done ;;
direct:
{% endif %}
    {{ store(act) }}
block_done:
    INC LR1 1 ; DEC LR13 1 ; BNE LR13 CR1 gemm_block ;;

    INC LR3 1 ; INC LR14 1 ; INC LR4 {{ chunks }} ;;
    BGE.S LR3 {{ cr.pixel_step }}.L done ;;
    BLT.S LR14 {{ cr.row_period }}.L pixel ;;
    SET LR14 CR0 ; SUB LR4 LR4 {{ cr.row_period }}.H ; INC LR5 {{ groups }} ;;
    # LR12 can have been reused by the copy path.
    SET LR12 CR0 ;;
    INC LR12 {{ pack * groups }} ;;
    BLT.S LR5 LR12 pixel ;;
    SET LR5 CR0 ; INC LR4 1 ; BEQ LR0 CR0 pixel ;;
done:
    HALT ;;
