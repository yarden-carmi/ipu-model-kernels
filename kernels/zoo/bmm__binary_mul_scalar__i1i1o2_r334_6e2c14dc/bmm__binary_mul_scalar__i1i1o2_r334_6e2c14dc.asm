{% macro product(first, loop=false) %}
    LD.MULT R0 LR6 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR9 ;;
    MULT.RC.VE LR9 LR3 0 LR9 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR5 LR5 {{ cr.strides }}.L ; ADD LR6 LR6 {{ cr.strides }}.H ; DEC LR7 1 {% if loop %}; BNE LR7 CR1 reduce {% endif %};;
{% endmacro %}
{% macro output(half) %}
    {% set ds = cr.ds_pair ~ '.' ~ half %}
    {% set q = cr.qf_out0 ~ '.L' %}
    SET LR11 CR1 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR9 ;;
    LD.MULT R0 LR9 {{ cr.tmp }} ;;
    MULT.VE LR9 CR1 0 LR9 {{ ds }} {{ q }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR11 ;;
    MULT.VE LR9 {{ cr.fp_hi }} 0 LR9 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.VE LR9 {{ cr.fp_lo }} 0 LR9 {{ ds }} {{ q }} ; ACC.SUB ;;
    MULT.VE LR9 {{ cr.nx_scale }} 0 LR9 {{ ds }} {{ q }} ; ACC.ADD ;;
    LD.MULT R0 LR11 {{ cr.tmp }} ;;
    MULT.VE LR9 {{ cr.fp_hi }} 0 LR9 {{ ds }} {{ q }} ; ACC.ADD ;;
    MULT.VE LR9 {{ cr.fp_lo }} 0 LR9 {{ ds }} {{ q }} ; ACC.SUB ;;
    MULT.VE LR9 {{ cr.nx_scale }} 0 LR9 {{ ds }} {{ q }} ; ACC.ADD ;;
    INC LR11 1 ;;
    LD.MULT R0 LR11 {{ cr.tmp }} ;;
    MULT.VE LR9 {{ cr.tiny_anchor }} 0 LR9 {{ ds }} {{ q }} ; ACC.ADD ;;
    MULT.VE LR9 {{ cr.tiny_anchor }} 0 LR9 {{ ds }} {{ q }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ q }} {{ cr.out0 }} LR0 ;;
    INC LR0 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR9 CR0 ;;
    SET LR11 CR0 ;;
    INC LR11 2 ;;
    MULT.VE LR9 CR0 0 LR9 {{ cr.ds_pair }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE exp2 {{ cr.ds_pair }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR11 ;;
head:
    SET LR2 {{ cr.s0_n }} ; SET LR3 CR0 ; SET LR10 CR0 ;;
column:
    SET LR8 CR0 ;;
tile:
    ADD LR5 LR1 LR8 ; ADD LR6 LR4 LR10 ; SET LR7 LR15 ;;
    {{ product(true) }}
    BEQ LR7 CR0 store ;;
reduce:
    {{ product(false, true) }}
store:
    INC LR8 1 ;;
    BEQ LR8 {{ cr.strides }}.L tail ;;
    {{ output('L') }}
    B tile ;;
tail:
    {{ output('H') }}
    DEC LR2 1 ;;
    BEQ LR2 CR0 next_head ;;
    INC.MODP2 LR3 CR1 7 ;;
    BNE LR3 CR0 column ;;
    INC LR10 1 ; B column ;;
next_head:
    DEC LR8 1 ;;
    SUB LR1 LR5 LR8 ; SUB LR4 LR6 LR10 ; DEC LR14 1 ;;
    BNE LR14 CR0 head ;;
    HALT ;;
