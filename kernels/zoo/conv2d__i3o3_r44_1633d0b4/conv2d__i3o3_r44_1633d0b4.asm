{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set packed = cr.packed ~ '.L' %}

{% macro offset(reg, n) %}
{% for i in range(0, n, 255) %}
 INC {{ reg }} {{ [255, n-i]|min }} ;;
{% endfor %}
{% endmacro %}

{# Gather one tap for a tile of output rows into a SIMD vector. #}
{% macro patch(x) %}
 MULT.RC.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; SET LR9 LR5 ; SET LR10 LR7 ; SET LR11 LR13 ;;
 SET LR12 CR0 ;;
 {{ offset('LR12', 1+x*pack) }}
 {% set shift = x - 1 if stride == 1 else (-1 if x == 0 else 0) %}
 {% if shift %}{{ 'INC' if shift > 0 else 'DEC' }} LR11 1 ;;{% endif %}
 {% if pack > 1 %}
 SET LR4 CR0 ;;
 {{ offset('LR4', 1+(x+1)*pack) }}
 {% endif %}
 slot_{{ x }}:
 LD.MULT R0 LR12 {{ cr.masks }} ; BLT.S LR9 CR0 next_slot_{{ x }} ;;
 BGE.S LR9 {{ cr.in0_d2 }} next_slot_{{ x }} ;;
 {% if stride == 2 %}
 ADD LR8 LR10 LR10 ;;
 {% if x != 1 %}INC LR8 1 ;;{% endif %}
 LD.MULT.CYCLIC LR8 {{ cr.parity }} LR13 ;;
 {% else %}
 LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR13 ;;
 {% endif %}
 MULT.RC.VV LR11 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
 next_slot_{{ x }}:
 {% if pack > 1 %}
 INC LR12 1 ; INC LR9 {{ stride }} ; DEC LR11 {{ out0_d3 }} ;;
 INC LR10 {{ stride }} ; BLT.S LR12 LR4 slot_{{ x }} ;;
 {% endif %}
 ACTIVATE.QUANTIZE identity {{ packed }} {{ qi }} {{ cr.patches }} LR1 ;;
 INC LR1 1 ;;
{% endmacro %}

{% macro parity(odd) %}
 MULT.RC.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE {{ 'LR4' if odd else 'LR13' }} CR1 0 LR0 {{ full }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.parity }} LR1 ;;
 INC LR1 1 ;;
{% endmacro %}

{# Multiply one packed patch vector per scalar in the weight panel. #}
{% macro reduce_panel(count, tag) %}
 LD.MULT R0 LR5 {{ cr.weights }} ; SET LR7 CR0 ;;
 LD.MULT.CYCLIC LR4 {{ cr.patches }} LR13 ; INC LR5 1 ; DEC LR7 1 ;;
 {% if count > 1 %}
 mac_{{ tag }}:
 MULT.RC.VE LR13 LR7 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR7 1 ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.patches }} LR13 ; BLT.S LR7 {{ 'LR8' if count == 128 else 'LR9' }} mac_{{ tag }} ;;
 {% endif %}
 MULT.RC.VE LR13 LR7 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR7 1 ; INC LR4 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR13 CR0 ; SET LR1 CR0 ;;
 SET LR2 CR0 ; SET LR3 CR0 ; INC LR13 128 ;;
 LD.MULT.CYCLIC LR0 {{ cr.masks }} LR0 ;;
{% if stride == 2 %}
 SET LR4 LR13 ;;
 INC LR4 1 ;;
 parity_row:
 LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR13 ;;
 {{ parity(false) }}
 {{ parity(true) }}
 INC LR2 1 ;;
 BLT.S LR2 LR14 parity_row ;;
 SET LR2 CR0 ;;
{% endif %}

 tile:
 SET LR1 CR0 ; SET LR5 LR2 ;;
 DEC LR5 1 ;;
 ky:
 SET LR7 LR5 ; SET LR6 CR0 ;;
 channel:
 {% for x in range(3) %}{{ patch(x) }}{% endfor %}
 INC LR6 1 ; ADD LR7 LR7 {{ cr.in0_d2 }} ;;
 BLT.S LR6 {{ cr.cin }} channel ;;
 INC LR5 1 ; SET LR8 LR2 ;;
 INC LR8 2 ;;
 BLT.S LR5 LR8 ky ;;

 SET LR5 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
 SET LR14 CR0 ; INC LR8 125 ;;
 {% if 9 * cin % 128 > 3 %}INC LR9 {{ 9 * cin % 128 - 3 }} ;;{% endif %}
 {% if 9 * cin % 128 == 2 %}DEC LR9 1 ;;{% endif %}
 {% if 9 * cin >= 128 %}INC LR14 {{ 9 * cin // 128 }} ;;{% endif %}
 output_channel:
 LD.MULT.CYCLIC LR5 {{ cr.weights }} LR0 ; SET LR4 CR0 ; SET LR6 CR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; INC LR5 1 ;;
 {% if 9 * cin >= 128 %}
 panel:
 {{ reduce_panel(128, 'full') }}
 INC LR6 1 ;;
 BLT.S LR6 LR14 panel ;;
 {% endif %}
 {% if 9 * cin % 128 %}{{ reduce_panel(9 * cin % 128, 'tail') }}{% endif %}

 {# Unpack to y-major, channel-minor rows, applying activation at the store. #}
 SET LR10 LR3 ;;
 {% if pack > 1 %}
 ACTIVATE.QUANTIZE identity {{ packed }} {{ qo }} {{ cr.patches }} LR1 ; SET LR11 LR13 ; SET LR12 CR0 ;;
 LD.MULT.CYCLIC LR1 {{ cr.patches }} LR13 ;;
 {{ offset('LR12', pack*out0_d3) }}
 ADD LR12 LR12 LR13 ;;
 split:
 MULT.RC.VE LR11 CR1 0 LR0 {{ full }} {{ qo }} ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.width }}.L {{ qo }} {{ cr.out0 }} LR10 ; INC LR11 {{ out0_d3 }} ;;
 BGE.S LR11 LR12 split_done ;;
 ADD LR10 LR10 LR15 ; BEQ LR0 CR0 split ;;
 split_done:
 {% else %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ packed }} {{ qo }} {{ cr.out0 }} LR10 ;;
 {% endif %}
 INC LR3 1 ;;
 BLT.S LR5 {{ cr.weight_rows }} output_channel ;;
 SET LR3 LR10 ;;
 INC LR3 1 ;;
 {{ offset('LR2', pack*stride) }}
 SET LR6 CR0 ;;
 {{ offset('LR6', tile_end) }}
 BLT.S LR2 LR6 tile ;;
 HALT ;;
