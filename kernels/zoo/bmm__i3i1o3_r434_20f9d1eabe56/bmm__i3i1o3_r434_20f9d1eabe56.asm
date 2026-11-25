{# Each B row is a contiguous K chunk for one output column. Keep the
   two query rows' reductions in disjoint accumulator lanes until store. #}
{% macro dot_pass(tag, acc, ds) %}
    SET LR5 LR4 ; SUB LR6 LR8 CR1 ; SET LR7 {{ cr.n }} ; LD.MULT R0 LR3 {{ cr.in0 }} ;;
{{ tag }}_column:
    LD.MULT.CYCLIC LR5 {{ cr.in1 }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.width }}.L {{ cr.qf_in1 }}.L ; {{ acc }} LR6 {{ ds }} ; INC LR6 1 ; DEC LR7 1 ; ADD LR5 LR5 {{ cr.config }}.H ; BNE LR7 CR1 {{ tag }}_column ;;
{% endmacro %}

{% macro query(tag, start) %}
    SET LR8 {{ start }} ; SET LR3 LR1 ; SET LR4 LR2 ;;
    SET LR9 {{ cr.chunks }} ;;
    BEQ LR9 CR1 {{ tag }}_single ;;
    {{ dot_pass(tag ~ '_first', 'AGG.SUM.FIRST', cr.width ~ '.L') }}
    DEC LR9 1 ;;
{{ tag }}_chunk:
    INC LR3 1 ; INC LR4 1 ;;
    BEQ LR9 CR1 {{ tag }}_last ;;
    {{ dot_pass(tag ~ '_add', 'AGG.SUM', cr.width ~ '.L') }}
    DEC LR9 1 ; B {{ tag }}_chunk ;;
{{ tag }}_last:
    {{ dot_pass(tag ~ '_tail', 'AGG.SUM', cr.tail ~ '.L') }}
    B {{ tag }}_done ;;
{{ tag }}_single:
    {{ dot_pass(tag ~ '_only', 'AGG.SUM.FIRST', cr.tail ~ '.L') }}
{{ tag }}_done:
    ADD LR1 LR1 {{ cr.config }}.L ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR10 CR0 ;;
    DEC LR10 1 ;;
group:
    SET LR2 LR11 ; SET LR14 {{ cr.heads }} ;;
head:
    SET LR13 {{ cr.pairs }} ;;
pair:
    {{ query('even', 'CR0') }}
    {{ query('odd', cr.n) }}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.width }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ; INC LR10 1 ; DEC LR13 1 ; BNE LR13 CR1 pair ;;
    ADD LR2 LR2 {{ cr.config }}.H ; SET LR7 {{ cr.n }} ;;
    DEC LR7 1 ; BEQ LR7 CR1 head_done ;;
next_column:
    ADD LR2 LR2 {{ cr.config }}.H ; DEC LR7 1 ; BNE LR7 CR1 next_column ;;
head_done:
    DEC LR14 1 ; BNE LR14 CR1 head ;;
    ADD LR11 LR11 {{ cr.group_pitch }} ; DEC LR15 1 ; BNE LR15 CR1 group ;;
    HALT ;;
