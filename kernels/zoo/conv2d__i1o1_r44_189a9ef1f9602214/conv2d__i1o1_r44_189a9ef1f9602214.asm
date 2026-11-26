{% macro shift(r,n) %}
{% for tile in range(0,n|abs,8160) %}
{% for k in range(tile,[tile+8160,n|abs]|min,255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ [255,(n|abs)-k]|min }} ;;
{% endfor %}
{% endfor %}
{% endmacro %}

{% macro channel(i) %}
{% set cur = 'LR15' if i % 2 == 0 else 'LR12' %}
{% set nxt = 'LR12' if i % 2 == 0 else 'LR15' %}
 MULT.RC.VE {{ cur }} LR11 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR4 1 ; INC LR11 1 {% if i < 15 %}; LD.MULT.CYCLIC LR4 {{ cr.weights }} {{ nxt }}{% else %}; BNE LR10 CR0 channels{% endif %} ;;
{% endmacro %}

{% macro store(mask) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
{% endmacro %}

{% if dot %}
 {{ shift('LR12', cout - 3) }}
{% endif %}
 {{ shift('LR0', -padding) }}
 {{ shift('LR1', -padding * (in0_d3 + 1)) }}
 oy:
 SET LR2 CR0 ;;
 {{ shift('LR2', -padding) }}
 ox:
 SET LR3 CR0 ; SET LR4 CR0 ;;
 block:
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ;;
 MULT.RC.VE LR15 {{ 'CR1' if bias else 'CR0' }} 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR5 CR0 ; SET LR14 LR1 ; INC LR4 1 ;;
 ky:
 ADD LR7 LR0 LR5 ; SET LR6 CR0 ;;
 BLT.S LR7 CR0 skip_row ;;
 BGE.S LR7 {{ cr.input_hw }}.L skip_row ;;
 kx:
 ADD LR8 LR2 LR6 ;;
 BLT.S LR8 CR0 skip ;;
 BGE.S LR8 {{ cr.input_hw }}.H skip ;;
 ADD LR9 LR14 LR6 ;;
{% if chunks > 1 %}
 SET LR7 LR9 ;;
 {% for i in range(chunks - 1) %} ADD LR9 LR9 LR7 ;; {% endfor %}
{% endif %}
 SET LR7 CR0 ;;
 INC LR7 {{ chunks }} ;;
 chunk:
{% if dot %}
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR15 ;;
 LD.MULT R0 LR4 {{ cr.weights }} ; SET LR11 {{ cr.full }}.H ;;
 {% if cout > 1 %}
 dot_lane:
 MULT.RC.VV LR15 R0 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.full }}.L ; INC LR11 1 ; LD.MULT R0 LR4 {{ cr.weights }} ; INC LR4 1 ; BLT.S LR11 LR12 dot_lane ;;
 {% endif %}
 MULT.RC.VV LR15 R0 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.full }}.L ; INC LR4 1 ; INC LR11 1 ;;
{% else %}
 SET LR10 {{ cr.panel_tail }}.H ; BEQ LR7 CR1 chunk_load ;;
 SET LR10 CR0 ;;
 INC LR10 128 ;;
 chunk_load:
 LD.MULT R0 LR9 {{ cr.in0 }} ; SET LR11 {{ cr.full }}.H ;;
 channels:
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ; DEC LR10 16 ;;
 {% for i in range(16) %}{{ channel(i) }}{% endfor %}
{% endif %}
 DEC LR7 1 ; INC LR9 1 ; BNE LR7 CR1 chunk ;;
 B next ;;
 skip:
 ADD LR4 LR4 {{ cr.panel_tail }}.L ;;
 next:
 INC LR6 1 ; BLT.S LR6 {{ cr.kernel_last }}.L kx ;;
 B next_row ;;
 skip_row:
 {% for x in range(kw) %} ADD LR4 LR4 {{ cr.panel_tail }}.L ;; {% endfor %}
 next_row:
 INC LR5 1 ; ADD LR14 LR14 {{ cr.input_hw }}.H ; BLT.S LR5 {{ cr.kernel_last }}.H ky ;;
 INC LR3 1 ;;
 BLT.S LR3 {{ cr.blocks }} fullstore ;;
 {{ store(cr.tail ~ '.L') }}
 INC LR13 1 ; B advance ;;
 fullstore:
 {{ store(cr.full ~ '.L') }}
 INC LR13 1 ; B block ;;
 advance:
 INC LR1 {{ stride }} ; INC LR2 {{ stride }} ;;
 BLT.S LR2 {{ cr.xend }} ox ;;
 ADD LR1 LR1 {{ cr.row_delta }} ; INC LR0 {{ stride }} ;;
 BLT.S LR0 {{ cr.yend }} oy ;;
 HALT ;;
