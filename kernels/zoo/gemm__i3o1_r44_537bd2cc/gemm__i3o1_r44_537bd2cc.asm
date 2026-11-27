{% set paired = bias and n <= 64 %}
{% macro load_weight() %}LD.MULT.CYCLIC LR4 {{ cr.w if bias else cr.direct }} LR0 ; INC LR4 1{% endmacro %}
{% macro mac(idx, src, mode='ADD', ds=cr.full) %}MULT.RC.VE {{ idx }} {{ src }} 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}{% endmacro %}
{% macro store(ds) %}ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1{% endmacro %}
{% macro next_input() %}LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR2 LR2 {{ cr.pitch }}{% endmacro %}
{% macro pair(count, final=false) %}
    SET LR10 CR0 ; {{ load_weight() }} ;;
    {{ mac('LR0', 'LR3', ds=cr.tail) }} ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR1 ; SET LR6 LR1 ;;
    {{ mac('LR1', 'LR3', ds=cr.tail) }} {% if count == 2 %}; {{ next_input() }}{% else %}; {{ store(cr.tail) }}{% endif %} ;;
{% if count == 2 %}
    {{ mac('LR10', 'LR3', ds=cr.tail) }} ; INC LR10 {{ n }} ; INC LR6 {{ n }} ;;
    {{ mac('LR6', 'LR3', ds=cr.tail) }} {% if final %}; {{ store(cr.tail) }}{% else %}; {{ next_input() }} ; DEC LR7 1 ; BNE LR7 CR1 pairs{% endif %} ;;
{% endif %}
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR9 CR0 ;;
    DEC LR5 1 ;;
batch:
    SET LR8 LR9 ; SET LR11 CR0 ; SET LR12 {{ cr.in0_d2 }} ;;
row:
    SET LR13 LR15 ;;
pixel:
{% if not bias and k <= 128 %}
    SUB LR2 LR8 {{ cr.pitch }} ; SET LR3 LR11 ; SET LR7 CR0 ;;
    SET LR4 {{ cr.k }} ;;
    DEC LR7 1 ; DEC LR4 1 ; LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR2 LR2 {{ cr.pitch }} ;;
{% if k > 1 %}
gather:
    MULT.EE LR3 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR7 {{ cr.full }}.L ; INC LR7 1 ; LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR2 LR2 {{ cr.pitch }} ; DEC LR4 1 ; BNE LR4 CR1 gather ;;
{% endif %}
    MULT.EE LR3 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR7 {{ cr.full }}.L ; INC LR7 1 ; SET LR6 LR5 ;;
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.out0 }} LR6 ; INC LR6 1 ;;
    LD.MULT R0 LR6 {{ cr.out0 }} ; SET LR4 CR0 ;;
    SET LR6 {{ cr.tiles }} ;;
fast_tile:
    LD.MULT.CYCLIC LR4 {{ cr.direct }} LR0 ;;
    INC LR4 1 ; SET LR7 CR0 ; LD.MULT.CYCLIC LR4 {{ cr.direct }} LR0 ;;
    DEC LR7 1 ;;
{% if k > 1 %}
    MULT.RC.VE LR0 LR7 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR7 1 ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.direct }} LR0 ; SET LR2 {{ cr.k }} ;;
    DEC LR2 2 ;;
{% if k > 2 %}
fast_channel:
    MULT.RC.VE LR0 LR7 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR7 1 ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.direct }} LR0 ; DEC LR2 1 ; BNE LR2 CR1 fast_channel ;;
{% endif %}
    MULT.RC.VE LR0 LR7 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR7 1 ;;
{% else %}
    MULT.RC.VE LR0 LR7 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR7 1 ;;
{% endif %}
    DEC LR6 1 ; INC LR4 1 ; BEQ LR6 CR1 fast_last ;;
    {{ store(cr.full) }} ; B fast_tile ;;
fast_last:
    {{ store(cr.tail) }} ; LD.MULT.CYCLIC LR4 {{ cr.direct }} LR0 ;;
{% else %}
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ; SET LR3 LR11 ;;
    DEC LR4 1 ;;
    {{ load_weight() }} ;;
tile:
{% if paired %}
    SUB LR2 LR8 {{ cr.pitch }} ; SET LR7 {{ cr.pair_groups }} ;;
    {{ mac('LR0', 'CR1', 'ADD.FIRST') }} ; {{ load_weight() }} ;;
    {{ mac('LR0', 'CR1') }} ; {{ next_input() }} ;;
{% if k > 2 %}
pairs:
    {{ pair(2) }}
{% endif %}
    {{ pair((k - 1) % 2 + 1, true) }}
    {{ load_weight() }} ;;
{% else %}
    SUB LR2 LR8 {{ cr.pitch }} ; SET LR7 {{ cr.k }} ;;
{% if bias %}
    {{ mac('LR0', 'CR1', 'ADD.FIRST') }} ; {{ load_weight() }} ;;
    {{ mac('LR0', 'CR1') }} ; {{ load_weight() }} ;;
{% else %}
    {{ load_weight() }} ;;
    {{ next_input() }} ;;
    {{ mac('LR0', 'LR3', 'ADD.FIRST') }} ; {{ load_weight() }} ; DEC LR7 1 ;;
    BEQ LR7 CR0 finished_channel ;;
{% endif %}
channel:
    {{ next_input() }} ;;
{% if bias %}
    {{ mac('LR0', 'LR3') }} ; {{ load_weight() }} ;;
{% endif %}
    {{ mac('LR0', 'LR3') }} ; {{ load_weight() }} ; DEC LR7 1 ; BNE LR7 CR1 channel ;;
finished_channel:
    DEC LR6 1 ; BEQ LR6 CR1 last_tile ;;
    {{ store(cr.full) }} ; B tile ;;
last_tile:
    {{ store(cr.tail) }} ;;
{% endif %}
{% endif %}
    INC LR11 1 ; DEC LR13 1 ; BNE LR13 CR1 pixel ;;
    DEC LR12 1 ; BEQ LR12 CR1 next_batch ;;
    BNE LR11 {{ cr.packed_width }} row ;;
    SET LR11 CR0 ; INC LR8 1 ; B row ;;
next_batch:
    ADD LR9 LR9 {{ cr.batch_pitch }} ; DEC LR14 1 ; BNE LR14 CR1 batch ;;
    HALT ;;
