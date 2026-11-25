{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set width = cr.width_ds ~ '.L' %}

{% macro decimate(index) %}
 MULT.RC.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE {{ index }} CR1 0 LR0 {{ full }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;
 ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.parity }} LR4 ;;
 INC LR4 1 ;;
{% endmacro %}

{% macro patch_tap(x) %}
 {% if x != 1 %}
 LD.MULT.CYCLIC {{ 'LR8' if stride == 2 else 'LR7' }} {{ cr.parity if stride == 2 else cr.in0 }} LR13 ;;
 {% elif stride == 2 %}
 LD.MULT.CYCLIC LR9 {{ cr.parity }} LR13 ;;
 {% endif %}
 {% if x == 1 %}SET LR9 CR1 ;;{% endif %}
 LD.MULT R0 {{ ['LR0','LR9','LR11'][x] }} {{ cr.masks }} ;;
 MULT.RC.VV {{ ['LR10','LR13','LR3' if stride == 1 else 'LR13'][x] }} R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;
 ACTIVATE.QUANTIZE identity {{ width }} {{ qi }} {{ cr.patch }} LR4 ;;
 INC LR4 1 ;;
{% endmacro %}

{# One scalar per tap, broadcast over an entire output row. #}
{% macro panel(tag, end, count) %}
 LD.MULT R0 LR5 {{ cr.weights }} ; SET LR7 CR0 ;;
 LD.MULT.CYCLIC LR4 {{ cr.patch }} LR13 ; INC LR5 1 ; DEC LR7 1 ;;
 {% if count > 1 %}
 mac_{{ tag }}:
 MULT.RC.VE LR13 LR7 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR7 1 ; INC LR4 1 ;
 LD.MULT.CYCLIC LR4 {{ cr.patch }} LR13 ; BLT.S LR7 {{ end }} mac_{{ tag }} ;;
 {% endif %}
 MULT.RC.VE LR13 LR7 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR7 1 ; INC LR4 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR13 CR0 ; SET LR4 CR0 ;;
 INC LR13 128 ; SET LR2 CR0 ;;
 SET LR3 LR13 ;;
 INC LR3 1 ;;
 {% if stride == 2 %}
 parity_row:
 LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR13 ;;
 {{ decimate('LR13') }}
 {{ decimate('LR3') }}
 INC LR2 1 ;;
 BLT.S LR2 LR12 parity_row ;;
 {% endif %}
 SET LR1 CR0 ; SET LR2 CR0 ; SET LR10 LR13 ;;
 DEC LR10 1 ; SET LR11 CR0 ; SET LR12 CR0 ;;
 INC LR11 2 ; INC LR12 125 ;;

 output_row:
 SET LR4 CR0 ; SET LR5 LR1 ;;
 DEC LR5 1 ;;
 kernel_row:
 SET LR7 LR5 ; SET LR6 CR0 ; BLT.S LR5 CR0 zero_channel ;;
 BGE.S LR5 {{ cr.in0_d2 }} zero_channel ;;
 patch_channel:
 {% if stride == 2 %}
 ADD LR9 LR7 LR7 ;;
 ADD LR8 LR9 CR1 ;;
 {% endif %}
 {% for x in range(3) %}{{ patch_tap(x) }}{% endfor %}
 INC LR6 1 ; ADD LR7 LR7 {{ cr.in0_d2 }} ;;
 BLT.S LR6 {{ cr.cin }} patch_channel ;;
 BEQ LR0 CR0 next_kernel_row ;;
 zero_channel:
 {% for x in range(3) %}
 MULT.RC.VE LR13 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ width }} {{ qi }} {{ cr.patch }} LR4 ;;
 INC LR4 1 ;;
 {% endfor %}
 INC LR6 1 ;;
 BLT.S LR6 {{ cr.cin }} zero_channel ;;
 next_kernel_row:
 INC LR5 1 ; SET LR8 LR1 ;;
 INC LR8 2 ;;
 BLT.S LR5 LR8 kernel_row ;;

 SET LR5 CR0 ;;
 output_channel:
 SET LR4 CR0 ; SET LR6 CR0 ; LD.MULT.CYCLIC LR5 {{ cr.weights }} LR13 ;;
 MULT.RC.VE LR13 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; INC LR5 1 ;;
 {% if 9 * cin >= 128 %}
 full_panel:
 {{ panel('full', 'LR12', 128) }}
 INC LR6 1 ;;
 BLT.S LR6 LR14 full_panel ;;
 {% endif %}
 {% if 9 * cin % 128 %}{{ panel('tail', 'LR15', 9 * cin % 128) }}{% endif %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ width }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
 INC LR2 1 ; BLT.S LR5 {{ cr.weight_rows }} output_channel ;;
 INC LR1 {{ stride }} ;;
 BLT.S LR1 {{ cr.tile_end }} output_row ;;
 HALT ;;
