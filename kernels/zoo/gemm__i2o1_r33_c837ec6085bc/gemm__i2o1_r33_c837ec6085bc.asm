{% set chunks = (k + 127) // 128 %}
{% set nr = (2 * out0_d1 + 127) // 128 %}
{% macro addimm(reg, val) %}
{% for i in range(0, val, 255) %}INC {{reg}} {{ [255, val-i]|min }} ;;{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR7 {{ cr.out0_d0 }} ; DEC LR5 1 ;;
batch:
    SET LR8 {{ cr.pairs }} ; SET LR4 CR0 ;;
pair:
{% for r in range(nr) %}
    SET LR2 LR4 ;; {{ addimm('LR2',r) }}
    LD.MULT.CYCLIC LR2 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% for ch in range(2) %}
{% set start = [r * 128, ch * out0_d1]|max %}
{% set end = [(r + 1) * 128, (ch + 1) * out0_d1]|min %}
{% if end > start %}
    SET LR9 LR6 ;; {{ addimm('LR9',(start - ch * out0_d1) * chunks) }}
    SET LR10 CR0 ;; {{ addimm('LR10',start - r * 128) }}
    SET LR11 CR0 ;; {{ addimm('LR11',end - start) }}
sample_{{r}}_{{ch}}:
    SET LR2 LR9 ; SET LR3 LR4 ;; {{ addimm('LR3',nr + ch * chunks) }}
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR3 {{ cr.w }} LR0 ; INC LR2 1 ;;
{% for c in range(chunks) %}
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR10 {{ cr.full }}.L {% if not loop.last %}; LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR3 1{% endif %} ;;
{% if not loop.last %}
    LD.MULT.CYCLIC LR3 {{ cr.w }} LR0 ; INC LR2 1 ;;
{% endif %}
{% endfor %}
    ADD LR9 LR9 {{ cr.chunks }} ; INC LR10 1 ; DEC LR11 1 ; BNE LR11 CR1 sample_{{r}}_{{ch}} ;;
{% endif %}
{% endfor %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail if r == nr - 1 else cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endfor %}
    ADD LR4 LR4 {{ cr.pairstride }} ; DEC LR8 1 ; BNE LR8 CR1 pair ;;
    ADD LR6 LR6 {{ cr.batchstride }} ; DEC LR7 1 ; BNE LR7 CR1 batch ;;
    HALT ;;
