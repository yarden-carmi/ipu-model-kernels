{# Weights are contiguous in reduction order for each output tile.
   Two cyclic slots overlap the next weight load with the current MAC. #}
{% macro mac(slot, next_slot) %}
    MULT.RC.VE {{ slot }} LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ cr.w }} {{ next_slot }} ; INC LR3 1 ; INC LR4 1 ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE identity {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
{% endmacro %}
{% macro bias_digit() %}
    LD.MULT R0 LR12 {{ cr.b }} ; INC LR12 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 {{ cr.width }} ; SET LR2 CR0 ;;
    SET LR5 CR0 ; SET LR7 CR0 ;;
row:
    SET LR4 CR0 ; SET LR6 CR0 ;;
{% if bias %}
    SET LR12 CR0 ;;
{% endif %}
    DEC LR4 1 ;;
tile:
    SET LR8 LR2 ; SET LR9 {{ cr.chunks }} ;;
{% if bias %}
    LD.MULT R0 LR12 {{ cr.b }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% for i in range(7) %}
{{ bias_digit() }}
{% endfor %}
    INC LR12 1 ;;
{% else %}
    MULT.VE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
chunk:
    LD.MULT R0 LR8 {{ cr.in0 }} ; SET LR11 {{ cr.planes }} ;;
    INC LR8 1 ;;
plane:
    SET LR3 CR0 ; SET LR10 {{ cr.groups }} ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ; DEC LR3 1 ;;
group:
{% for i in range(15) %}
{{ mac('LR0', 'LR1') }}
{{ mac('LR1', 'LR0') }}
{% endfor %}
{{ mac('LR0', 'LR1') }}
    DEC LR10 1 ;;
    BEQ LR10 CR0 last ;;
{{ mac('LR1', 'LR0') }}
    B group ;;
last:
    MULT.RC.VE LR1 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR3 1 ;;
    DEC LR11 1 ;;
    BNE LR11 CR0 plane ;;
    DEC LR9 1 ;;
    BNE LR9 CR0 chunk ;;
    INC LR6 1 ;;
    BEQ LR6 {{ cr.tiles }} tail ;;
{{ store(cr.full) }}
    INC LR7 1 ; B tile ;;
tail:
{{ store(cr.tail) }}
    INC LR7 1 ; INC LR5 1 ; ADD LR2 LR2 {{ cr.chunks }} ;;
    BLT.S LR5 {{ cr.out0_d0 }} row ;;
    HALT ;;
