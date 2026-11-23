{% set width = in0_d3 %}
{% set narrow = width == 8 %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.full ~ '.L' %}
{% set md = cr.full ~ '.H' %}
{% set act_out0 = act_out0 | default('identity') %}

{% macro tap(ky, kx) %}
 {% set shift = ['LR10', 'LR9', 'LR11'][kx] %}
 {% set delta = ['LR11', 'LR9', 'LR10'][kx] %}
 {% if narrow %}
 LD.MULT R0 LR4 {{ cr.weights }} ; ADD LR12 LR15 {{ delta }} ;;
 {% for part in range(3) %}
 MULT.RC.VV LR12 R0 0 LR9 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR4 1 {% if part != 2 %}; LD.MULT R0 LR4 {{ cr.weights }}{% endif %} ;;
 {% endfor %}
 {% else %}
 {% set i = 3 * ky + kx %}
 {% set addr = 'LR12' if i % 2 == 0 else 'LR14' %}
 {% set next_addr = 'LR14' if i % 2 == 0 else 'LR12' %}
 MULT.RC.VE {{ addr }} LR5 0 {{ shift }} {{ md }} {{ qi }} ; ACC.ADD ; ADD LR6 LR5 LR7 {% if kx == 2 and ky != 2 %}; INC LR15 {{ width }}{% endif %} ;;
 MULT.RC.VE {{ addr }} LR6 0 {{ shift }} {{ md }} {{ qi }} ; ACC.ADD ; INC LR5 1 {% if i != 8 %}; ADD {{ next_addr }} LR15 {{ ['LR9', 'LR10', 'LR11'][kx] }}{% endif %} ;;
 {% endif %}
{% endmacro %}

 SET LR7 CR0 ; SET LR8 CR0 ; SET LR1 CR1 ;;
 INC LR7 128 ; INC LR8 255 ; SET LR10 CR1 ;;
 INC LR8 1 ; DEC LR11 1 ;;
channel:
 SET LR0 CR0 ;;
tile:
 SET LR4 LR1 ; SET LR13 CR0 ; SET LR3 LR0 ;;
 LD.MULT R0 LR4 {{ cr.weights }} ; SET LR5 CR0 ;;
 INC LR5 126 ;;
 {% if narrow %}
 {% for part in range(3) %}
 MULT.VE LR9 CR1 0 LR9 {{ ds }} {{ qi }} ; {{ 'ACC.ADD.FIRST' if part == 0 else 'ACC.ADD' }} ; INC LR4 1 {% if part != 2 %}; LD.MULT R0 LR4 {{ cr.weights }}{% endif %} ;;
 {% endfor %}
 {% else %}
 MULT.EE LR5 CR1 0 LR9 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; INC LR4 1 ; LD.MULT R1 LR4 {{ cr.weights }} ;;
 ADD LR6 LR5 LR7 ; MULT.EE LR6 CR1 0 LR9 {{ ds }} {{ qi }} ; ACC.ADD ;;
 SET LR5 CR0 ;;
 {% endif %}
input_channel:
 SET LR6 LR3 ; BEQ LR0 CR0 zero_prev ;;
 DEC LR6 1 ;;
 LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR9 ; B load_center ;;
zero_prev:
 LD.MULT.CYCLIC LR9 {{ cr.weights }} LR9 ;;
load_center:
 LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR7 ; INC LR6 1 ; BEQ LR0 {{ cr.last }} zero_next ;;
 SET LR6 LR3 ;;
 INC LR6 1 ;;
 LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR8 ; B taps ;;
zero_next:
 LD.MULT.CYCLIC LR9 {{ cr.weights }} LR8 ;;
taps:
 SET LR15 LR7 ;;
 DEC LR15 {{ width }} ;;
 {% if not narrow %}ADD LR12 LR15 LR11 ;;{% endif %}
 {% for ky in range(3) %}
 {% for kx in range(3) %}
 {{ tap(ky, kx) }}
 {% endfor %}
 {% if narrow and ky != 2 %}INC LR15 {{ width }} ;;{% endif %}
 {% endfor %}
 INC LR13 1 ; ADD LR3 LR3 {{ cr.tiles }} ;;
 BGE.S LR13 {{ cr.cin }} tile_store ;;
 {% if not narrow %}
 SET LR14 CR0 ;;
 INC LR14 126 ;;
 BLT.S LR5 LR14 input_channel ;;
 INC LR4 1 ; SET LR5 CR0 ;;
 LD.MULT R0 LR4 {{ cr.weights }} ;;
 INC LR4 1 ; LD.MULT R1 LR4 {{ cr.weights }} ;;
 {% endif %}
 B input_channel ;;
