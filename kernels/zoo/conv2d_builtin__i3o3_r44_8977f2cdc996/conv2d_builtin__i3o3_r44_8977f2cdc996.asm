{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set chunks = (in0_d3 + 127) // 128 %}
{% set candidate = [1, 128 // in0_d3]|max %}
{% set pack = candidate if in0_d2 % candidate == 0 else 1 %}
{% set ntaps = (15 if pack > 1 or chunks == 2 else 9) * cin %}

{# The cyclic window is [previous, current, next]. Missing rows are zero. #}
{% macro neighbors(tag) %}
 LD.MULT.CYCLIC LR0 {{ cr.masks }} LR0 ; SET LR6 LR9 ; SET LR7 LR9 ; SET LR8 LR5 ;;
 LD.MULT.CYCLIC LR0 {{ cr.masks }} LR12 ; DEC LR6 1 ; INC LR7 1 ;;
 {% if pack == 1 %}
 {% if tag == 'top' %}DEC LR8 {{ chunks }} ;;{% elif tag == 'bottom' %}INC LR8 {{ chunks }} ;;{% endif %}
 {% endif %}
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR11 ; BEQ LR8 CR0 no_prev_{{ tag }} ;;
 LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
 no_prev_{{ tag }}:
 INC LR8 1 ;;
 BGE.S LR8 {{ cr.tiles }} no_next_{{ tag }} ;;
 LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR12 ;;
 no_next_{{ tag }}:
{% endmacro %}

{% macro sample(delta) %}
 SET LR15 LR11 ; LD.MULT R0 LR10 {{ cr.masks }} ;;
 {% if delta < 0 %}DEC LR15 {{ -delta }} ;;{% elif delta > 0 %}INC LR15 {{ delta }} ;;{% endif %}
 MULT.RC.VV LR15 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.patches }} LR1 ; INC LR10 1 ;;
 INC LR1 1 ;;
{% endmacro %}

{% macro patches(ky) %}
 {% if pack == 1 %}
 SET LR9 LR4 ; SET LR8 LR5 ;;
 {% if ky == -1 %}DEC LR9 {{ chunks }} ; DEC LR8 {{ chunks }} ;;{% elif ky == 1 %}INC LR9 {{ chunks }} ; INC LR8 {{ chunks }} ;;{% endif %}
 BLT.S LR8 CR0 zero_{{ ky+1 }} ;;
 BGE.S LR8 {{ cr.tiles }} zero_{{ ky+1 }} ;;
 {{ neighbors(['top','middle','bottom'][ky+1]) }}
 B patch_{{ ky+1 }} ;;
 zero_{{ ky+1 }}:
 LD.MULT.CYCLIC LR0 {{ cr.masks }} LR11 ;;
 LD.MULT.CYCLIC LR0 {{ cr.masks }} LR0 ;;
 LD.MULT.CYCLIC LR0 {{ cr.masks }} LR12 ;;
 patch_{{ ky+1 }}:
 {% endif %}
 {% for kx in [-1,0,1] %}
 {% set delta = kx + (ky * in0_d3 if pack > 1 else 0) %}
 {{ sample(delta) }}
 {% if (pack > 1 and ky != 0) or (chunks == 2 and kx != 0) %}
 {{ sample(delta + (ky * (128 - pack * in0_d3) if pack > 1 else 0)) }}
 {% endif %}
 {% endfor %}
{% endmacro %}

{# Each panel is stored as two residual components. Rewind the patch
   pointer between components, never rounding the accumulated output. #}
{% macro panel(n, tag) %}
 SET LR10 LR4 ; SET LR14 CR0 ;;
 part_{{ tag }}:
 SET LR4 LR10 ; SET LR7 CR0 ;;
 LD.MULT R0 LR5 {{ cr.weights }} ;;
 LD.MULT.CYCLIC LR4 {{ cr.patches }} LR11 ; INC LR5 1 ; DEC LR7 1 ;;
 {% if n > 1 %}
 mac_{{ tag }}:
 MULT.RC.VE LR11 LR7 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR7 1 ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.patches }} LR11 ; BLT.S LR7 {{ 'LR8' if n == 128 else 'LR9' }} mac_{{ tag }} ;;
 {% endif %}
 MULT.RC.VE LR11 LR7 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR7 1 ; INC LR4 1 ;;
 INC LR14 1 ;;
 BLT.S LR14 {{ cr.parts }} part_{{ tag }} ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR3 CR0 ; SET LR5 CR0 ;;
 SET LR11 CR0 ; SET LR12 CR0 ; SET LR13 CR0 ;;
 INC LR11 128 ; INC LR12 255 ;;
 INC LR12 1 ;;
 tile:
 SET LR1 CR0 ; SET LR4 LR5 ; ADD LR14 LR5 {{ cr.input_rows }} ;;
 gather:
 SET LR10 CR0 ;;
 INC LR10 1 ;;
 {% if chunks == 2 %}
 BEQ LR13 CR0 mask_start ;;
 INC LR10 15 ;;
 mask_start:
 {% endif %}
 {% if pack > 1 %}SET LR9 LR4 ;;{{ neighbors('narrow') }}{% endif %}
 {% for ky in [-1,0,1] %}{{ patches(ky) }}{% endfor %}
 ADD LR4 LR4 {{ cr.tiles }} ;;
 BLT.S LR4 LR14 gather ;;

 SET LR2 LR5 ; SET LR5 CR0 ; SET LR6 LR3 ;;
 SET LR8 CR0 ; SET LR9 CR0 ;;
 INC LR8 125 ;;
 {% set tail = ntaps % 128 %}
 {% if tail > 3 %}INC LR9 {{ tail - 3 }} ;;{% elif tail == 2 %}DEC LR9 1 ;;{% endif %}
 channel:
 SET LR4 CR0 ; SET LR1 CR0 ;;
 {% for p in range(2) %}
 LD.MULT.CYCLIC LR5 {{ cr.weights }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; {{ 'ACC.ADD.FIRST' if p == 0 else 'ACC.ADD' }} ; INC LR5 1 ;;
 {% endfor %}
 {% if ntaps >= 128 %}
 panels:
 {{ panel(128, 'full') }}
 INC LR1 1 ;;
 BLT.S LR1 {{ cr.panels }} panels ;;
 {% endif %}
 {% if tail %}{{ panel(tail, 'tail') }}{% endif %}
 {% if chunks == 2 %}
 BEQ LR13 CR0 store_full ;;
 {% endif %}
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
 {% if chunks == 2 %}
 B stored ;;
 store_full:
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
 stored:
 {% endif %}
 ADD LR6 LR6 {{ cr.tiles }} ;;
 BLT.S LR5 {{ cr.weight_rows }} channel ;;
 SET LR5 LR2 ;;
 INC LR5 1 ; INC LR3 1 ;;
 {% if chunks == 2 %}
 BEQ LR13 CR0 first_chunk ;;
 SET LR13 CR0 ;;
 B next_tile ;;
 first_chunk:
 INC LR13 1 ;;
 next_tile:
 {% endif %}
 BLT.S LR5 {{ cr.tiles }} tile ;;
 HALT ;;
