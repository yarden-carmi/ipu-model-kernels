    INC LR9 128 ;;
head:
    SET LR5 CR0 ;;
row:
    SET LR6 CR0 ; SET LR7 LR2 ;;
tile:
    ADD LR8 LR1 {{ cr.ka }}.H ; SET LR11 LR7 ; SET LR13 {{ cr.ka }}.L ;;
    DEC LR8 1 ;;
    MULT.VE LR15 CR0 0 LR15 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR14 {{ cr.n }} ;;
    SUB LR14 LR14 LR6 ;;
    BLE.S LR14 LR9 width_ready ;;
    SET LR14 LR9 ;;
width_ready:
    ADD LR14 LR14 LR3 ;;
    BGT.S LR14 LR9 split_chunk ;;

{# Stream the key rows; the second slot is only needed across a row boundary. #}
{% macro reduce(tag, split) %}
{{ tag }}_chunk:
    LD.MULT R0 LR8 {{ cr.in0 }} ; SET LR12 LR13 ;;
    SUB LR14 LR15 CR1 ;;
    INC.MODP2 LR12 LR14 7 ;;
{{ tag }}_inner:
    LD.MULT.CYCLIC LR11 {{ cr.in1 }} LR15 ;;
{% if split %}
    LD.MULT.CYCLIC LR11 {{ cr.in1_next }} LR9 ;;
{% endif %}
    MULT.RC.VE LR3 LR12 0 LR15 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    DEC LR12 1 ; SUB LR11 LR11 {{ cr.stride_lane }}.L ; DEC LR13 1 ;;
    BGE.S LR12 CR0 {{ tag }}_inner ;;
    DEC LR8 1 ;;
    BNE LR13 CR0 {{ tag }}_chunk ;;
    B store ;;
{% endmacro %}
    {{ reduce('single', false) }}
    {{ reduce('split', true) }}

store:
    INC LR6 128 ;;
    BLT.S LR6 {{ cr.n }} store_full ;;
{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
{% endmacro %}
    {{ output('H') }}
    B stored ;;
store_full:
    {{ output('L') }}
stored:
    INC LR0 1 ; INC LR7 1 ;;
    BLT.S LR6 {{ cr.n }} tile ;;
    ADD LR1 LR1 {{ cr.ka }}.H ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.mh }}.L row ;;
    INC LR4 1 ; INC LR10 1 ; ADD LR3 LR3 {{ cr.n }} ;;
    BGE.S LR4 {{ cr.b }} done ;;
normalize:
    BLT.S LR3 LR9 next_head ;;
    DEC LR3 128 ; INC LR2 1 ;;
    B normalize ;;
next_head:
    BLT.S LR10 {{ cr.mh }}.H head ;;
    ADD LR2 LR2 {{ cr.group_jump }} ; SET LR3 {{ cr.stride_lane }}.H ; SET LR10 CR0 ;;
    B head ;;
done:
    HALT ;;