tile_store:
 {% if stride == 1 %}
 {% if out0_d2 * out0_d3 % 128 %}BEQ LR0 {{ cr.last }} tail_store ;;{% endif %}
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }} {{ qo }} {{ cr.out0 }} LR2 ; B tile_next ;;
 {% if out0_d2 * out0_d3 % 128 %}
tail_store:
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.out_tail }}.L {{ qo }} {{ cr.out0 }} LR2 ;;
 {% endif %}
tile_next:
 INC LR2 1 ; INC LR0 1 ;;
 BLT.S LR0 {{ cr.tiles }} tile ;;
 {% else %}
 {% if in0_d2 * width % 128 %}BEQ LR0 {{ cr.last }} scratch_tail ;;{% endif %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.decimate }} LR0 ; B scratch_next ;;
 {% if in0_d2 * width % 128 %}
scratch_tail:
 ACTIVATE.QUANTIZE identity {{ cr.input_tail }}.L {{ qo }} {{ cr.decimate }} LR0 ;;
 {% endif %}
scratch_next:
 INC LR0 {{ 2 if width == 128 else 1 }} ;;
 BLT.S LR0 {{ cr.tiles }} tile ;;
 SET LR3 CR0 ;;
gather:
 MULT.EE LR9 CR0 0 LR9 {{ ds }} {{ qo }} ; ACC.ADD.FIRST ;;
 {% for part in range(2 if width == 128 else 4) %}
 LD.MULT.CYCLIC LR3 {{ cr.decimate }} LR9 ;;
 {% if narrow %}
 {# Each source row contributes two runs of four samples. #}
 {% macro imm(reg, bytes) %}
 SET {{ reg }} CR0 ;;
 {% for byte in bytes | reverse %}
 {% if not loop.first %}{% for bit in range(8) %}ADD {{ reg }} {{ reg }} {{ reg }} ;;{% endfor %}{% endif %}
 {% if byte %}INC {{ reg }} {{ byte }} ;;{% endif %}
 {% endfor %}
 {% endmacro %}
 {% if part == 0 %}
 {{ imm('LR4', [0,2,4,6]) }}
 {{ imm('LR5', [16,18,20,22]) }}
 {{ imm('LR6', [0,1,2,3]) }}
 {{ imm('LR7', [4,5,6,7]) }}
 {% endif %}
 {% for sub in range(4) %}
 MULT.RC.VE LR9 CR1 0 LR9 {{ ds }} {{ qo }} ; ACC.RESHAPE LRD4 LRD6 0 ;;
 ADDBI LRD4 {{ -96 if sub == 3 else 32 }} ; ADDBI LRD6 8 ;;
 {% endfor %}
 {% else %}
 SET LR6 CR0 ;;
 {% if part %}INC LR6 {{ part * (2 if width == 128 else 1) }} ;;{% endif %}
 MULT.RC.VE LR9 CR1 0 LR9 {{ ds }} {{ qo }} ; ACC.STRIDE {{ [16, width]|max }} on {{ 'off' if width == 128 else 'on' }} LR6 ;;
 {% endif %}
 INC LR3 {{ 2 if width == 128 else 1 }} ;;
 BGE.S LR3 {{ cr.tiles }} gather_tail ;;
 {% endfor %}
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }} {{ qo }} {{ cr.out0 }} LR2 ;;
 INC LR2 1 ; B gather ;;
gather_tail:
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.out_tail }}.L {{ qo }} {{ cr.out0 }} LR2 ;;
 INC LR2 1 ;;
 {% if narrow %}SET LR7 CR0 ;; INC LR7 128 ;;{% endif %}
 {% endif %}
 ADD LR1 LR1 {{ cr.weight_rows }} ;;
 BLT.S LR1 {{ cr.weight_end }} channel ;;
 HALT ;;
