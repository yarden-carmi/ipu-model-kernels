{% set qi = cr.qf_in0 ~ '.L' %}
{% set ds = cr.full ~ '.L' %}
{% set cap = [out0_d3, 128 // out0_d2] | min %}
{% set p = [1, out0_d3 // ((out0_d3 + cap - 1) // cap)] | max %}
{% set pack = p if out0_d3 % p == 0 else 1 %}
{% set icg = in0_d1 // groups %}
{% set ocg = out0_d1 // groups %}
{% set src = cr.parity if stride == 2 else cr.in0 %}

{% macro weight() %}
 LD.MULT R0 LR9 {{ cr.weights }} ; INC LR9 1
{% endmacro %}

{% macro horizontal(kx) %}
 SET LR11 LR7 ; SET LR12 LR8 ; SET LR14 CR0 ;;
 {% if kx < 0 %}
 DEC LR11 1 ; DEC LR12 {{ in0_d1 }} ;;
 {% elif kx > 0 %}
 INC LR11 1 ; INC LR12 {{ in0_d1 }} ;;
 {% endif %}
 INC LR14 {{ icg }} ;;
 ic_{{ kx + 1 }}:
 BLT.S LR11 CR0 zero_{{ kx + 1 }} ;;
 BGE.S LR11 {{ cr.in0_d3 }} zero_{{ kx + 1 }} ;;
 LD.MULT.CYCLIC LR12 {{ src }} LR1 ; BEQ LR0 CR0 loaded_{{ kx + 1 }} ;;
 zero_{{ kx + 1 }}:
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR1 ;;
 loaded_{{ kx + 1 }}:
 {% for ky in range(3) %}
 SET LR13 LR10 ;;
 {% set shift = [-1, 0, 1][ky] if stride == 1 else [63, 0, 64][ky] %}
 {% if shift < 0 %} DEC LR13 1 ; {% elif shift > 0 %} INC LR13 {{ shift }} ; {% endif %} {{ weight() }} ;;
 {% for part in range(4) %}
 MULT.RC.VV LR13 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD {% if not loop.last %}; {{ weight() }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 INC LR12 1 ; DEC LR14 1 ;;
 BNE LR14 CR0 ic_{{ kx + 1 }} ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 INC LR1 128 ;;
 {% if stride == 2 %}
 SET LR3 CR0 ;;
 INC LR3 2 ;;
 parity:
 LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on_inv off LR3 ;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.parity }} LR2 ;;
 INC LR2 1 ;;
 BLT.S LR2 {{ cr.input_rows }} parity ;;
 {% endif %}
 SET LR2 CR0 ; SET LR6 CR0 ; SET LR3 CR0 ;;
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR0 ; SET LR13 LR1 ;;
 INC LR13 128 ; LD.MULT.CYCLIC LR0 {{ cr.weights }} LR13 ;;
 INC LR13 128 ; LD.MULT.CYCLIC LR0 {{ cr.weights }} LR13 ;;
 batch:
 SET LR3 LR2 ; SET LR4 CR0 ; SET LR5 CR0 ;;
 INC LR4 {{ ocg }} ;;
 channel:
 SET LR7 CR0 ; SET LR8 LR3 ;;
 packed_column:
 SET LR9 LR5 ; SET LR10 LR1 ; SET LR15 CR0 ;;
 INC LR15 {{ pack }} ; {{ weight() }} ;;
 {% for part in range(4) %}
 MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; {{ 'ACC.ADD.FIRST' if loop.first else 'ACC.ADD' }} {% if not loop.last %}; {{ weight() }}{% endif %} ;;
 {% endfor %}
 member:
 {% for kx in [-1, 0, 1] %}
 {{ horizontal(kx) }}
 {% endfor %}
 INC LR7 {{ stride }} ; INC LR8 {{ stride * in0_d1 }} ; DEC LR10 {{ out0_d2 }} ;;
 DEC LR15 1 ;;
 BNE LR15 CR0 member ;;
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
 INC LR6 1 ; BLT.S LR7 {{ cr.in0_d3 }} packed_column ;;
 SET LR5 LR9 ; DEC LR4 1 ;;
 BGE.S LR5 {{ cr.last_weight }} next_batch ;;
 BNE LR4 CR0 channel ;;
 INC LR3 {{ icg }} ; SET LR4 CR0 ;;
 INC LR4 {{ ocg }} ; BEQ LR0 CR0 channel ;;
 next_batch:
 ADD LR2 LR2 {{ cr.batch_rows }} ; BLT.S LR6 {{ cr.output_rows }} batch ;;
 HALT ;;
