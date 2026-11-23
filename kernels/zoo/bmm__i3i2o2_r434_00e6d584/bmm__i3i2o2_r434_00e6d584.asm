{# Each column's K lanes are loaded once and reused across M queries. #}
    INC LR12 128 ;;
group:
    SET LR3 {{ cr.mh }}.H ; SET LR10 {{ cr.bstart }} ;;
head:
    SET LR5 {{ cr.n }} ; SET LR2 LR9 ;;
column:
    SET LR7 LR2 ; SET LR4 LR10 ;;
normalize:
    BLT.S LR4 LR12 load ;;
    DEC LR4 128 ; INC LR7 1 ; B normalize ;;
load:
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR14 ; ADD LR8 LR4 {{ cr.kd }}.H ;;
    BLE.S LR8 LR12 query ;;
    INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR12 ;;
query:
    SET LR6 {{ cr.mh }}.L ; SET LR11 LR1 ;;
tile:
    SET LR7 CR0 ; SET LR8 LR6 ;;
    BLE.S LR8 LR12 width_ready ;;
    SET LR8 LR12 ;;
width_ready:
    SUB LR6 LR6 LR8 ; DEC LR7 1 ; DEC LR8 1 ; LD.MULT R0 LR11 {{ cr.in0 }} ; BEQ LR8 CR1 last ;;
{% macro product() %}
    MULT.RC.VV LR4 R0 0 LR14 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR7 {{ cr.kd }}.L ; INC LR7 1 ; ADD LR11 LR11 {{ cr.astride }}
{%- endmacro %}
rows:
    {{ product() }} ; DEC LR8 1 ; LD.MULT R0 LR11 {{ cr.in0 }} ; BGT.S LR8 CR1 rows ;;
last:
    {{ product() }} ; BNE LR6 CR0 full ;;
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ;;
{% endmacro %}
    {{ store('H') }}
    DEC LR5 1 ;;
    BEQ LR5 CR0 head_done ;;
    ADD LR2 LR2 {{ cr.abc }}.H ; B column ;;
head_done:
    ADD LR1 LR1 {{ cr.abc }}.L ; ADD LR10 LR10 {{ cr.kd }}.H ; DEC LR3 1 ; BGT.S LR3 CR1 head ;;
    ADD LR1 LR1 LR13 ; ADD LR9 LR9 {{ cr.bstride }} ; DEC LR15 1 ; BGT.S LR15 CR1 group ;;
    HALT ;;
full:
    {{ store('L') }}
    B tile ;;
