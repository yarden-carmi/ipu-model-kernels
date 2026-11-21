    INC LR13 128 ; SET LR14 CR0 ;;
group:
    SET LR4 CR0 ; SET LR3 CR0 ;;
    {% for i in range(4) %}
    ADD LR3 LR3 {{ cr.k }} ;;
    {% endfor %}
normalize:
    BLT.S LR3 LR13 head ;;
    SUB LR3 LR3 LR13 ; INC LR2 1 ;;
    B normalize ;;
head:
    SET LR5 LR1 ; SET LR6 CR0 ;;
row:
    LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR7 LR2 ; SET LR8 {{ cr.n }} ;;
tile:
    SET LR12 LR8 ; SET LR9 LR7 ; SET LR11 CR0 ;;
    BLE.S LR12 LR13 width_ready ;;
    SET LR12 LR13 ;;
width_ready:
    ADD LR10 LR3 {{ cr.k }} ;;
    BGT.S LR10 LR13 split ;;
{% macro dots(tag, split) %}
{{ tag }}:
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR14 ;;
{% if split %}
    SET LR10 LR9 ;;
    INC LR10 1 ;;
    LD.MULT.CYCLIC LR10 {{ cr.in1 }} LR13 ;;
{% endif %}
    MULT.RC.VV LR3 R0 0 LR14 {{ cr.dsk }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR11 {{ cr.dsk }}.L ; ADD LR9 LR9 {{ cr.brows }} ;;
    INC LR11 1 ;;
    BLT.S LR11 LR12 {{ tag }} ;;
{% endmacro %}
    {{ dots('single', false) }}
    B store ;;
    {{ dots('split', true) }}
store:
    SUB LR8 LR8 LR12 ;;
    BNE LR8 CR0 store_full ;;
{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.dsout }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ;;
{% endmacro %}
    {{ output('H') }}
    ADD LR5 LR5 {{ cr.in0_d1 }} ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.m }} row ;;
    DEC LR15 1 ; INC LR4 1 ;;
    BEQ LR15 CR0 done ;;
    BGE.S LR4 {{ cr.in0_d1 }} next_group ;;
    INC LR1 1 ; ADD LR3 LR3 {{ cr.k }} ;;
    B normalize ;;
next_group:
    SUB LR1 LR5 LR4 ; ADD LR2 LR2 {{ cr.group_gap }} ;;
    INC LR1 1 ;;
    B group ;;
store_full:
    {{ output('L') }}
    SET LR7 LR9 ; B tile ;;
done:
    HALT ;;
