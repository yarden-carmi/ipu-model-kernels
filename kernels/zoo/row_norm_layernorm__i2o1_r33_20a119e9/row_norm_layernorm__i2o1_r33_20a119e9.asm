{% set q = cr.qf_stats ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set oq = cr.qf_out0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.L' %}
{% set tail = cr.ds_pair ~ '.H' %}
{% set k = cr.view_config ~ '.L' %}
{% macro ptr(r,n=0) %}
 SET {{ r }} CR0 ;;
 {% if n %}INC {{ r }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro ve(op='ADD', first=false, imm='CR1', fmt=q, shift='LR0') %}
 MULT.VE {{ shift }} {{ imm }} 0 {{ shift }} {{ full }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro clear(shift='LR0') %}{{ ve(first=true,imm='CR0',shift=shift) }}{% endmacro %}
{% macro mul(first=false, slot='LR0') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro load(n, cyclic=false) %}
 {{ ptr('LR1',n) }}
 {% if cyclic %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro split(reg, count, base=cr.tmp, stride='1', ds=full, fmt=q) %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ fmt }} {{ base }} {{ reg }} ;;
 {% for p in range(count) %}
 {% if not loop.last %}
 LD.MULT R0 {{ reg }} {{ base }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ fmt }} ; ACC.SUB ; {% if stride == '1' %}INC {{ reg }} 1{% else %}ADD {{ reg }} {{ reg }} {{ stride }}{% endif %} ; ACTIVATE.QUANTIZE identity {{ ds }} {{ fmt }} {{ base }} {{ reg }} ;;
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro save(n, count=3) %}{{ ptr('LR1',n) }}{{ split('LR1',count) }}{% endmacro %}
{% macro average(label) %}
 {# AGG places the sum in lane zero. Broadcast its residual planes. #}
 {{ save(0) }}
 {% for j in range(3) %}
 {{ load(j) }}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3) }}
 {{ ptr('LR10') }}{{ ptr('LR7',3) }}{{ clear() }}
{{ label }}:
 LD.MULT.CYCLIC LR10 {{ cr.stats }} LR0 ;;
 {% for j in range(3,6) %}{{ load(j) }}{{ mul() }}{% endfor %}
 INC LR10 1 ;;
 BLT.S LR10 LR7 {{ label }} ;;
{% endmacro %}
{% macro square_sum(ds) %}
 {% for a,b in [(0,0),(0,1),(1,1)] %}
 {% if a == b %}LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;{% endif %}
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {% for j in range(2 if a != b else 1) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 {% endfor %}
 {% if a == b %}INC LR9 1 ;;{% endif %}
 {% endfor %}
{% endmacro %}

{# Materialize the non-contiguous view. A logical channel step advances
   `rows` elements through the producer's unpadded flat storage. #}
{% macro advance(rem,step,label) %}
 {% if rem %}
 {% for _ in range(rem // 255) %}INC LR8 255 ;;{% endfor %}
 {% if rem % 255 %}INC LR8 {{ rem % 255 }} ;;{% endif %}
 BLT.S LR8 LR14 {{ label }} ;;
 SUB LR8 LR8 LR14 ; ADD LR9 LR9 {{ k }} ;;
{{ label }}:
 {% endif %}
 {% for _ in range(step // 255) %}INC LR9 255 ;;{% endfor %}
 {% if step % 255 %}INC LR9 {{ step % 255 }} ;;{% endif %}
{% endmacro %}
 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 INC LR3 128 ; SET LR4 CR0 ; SET LR5 CR0 ;;
view_batch:
 SET LR6 LR4 ; SET LR7 CR0 ; SET LR12 {{ cr.view_config }}.H ;;
 B view_token_wrap ;;
view_row:
 SET LR8 LR6 ; SET LR9 LR7 ; SET LR10 CR0 ;;
 SET LR11 CR0 ; SET LR15 CR0 ;;
view_channel:
 SET LR1 LR8 ; SET LR5 LR9 ;;
 BLT.S LR1 LR3 view_load ;;
view_chunk:
 SUB LR1 LR1 LR3 ; INC LR5 1 ;;
 {% if channels > 256 %}BGE.S LR1 LR3 view_chunk ;;{% endif %}
view_load:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.EE LR1 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD10 7 ; INC LR15 1 ;;
 SET LR5 CR0 ;;
 INC.MODP2 LR5 LR15 7 ;;
 BEQ LR15 LR14 view_tail ;;
 BNE LR5 CR0 view_advance ;;
 SET LR5 LR2 ;;
 {{ split('LR5',2,cr.gathered,'LR13',full,iq) }}
 INC LR2 1 ; SET LR10 CR0 ; SET LR11 CR0 ; B view_step ;;
view_advance:
 ADDBI LRD10 1 ;;
view_step:
 {{ advance(rows % channels,(rows // channels)*((channels+127)//128),'view_no_wrap') }}
 B view_channel ;;
view_tail:
 SET LR5 LR2 ;;
 {{ split('LR5',2,cr.gathered,'LR13',tail,iq) }}
 INC LR2 1 ; DEC LR12 1 ;;
 BEQ LR2 LR13 view_done ;;
 BEQ LR12 CR0 view_next_batch ;;
 {# Advance the view's token index by the batch extent. #}
 {% for _ in range(in0_d0 // 255) %}INC LR6 255 ;;{% endfor %}
 {% if in0_d0 % 255 %}INC LR6 {{ in0_d0 % 255 }} ;;{% endif %}
view_token_wrap:
 BLT.S LR6 LR14 view_row ;;
 SUB LR6 LR6 LR14 ; ADD LR7 LR7 {{ k }} ; B view_token_wrap ;;
view_next_batch:
 INC LR4 1 ; B view_batch ;;
view_done:
 SET LR12 {{ cr.view_config }}.H ;;

 SET LR0 CR0 ; SET LR2 CR0 ;;
 {{ ptr('LR3',128) }}
row_loop:
 SET LR5 LR2 ; ADD LR6 LR2 {{ k }} ;;
 {{ clear() }}
sum_loop:
 LD.MULT R0 LR5 {{ cr.gathered }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ iq }} ; AGG.SUM LR0 {{ full }} ; ADD LR8 LR5 LR13 ; LD.MULT R0 LR8 {{ cr.gathered }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ iq }} ; AGG.SUM LR0 {{ full }} ; INC LR5 1 ;;
 BLT.S LR5 LR6 sum_loop ;;
 {{ average('mean_scale') }}{{ save(6) }}

 SET LR5 LR2 ;;
 {{ ptr('LR9',32) }}
center_loop:
 LD.MULT R0 LR5 {{ cr.gathered }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.ADD.FIRST ; ADD LR8 LR5 LR13 ; LD.MULT R0 LR8 {{ cr.gathered }} ;;
 {{ ve(fmt=iq) }}
 {% for n in range(6,9) %}{{ load(n) }}{{ ve('SUB') }}{% endfor %}
 {{ split('LR9',2) }}
 INC LR9 1 ; INC LR5 1 ;;
 BLT.S LR5 LR6 center_loop ;;

 {{ clear() }}
 {{ ptr('LR9',32) }}
 ADD LR5 LR2 CR1 ;;
 BGE.S LR5 LR6 variance_tail ;;
variance_loop:
 {{ square_sum(full) }}
 INC LR5 1 ;;
 BLT.S LR5 LR6 variance_loop ;;
variance_tail:
 {{ square_sum(tail) }}
 {{ average('variance_scale') }}
 LD.MULT R0 LR7 {{ cr.stats }} ;;
 {{ ve() }}
 {{ ptr('LR1',12) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(9) }}
 {{ ptr('LR1',13) }}{{ clear() }}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ ptr('LR4',2) }}
refine:
 {% for i in range(2) %}
 {{ load(12+i,true) }}
 {% for j in range(2) %}{{ load(12+j) }}{{ mul(first=(i==0 and j==0)) }}{% endfor %}
 {% endfor %}
 {{ save(14,2) }}
 {% for i in range(3) %}
 {{ load(9+i,true) }}
 {% for j in range(2) %}{{ load(14+j) }}{{ mul(first=(i==0 and j==0)) }}{% endfor %}
 {% endfor %}
 {{ save(16,2) }}
 {% for i in range(2) %}
 {{ load(12+i,true) }}
 {% for j in range(2) %}{{ load(16+j) }}{{ mul(first=(i==0 and j==0)) }}{% endfor %}
 {% endfor %}
 {{ save(18,2) }}
 {% for i in range(2) %}
 {{ load(12+i,true) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% endfor %}
 {% for n in [18,19] %}{{ load(n) }}{{ ve('SUB',imm=cr.half) }}{% endfor %}
 {{ save(12,2) }}
 DEC LR4 1 ;;
 BLT.S CR0 LR4 refine ;;

 SET LR5 LR2 ;;
 {{ ptr('LR9',32) }}{{ ptr('LR11') }}{{ ptr('LR7',3) }}
normalize:
 SET LR10 LR11 ; SET LR4 CR0 ;;
 {{ clear() }}
weight_loop:
 LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0 ;;
 {% for n in [12,13] %}{{ load(n) }}{{ mul() }}{% endfor %}
 ADD LR10 LR10 {{ k }} ; INC LR4 1 ;;
 BLT.S LR4 LR7 weight_loop ;;
 {{ save(20) }}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 INC LR9 1 ;;
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR3 ;;
 INC LR9 1 ;;
 {% for n in range(20,23) %}{{ load(n) }}{{ mul(first=loop.first) }}{{ mul(slot='LR3') }}{% endfor %}
 SET LR10 LR11 ;;
 {% for i in range(3) %}
 LD.MULT R0 LR10 {{ cr.beta }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; ADD LR10 LR10 {{ k }} ;;
 {% endfor %}
 SET LR8 LR5 ;;
 {{ split('LR8',3,cr.normalized,'LR13') }}
 INC LR5 1 ; INC LR11 1 ;;
 BLT.S LR5 LR6 normalize ;;
 SET LR2 LR6 ;;
 BLT.S LR2 LR13 row_loop ;;

{# Accumulator scatter forms one output vector per channel and token tile.
   Reassemble the residuals before the only output-format rounding. #}
{% macro scatter() -%}
 MULT.EE LR4 CR1 0 LR15 {{ full }} {{ q }} ; ACC.RESHAPE LRD4 LRD10 7
{%- endmacro %}
{% macro gather(p) %}
 SET LR6 LR2 ; SET LR10 CR0 ; SET LR11 CR0 ;;
 SET LR8 LR7 ;;
 {% for i in range(p) %}ADD LR6 LR6 LR13 ;;{% endfor %}
 {% if out0_d1 % 128 %}{{ clear('LR15') }}{% endif %}
 LD.MULT R0 LR6 {{ cr.normalized }} ; DEC LR8 1 ;;
 BEQ LR8 CR0 last{{ p }} ;;
more{{ p }}:
 {{ scatter() }} ; LD.MULT R0 LR6 {{ cr.normalized }} ; ADD LR6 LR6 {{ k }} ; DEC LR8 1 ;;
 ADDBI LRD10 1 ; BLT.S CR0 LR8 more{{ p }} ;;
last{{ p }}:
 {{ scatter() }} ; ADD LR6 LR6 {{ k }} ;;
{% endmacro %}

 SET LR2 CR0 ; SET LR15 CR0 ;;
batch:
 SET LR4 CR0 ; SET LR1 LR2 ; SET LR9 CR0 ;;
channel:
 SET LR2 LR1 ; SET LR5 LR12 ;;
tile:
 SET LR7 LR3 ;;
 BGE.S LR5 LR3 tile_ready ;;
 SET LR7 LR5 ;;
tile_ready:
 {% for p in [2,1,0] %}
 {{ gather(p) }}
 {% for r in range(2-p) %}
 {{ ptr('LR8',r) }}
 LD.MULT R0 LR8 {{ cr.tmp }} ;;
 {{ ve(shift='LR15') }}
 {% endfor %}
 {% if p %}
 {{ ptr('LR8') }}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR8 ;;
 {% if p == 1 %}
 LD.MULT R0 LR8 {{ cr.tmp }} ;;
 {{ ve('SUB',shift='LR15') }}
 INC LR8 1 ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR8 ;;
 {% endif %}
 {% endif %}
 {% endfor %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ full }} {{ oq }} {{ cr.out0 }} LR0 ;;
 INC LR0 1 ; SUB LR5 LR5 LR7 ;;
 SET LR2 LR6 ;;
 BLT.S CR0 LR5 tile ;;
 INC LR9 1 ; INC.MODP2 LR4 CR1 7 ;;
 BNE LR4 CR0 same_chunk ;;
 INC LR1 1 ;;
same_chunk:
 BLT.S LR9 LR14 channel ;;
 {# LR6 is one stride past the last row, at the last channel chunk. #}
 SUB LR2 LR6 {{ k }} ;;
 INC LR2 1 ;;
 BLT.S LR2 LR13 batch ;;
 HALT ;;
