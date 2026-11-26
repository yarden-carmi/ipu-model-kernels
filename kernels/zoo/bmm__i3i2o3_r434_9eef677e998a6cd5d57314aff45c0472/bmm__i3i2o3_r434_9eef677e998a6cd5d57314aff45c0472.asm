# Keep both operands in their original formats: broadcast one A key and
# accumulate its product with the corresponding contiguous RHS head window.
{% macro rows(tag, crossing) %}
{{ tag }}_row:
    SET LR7 LR2 ; SET LR12 {{ cr.k }} ; LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.VE LR0 CR0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; B {{ tag }}_loaded ;;
{{ tag }}_chunk:
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
{{ tag }}_loaded:
    SET LR8 CR0 ; SET LR9 LR12 ;;
    BLT.S LR12 LR10 {{ tag }}_limit ;;
    SET LR9 LR10 ;;
{{ tag }}_limit:
    INC LR5 1 ;
{% if not crossing %}
    LD.MULT.CYCLIC LR7 {{ cr.vbase }} LR0 ;
{% endif %}
    DEC LR9 1 ;;
{% if not crossing %}
    DEC LR8 1 ; BEQ LR9 CR0 {{ tag }}_last ;;
{% endif %}
{{ tag }}_key:
{% if crossing %}
    LD.MULT.CYCLIC LR7 {{ cr.vbase }} LR0 ;
    ADD LR13 LR7 CR1 ;;
    LD.MULT.CYCLIC LR13 {{ cr.vbase }} LR10 ;;
{% else %}
    # The multiply sees the resident RHS row; the load sees the advanced
    # pointer and supplies the next word. The branch sees the old count.
    MULT.RC.VE LR3 LR8 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR7 {{ cr.vbase }} LR0 ; INC LR8 1 ; ADD LR7 LR7 {{ cr.brows }} ; DEC LR9 1 ; BGT.S LR9 CR1 {{ tag }}_key ;;
{{ tag }}_last:
    # Drain without reading past the last key of the tensor.
{% endif %}
    MULT.RC.VE LR3 LR8 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;
{% if not crossing %}
    ADD LR7 LR7 {{ cr.brows }} ; INC LR8 1 ;
{% endif %}
    ;;
{% if crossing %}
    INC LR8 1 ; ADD LR7 LR7 {{ cr.brows }} ; DEC LR9 1 ; BGT.S LR9 CR0 {{ tag }}_key ;;
{% endif %}
    DEC LR12 128 ;;
    BGT.S LR12 CR0 {{ tag }}_chunk ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; DEC LR11 1 ;;
    INC LR6 1 ; BNE LR11 CR0 {{ tag }}_row ;;
    B next_head ;;
{% endmacro %}
    INC LR10 128 ;;
group:
    SET LR2 LR1 ; SET LR3 {{ cr.lane }} ; SET LR4 {{ cr.counts }}.L ;;
head:
    SET LR11 {{ cr.counts }}.H ; SET LR14 LR3 ;;
    ADD LR14 LR14 LR15 ;;
    BGT.S LR14 LR10 split_row ;;
    {{ rows('single', false) }}
    {{ rows('split', true) }}
next_head:
    DEC LR4 1 ; SET LR3 LR14 ;;
    BEQ LR4 CR0 next_group ;;
    BLT.S LR3 LR10 head ;;
    DEC LR3 128 ; INC LR2 1 ; B head ;;
next_group:
    ADD LR1 LR1 {{ cr.group_rows }} ;;
    BNE LR1 {{ cr.total_rows }} group ;;
    HALT ;;
