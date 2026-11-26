{% macro add_c() %}
    ADD LR11 LR11 LR8 ;;
{% endmacro %}
{% macro store(mask) %}
    LD.MULT R0 LR4 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR14 CR0 ; SET LR15 CR0 ;;
row:
    SET LR6 LR5 ; SET LR13 CR0 ;;
    SET LR8 LR6 ; SET LR9 CR0 ;;
divide_c:
    BLT.S LR8 {{ cr.in0_d2 }} got_c ;;
    SUB LR8 LR8 {{ cr.in0_d2 }} ; INC LR9 1 ; B divide_c ;;
got_c:
    SET LR10 CR0 ;;
divide_b:
    BLT.S LR9 {{ cr.in0_d1 }} got_b ;;
    SUB LR9 LR9 {{ cr.in0_d1 }} ; INC LR10 1 ; B divide_b ;;
got_b:
    NOP ;;
chunk:
    SET LR2 CR0 ; SET LR3 CR0 ;;
element:
    SET LR11 CR0 ; SET LR12 LR9 ;;
{% for i in range(2 * ((in0_d1 + 63) // 64)) %}
    {{ add_c() }}
{% endfor %}
divide_pack:
    BLT.S LR12 {{ cr.sixtyfour }} got_pack ;;
    SUB LR12 LR12 {{ cr.sixtyfour }} ; INC LR11 2 ; B divide_pack ;;
got_pack:
    ADD LR12 LR12 LR12 ;;
    ADD LR12 LR12 LR12 ;;
    ADD LR7 LR12 LR10 ;;
    BLT.S LR7 {{ cr.onetwentyeight }} got_lane ;;
    SUB LR7 LR7 {{ cr.onetwentyeight }} ; INC LR11 1 ;;
got_lane:
    LD.MULT R0 LR11 {{ cr.in0 }} ;;
    MULT.EE LR7 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
    ADDBI LRD2 1 ; ADD LR8 LR8 {{ cr.stride }} ; INC LR13 1 ;;
advance:
    BLT.S LR8 {{ cr.in0_d2 }} advanced ;;
    SUB LR8 LR8 {{ cr.in0_d2 }} ; INC LR9 1 ;;
    BLT.S LR9 {{ cr.in0_d1 }} advance ;;
    SET LR9 CR0 ; INC LR10 1 ; B advance ;;
advanced:
    BEQ LR13 {{ cr.in0_d2 }} last_chunk ;;
    BLT.S LR2 CR0 full_chunk ;;
    B element ;;
full_chunk:
    {{ store(cr.full) }}
    B chunk ;;
last_chunk:
    {{ store(cr.tail) }}
    BEQ LR4 {{ cr.rows }} done ;;
    INC LR14 1 ; INC LR5 4 ;;
    BNE LR14 {{ cr.in0_d1 }} row ;;
    SET LR14 CR0 ; INC LR15 1 ;;
    SET LR5 LR15 ; B row ;;
done:
    HALT ;;
