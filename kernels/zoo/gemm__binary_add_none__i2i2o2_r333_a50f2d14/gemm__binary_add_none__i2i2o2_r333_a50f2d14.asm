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
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 {{cr.s0_m}} ; INC LR8 128 ;;
    ADD LR10 LR8 LR8 ;;
row:
    SET LR4 CR0 ; SET LR5 CR0 ;;
tile:
    LD.MULT R0 LR5 {{cr.w}} ; SET LR6 LR1 ; SET LR7 CR0 ;;
    MULT.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD.FIRST ; INC LR5 1 ;;
chunk:
    LD.MULT R1 LR6 {{cr.in0}} ; SET LR9 LR8 ;;
    LD.MULT.CYCLIC LR5 {{cr.w}} LR0 ; INC LR6 1 ;;
element:
    MULT.RC.VE LR0 LR9 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD ; INC LR5 1 ;;
    INC LR9 1 ; INC LR7 1 ;;
    BEQ LR7 {{cr.s0_k}} finish ;;
    BEQ LR9 LR10 chunk ;;
    LD.MULT.CYCLIC LR5 {{cr.w}} LR0 ; B element ;;
finish:
    INC LR4 1 ;;
    BEQ LR4 {{cr.blocks}} last ;;
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.full}}.L {{cr.qf_out0}}.L {{cr.out0}} LR2 ;;
    INC LR2 1 ; B tile ;;
last:
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.tail}}.L {{cr.qf_out0}}.L {{cr.out0}} LR2 ;;
    INC LR2 1 ;;
    ADD LR1 LR1 {{cr.chunks}} ; DEC LR3 1 ;;
    BNE LR3 CR0 row ;;
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
{{ integer('LR12', in1_d2) }}
{{ integer('LR3', s0_m * ((s0_n+127)//128)) }}
direct_add:
    SET LR8 CR0 ; INC LR2 1 ;;
    SET LR7 LR6 ; SET LR10 LR2 ;;
    DEC LR10 1 ;;
    BEQ LR10 CR0 tile_base_ready ;;
    SET LR14 {{cr.s0_m}} ;;
{% for i in range(7) %}
    ADD LR14 LR14 LR14 ;;
{% endfor %}
tile_base_loop:
    ADD LR7 LR7 LR14 ; DEC LR10 1 ; BNE LR10 CR1 tile_base_loop ;;
tile_base_ready:
    SET LR11 CR0 ;;
    INC LR11 128 ;;
    BLT.S LR2 {{cr.blocks}} gather_input ;;
    SET LR11 CR0 ;;
    INC LR11 {{(s0_n - 1) % 128 + 1}} ;;
gather_input:
    SET LR9 LR8 ;;
{% for bit in range(24) %}
    ADD LR9 LR9 LR9 ;;
{% endfor %}
    BNE LR8 CR0 divide_element ;;
    SET LR10 LR7 ; SET LR13 CR0 ;;
divide_element:
    BLT.S LR10 LR12 row_address ;;
    SUB LR10 LR10 LR12 ; INC LR13 1 ; B divide_element ;;
row_address:
    SET LR14 LR13 ; SET LR7 LR10 ;;
{% for i in range((in1_d2 + 127) // 128 - 1) %}
    ADD LR14 LR14 LR13 ;;
{% endfor %}
lane_check:
    SET LR15 CR0 ;;
    INC LR15 128 ;;
    BLT.S LR10 LR15 load_input ;;
    DEC LR10 128 ; INC LR14 1 ; B lane_check ;;
load_input:
    LD.MULT R0 LR14 {{cr.in1}} ;;
    MULT.EE LR10 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in1}}.L ; ACC.RESHAPE LRD0 LRD8 7 ;;
    SET LR10 LR7 ;;
    INC LR8 1 ; ADD LR10 LR10 {{cr.s0_m}} ;;
    BLT.S LR8 LR11 gather_input ;;
    LD.MULT R0 LR1 {{cr.out0}} ;;
    MULT.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_out0}}.L ; ACC.ADD ;;
    BEQ LR2 {{cr.blocks}} direct_tail ;;
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.full}}.L {{cr.qf_out0}}.L {{cr.out0}} LR1 ;;
    INC LR1 1 ; B direct_add ;;
direct_tail:
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.tail}}.L {{cr.qf_out0}}.L {{cr.out0}} LR1 ;;
    INC LR1 1 ; SET LR2 CR0 ; INC LR5 1 ;;
    INC LR6 {{in0_d0}} ;;
{{ integer('LR15', in0_d1) }}
    BLT.S LR5 LR15 next_row ;;
    SET LR5 CR0 ; INC LR4 1 ;;
    SET LR6 LR4 ;;
next_row:
    SET LR7 LR6 ;;
    BLT.S LR1 LR3 direct_add ;;
    HALT ;;
