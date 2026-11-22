{# LR1/LR2: first input/output row of this spatial tile. LR5/LR6:
   running input/weight addresses. LR3/LR4: scalar indices for the two digits. #}
{% macro load_weight(dest) %}LD.MULT {{ dest }} LR6 {{ cr.w }} ; INC LR6 1{% endmacro %}
{% macro load_input() %}LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ; ADD LR5 LR5 {{ cr.tiles }}{% endmacro %}
{% macro mac(idx) %}MULT.RC.VE LR0 {{ idx }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% endmacro %}
{% macro broadcast(idx, first=false) %}MULT.EE {{ idx }} CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% endmacro %}
{% macro store(ds) %}ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7{% endmacro %}
{% macro replay(idx, next_idx, last) %}
    {{ mac(idx) }} ; {{ load_input() }} ; INC {{ next_idx }} 2 ; BEQ {{ idx }} LR10 {{ last }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR13 {{ cr.tiles }} ; SET LR14 {{ cr.row_tiles }} ;;
tile:
    SET LR6 CR0 ; SET LR7 LR2 ; SET LR8 {{ cr.n }} ;;
    SUB LR6 LR6 CR1 ;;
feature:
    SET LR5 LR1 ; SET LR9 {{ cr.groups }} ; SET LR3 {{ cr.group_end }} ;;
    {{ load_weight('R0') }} ; SUB LR5 LR5 {{ cr.tiles }} ; SET LR4 {{ cr.width }} ;;
    {{ load_weight('R1') }} ;; 
    INC LR3 1 ; SET LR12 CR0 ;;
    ADD LR4 LR4 LR3 ;;
    {{ broadcast('LR3', true) }} ;;
    {{ broadcast('LR4') }} ; B group_ready ;;
group:
    {{ load_weight('R0') }} ;;
    {{ load_weight('R1') }} ;;
group_ready:
    DEC LR9 1 ; SET LR3 CR0 ; SET LR4 {{ cr.group_end }} ;;
    INC LR4 1 ;;
    SET LR10 {{ cr.group_end }} ; BNE LR9 CR0 preload ;;
    SET LR10 {{ cr.tail_end }} ;;
preload:
    SET LR11 LR5 ; SET LR15 CR0 ;;
    {{ load_input() }} ;;
reduce:
    {{ mac('LR3') }} ; INC LR4 1 ; BEQ LR3 LR10 last_digit ;;
    {{ mac('LR4') }} ; {{ load_input() }} ; INC LR3 1 ; B reduce ;;
last_digit:
    {{ mac('LR4') }} ; {{ load_weight('R0') }} ; SET LR5 LR11 ;;
    DEC LR10 1 ;;
low_plane:
    BEQ LR12 CR0 bias_low ;;
    B low_init ;;
bias_low:
    SET LR3 {{ cr.group_end }} ;;
    INC LR3 1 ;;
    {{ broadcast('LR3') }} ;;
low_init:
    SET LR3 CR0 ; SET LR4 CR0 ; {{ load_input() }} ;;
    DEC LR4 1 ; BLT.S LR10 CR0 low_last_even ;;
low_reduce:
    {{ replay('LR3', 'LR4', 'low_last_odd') }}
    {{ replay('LR4', 'LR3', 'low_last_even') }}
    B low_reduce ;;
low_last_odd:
    {{ mac('LR4') }} ; B low_done ;;
low_last_even:
    {{ mac('LR3') }} ;;
low_done:
    BNE LR15 CR0 group_done ;;
    {{ load_weight('R0') }} ; SET LR5 LR11 ; SET LR15 CR1 ; B low_plane ;;
group_done:
    SET LR12 CR1 ;;
    BNE LR9 CR0 group ;;
    BEQ LR13 CR1 tail_store ;;
    {{ store(cr.full) }} ; B stored ;;
tail_store:
    {{ store(cr.tail) }} ;;
stored:
    ADD LR7 LR7 {{ cr.tiles }} ; DEC LR8 1 ;;
    BNE LR8 CR0 feature ;;
    DEC LR14 1 ; DEC LR13 1 ;;
    BEQ LR14 CR0 done ;;
    BEQ LR13 CR0 batch ;;
    INC LR1 1 ; INC LR2 1 ; B tile ;;
batch:
    ADD LR1 LR5 CR1 ; ADD LR2 LR7 CR1 ;;
    SUB LR2 LR2 {{ cr.tiles }} ; SET LR13 {{ cr.tiles }} ; B tile ;;
done:
    HALT ;;
