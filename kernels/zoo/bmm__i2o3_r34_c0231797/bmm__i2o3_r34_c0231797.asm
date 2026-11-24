{# R0 holds the query throughout its output row. Rotate the full input
   row when needed so the row quantizer sees the same set of values. #}
{% macro write(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ; INC LR0 1 ;;
{% endmacro %}
{% macro dot(prefetch) %}
    MULT.RC.VV LR5 R0 0 LR14 {{ cr.ds_full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR9 {{ cr.ds_full }}.H ; INC LR9 1 {% if prefetch %}; ADD LR8 LR8 {{ cr.stride }} ; LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR14 ; DEC LR7 1 ; BNE LR7 CR1 dot{% endif %} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR14 CR0 ;;
    DEC LR0 1 ; SET LR15 CR0 ;;
    INC LR15 128 ;;
group:
    SET LR2 LR1 ; SET LR3 CR0 ; ADD LR4 LR1 {{ cr.key_rows }} ;;
    SET LR5 {{ cr.head_info }}.H ; SET LR12 {{ cr.head_info }}.L ;;
head:
    SET LR6 LR2 ; SET LR11 {{ cr.sizes }}.L ;;
query:
    BEQ LR3 CR0 aligned ;;
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR14 ;;
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR15 ;;
    MULT.RC.VE LR3 CR1 0 LR14 {{ cr.ds_full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.ds_full }}.L {{ cr.qf_in0 }}.L {{ cr.rotated }} LR14 ;;
    LD.MULT R0 LR14 {{ cr.rotated }} ; B start_row ;;
aligned:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
start_row:
    SET LR8 LR4 ; SET LR10 {{ cr.sizes }}.H ;;
tile:
    SET LR9 CR0 ; SET LR7 LR10 ; BLE.S LR10 LR15 load_key ;;
    SET LR7 LR15 ;;
load_key:
    LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR14 ; DEC LR9 1 ; DEC LR7 1 ; BEQ LR7 CR1 last_dot ;;
dot:
    {{ dot(true) }}
last_dot:
    {{ dot(false) }}
store:
    BLE.S LR10 LR15 tail ;;
    {{ write(cr.ds_full ~ '.L') }}
    DEC LR10 128 ; ADD LR8 LR8 {{ cr.stride }} ; B tile ;;
tail:
    {{ write(cr.ds_tail ~ '.L') }}
    ADD LR6 LR6 {{ cr.stride }} ; DEC LR11 1 ; BNE LR11 CR1 query ;;
    ADD LR3 LR3 {{ cr.k }} ; ADD LR5 LR5 {{ cr.k }} ; DEC LR12 1 ; BEQ LR12 CR1 next_group ;;
    BLT.S LR3 LR15 key_wrap ;;
    DEC LR3 128 ; INC LR2 1 ;;
key_wrap:
    BLT.S LR5 LR15 head ;;
    DEC LR5 128 ; INC LR4 1 ; B head ;;
next_group:
    ADD LR1 LR1 {{ cr.group_rows }} ; DEC LR13 1 ; BNE LR13 CR1 group ;;
    HALT ;;
