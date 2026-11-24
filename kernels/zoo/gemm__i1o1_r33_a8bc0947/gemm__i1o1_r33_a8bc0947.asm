# The two halves of each result row share one accumulator. Slot 0 is
# zero, and slot 1 holds the current input column. Reading across their
# boundary shifts the input for the second output channel without a store.
{% macro product(slot, scalar, epilogue='') %}
    MULT.RC.VE {{ slot }} {{ scalar }} 0 LR0 {{ cr.row_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ epilogue }} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    INC LR2 128 ;;
clean_input:
    LD.MULT R0 LR3 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.row_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.clean_ds }}.L {{ cr.qf_in0 }}.L {{ cr.clean }} LR3 ;;
    INC LR3 1 ;;
    BLT.S LR3 LR14 clean_input ;;
    SET LR3 CR0 ;;
    SET LR4 CR0 ; SET LR5 {{ cr.in0_d0 }} ;;
    SET LR1 {{ cr.shifted }} ;;
batch:
    SET LR6 CR0 ; SET LR7 CR0 ; SET LR15 CR0 ;;
    DEC LR7 1 ;;
pair:
    SET LR8 LR3 ; SET LR9 {{ cr.chunks }} ;;
    DEC LR8 1 ;;
{% if bias %}
{% for digit in range(3) %}
    LD.MULT R0 LR15 {{ cr.b }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.row_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if digit == 0 %}.FIRST{% endif %} ; INC LR15 1 ;;
{% endfor %}
{% else %}
    MULT.VE LR0 CR0 0 LR0 {{ cr.row_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
chunk:
    SET LR13 CR0 ; SET LR14 LR8 ; DEC LR9 1 ;;
    INC LR13 3 ;;
plane:
    LD.MULT R0 LR7 {{ cr.w }} ; INC LR7 1 ; SET LR8 LR14 ; DEC LR13 1 ;;
    LD.MULT R1 LR7 {{ cr.w }} ; INC LR7 1 ; SET LR10 CR0 ; SET LR11 LR2 ;;
    DEC LR11 1 ; BNE LR9 CR0 preload ;;
    SET LR11 {{ cr.last_tap }} ;;
preload:
    LD.MULT.CYCLIC LR8 {{ cr.clean }} LR2 ; ADD LR12 LR10 LR2 ; INC LR8 1 ;;
    BEQ LR10 LR11 last ;;
tap:
    {{ product('LR2', 'LR10') }}
    {{ product('LR1', 'LR12', ' ; LD.MULT.CYCLIC LR8 ' ~ cr.clean ~ ' LR2 ; INC LR8 1 ; INC LR10 1') }}
    INC LR12 1 ; BLT.S LR10 LR11 tap ;;
last:
    {{ product('LR2', 'LR10') }}
    {{ product('LR1', 'LR12', ' ; BNE LR13 CR0 plane') }}
    BNE LR9 CR0 chunk ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.row_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.pairs }} pair ;;
    ADD LR3 LR8 CR1 ; DEC LR5 1 ;;
    BNE LR5 CR0 batch ;;
    HALT ;;
