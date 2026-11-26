{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.input_tail ~ '.L' %}
{% set ir = (in0_d2*w+127)//128 %}
{% set wk = 3+(4-stride)*(cin//groups)*kh*kw %}
{% set window = stride == 1 and w <= 128 %}
{% macro bump(r,n) %}
{% if n>0 %}INC {{ r }} {{ n }} ;{% elif n<0 %}DEC {{ r }} {{ -n }} ;{% endif %}
{% endmacro %}
{% macro imm(r,n) %}
SET {{ r }} CR0 ;;
{% if n|abs <= 255 %}
{% if n %}{{ bump(r,n) }} ;;{% endif %}
{% else %}
{% for bit in range(19,-1,-1) if n >= 2**bit %}
{% if n >= 2**(bit+1) %}ADD {{ r }} {{ r }} {{ r }} ;;{% endif %}
{% if (n//(2**bit))%2 %}INC {{ r }} 1 ;;{% endif %}
{% endfor %}
{% endif %}
{% endmacro %}

# Copy spatial planes between explicit vertical zero guards.
{{ imm('LR0',0) }}
{{ imm('LR1',128) }}
{{ imm('LR2',-1) }}
{{ imm('LR3',-1) }}
{{ imm('LR4',0) }}
{{ imm('LR5',cin-1) }}
{{ imm('LR6',ir-1) }}
{% macro guard(label,count) %}
{{ imm('LR7',count-1) }}
SET LR8 CR0 ; MULT.RC.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
{{ label }}:
ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.guard }} LR3 ; INC LR3 1 ; INC LR8 1 ; BLT.S LR8 LR7 {{ label }} ;;
{% endmacro %}
copy_channel:
{{ guard('copy_top',4) }}
SET LR8 CR0 ;;
copy_row:
{% if (in0_d2*w)%128 %}BEQ LR8 LR6 copy_last ;;{% endif %}
LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ;;
MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.guard }} LR3 ; INC LR3 1 ; INC LR8 1 ; BLT.S LR8 LR6 copy_row ;;
{% if (in0_d2*w)%128 %}
BEQ LR0 CR0 copy_end ;;
copy_last:
LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ;;
MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
ACTIVATE.QUANTIZE identity {{ cr.input_tail }}.H {{ qi }} {{ cr.guard }} LR3 ; INC LR3 1 ;;
copy_end:
{% endif %}
{{ guard('copy_bottom',6) }}
INC LR4 1 ; BLT.S LR4 LR5 copy_channel ;;

# For stride two, compact the four input quadrants into output order once.
{% if stride == 2 %}
{{ imm('LR2',-1) }}
{{ imm('LR4',0) }}
{{ imm('LR13',4) }}
{{ imm('LR14',ir+10) }}
{{ imm('LR10',128) }}
{{ imm('LR11',256) }}
{{ imm('LR12',384) }}
{% macro piece(d,acc,last,p,step) %}
LD.MULT.CYCLIC LR6 {{ cr.guard }} LR0 ;
{% if p %}{{ bump('LR6',step-(1 if d%128 else 0)) }} INC LR9 {{ 1 if w <= 64 else 2 }} ;{% endif %} ;;
{% if d%128 %}
LD.MULT.CYCLIC LR6 {{ cr.guard }} LR1 ; INC LR6 1 ;;
{% endif %}
MULT.RC.VE LR7 CR1 0 LR0 {{ ds }} {{ qi }} ; {{ acc }} ;
{% if last %}ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.stencil }} LR2 ; INC LR2 1 ;{% endif %} ;;
{% endmacro %}
{% macro stage_tap(t) %}
{% set d = (t//kw-padding)*w+t%kw-padding %}
SET LR6 LR3 ; SET LR7 LR0 ; SET LR9 LR0 ;;
{% if d %}{{ bump('LR6',d//128) }} {{ bump('LR7',d%128) }} ;;{% endif %}
{% if w <= 64 %}
{# Walk adjacent slots of the cyclic ring; the next window shares its first row. #}
LD.MULT.CYCLIC LR6 {{ cr.guard }} LR0 ; DEC LR7 128 ; DEC LR9 1 ;;
LD.MULT.CYCLIC LR6 {{ cr.guard }} LR10 ; INC LR6 1 ;;
{% for p in range(4) %}
MULT.RC.VE LR7 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE {{ [16,w]|max }} on on LR9 ; INC LR7 128 ; INC LR9 1 ;
{% if p < 3 %}
LD.MULT.CYCLIC LR6 {{ cr.guard }} {{ ['LR11','LR12','LR0'][p] }} ; INC LR6 1 ;
{% else %}
ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.stencil }} LR2 ; INC LR2 1 ;
{% endif %} ;;
{% endfor %}
{% else %}
{{ piece(d,'ACC.STRIDE 64 on off LR9',false,0,1) }}
{{ piece(d,'ACC.STRIDE 64 on off LR9',true,1,2 if w==128 else 1) }}
{% endif %}
{% endmacro %}
stage_channel:
SET LR3 LR13 ; SET LR8 CR0 ;;
stage_row:
{% for t in range(kh*kw) %}{{ stage_tap(t) }}{% endfor %}
INC LR3 4 ; INC LR8 1 ; BLT.S LR8 {{ cr.sr_last }} stage_row ;;
ADD LR13 LR13 LR14 ; INC LR4 1 ; BLT.S LR4 LR5 stage_channel ;;
{% endif %}

{{ imm('LR2',-1) }}
{% for i in range(5) %}
LD.LUT {{ i }} {{ cr.lut }} LR2 ; INC LR2 1 ;;
{% endfor %}
{{ imm('LR2',-1) }}
{{ imm('LR3',4 if stride == 1 else -1) }}
{{ imm('LR4',0) }}
{{ imm('LR5',cout-1) }}
{{ imm('LR7',-1) }}
{{ imm('LR13',cout//groups-1) }}
{{ imm('LR14',0) }}
{{ imm('LR12',128) }}

output_channel:
SET LR6 CR0 ; SET LR10 LR3 ;;
output_row:
{% if out0_d3>128 %}
SET LR8 LR7 ;;
SET LR11 LR6 ;;
INC.MODP2 LR11 CR0 1 ;;
BEQ LR11 LR0 bias_load ;;
{{ imm('LR1',wk) }}
ADD LR8 LR8 LR1 ;;
bias_load:
LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ; INC LR8 1 ;;
{% else %}
ADD LR8 LR7 CR1 ; LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ;;
{% endif %}
MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; SET LR9 LR10 ; LD.MULT.CYCLIC LR8 {{ cr.weights }} LR12 ; INC LR8 1 ;;
MULT.RC.VE LR12 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; SET LR11 CR0 ; LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ; INC LR8 1 ;;
MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ; {% if stride == 2 %}SET LR1 LR9 ;{% endif %} ;;
input_channel:
{% if window %}
SET LR1 LR9 ; SET LR0 CR0 ;;
DEC LR1 2 ;;
LD.MULT.CYCLIC LR1 {{ cr.guard }} LR0 ;;
LD.MULT.CYCLIC LR1 {{ cr.guard }} LR0 ; INC LR1 1 ; INC LR0 128 ;;
LD.MULT.CYCLIC LR1 {{ cr.guard }} LR0 ; INC LR1 1 ; INC LR0 128 ;;
LD.MULT.CYCLIC LR1 {{ cr.guard }} LR0 ; INC LR1 1 ; INC LR0 128 ;;
SET LR0 CR0 ; SET LR1 LR12 ;;
{{ bump('LR1',127-w) }} ;;
{% endif %}
{% macro product(t) %}
{% if window %}
{% set rc = 'LR1' %}
{% elif stride == 1 %}
{% set d = (t//kw-padding)*w+t%kw-padding %}
SET LR1 LR9 ;;
{% if d//128 %}{{ bump('LR1',d//128) }} ;;{% endif %}
LD.MULT.CYCLIC LR1 {{ cr.guard }} LR0 ;;
{% if d%128 %}
LD.MULT.CYCLIC LR1 {{ cr.guard }} LR12 ; INC LR1 1 ;;
{% if d%128 == 1 %}SET LR1 CR1 ;;{% else %}SET LR1 CR0 ;; INC LR1 {{ d%128 }} ;;{% endif %}
{% set rc = 'LR1' %}
{% else %}
{% set rc = 'LR0' %}
{% endif %}
{% else %}
LD.MULT.CYCLIC LR1 {{ cr.stencil }} LR0 ; INC LR1 1 ;;
{% set rc = 'LR0' %}
{% endif %}
MULT.RC.VV {{ rc }} R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ;
{% if window and t %}INC LR1 {{ w-2 if t%kw == 0 else 1 }} ;{% endif %} ;;
{% if stride == 1 %}
MULT.RC.VV {{ rc }} R1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;;
{% endif %}
MULT.RC.VV {{ rc }} {{ 'R0' if stride == 1 else 'R1' }} 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
{% if t+1 < kh*kw %}LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;{% endif %}
{%- endmacro %}
{% for t in range(kh*kw) %}
{{ product(t) }} {% if loop.last %}ADD LR9 LR9 {{ cr.plane }} ; INC LR11 1 ; BLT.S LR11 {{ cr.gc_last }} next_input_channel ;{% endif %} ;;
{% endfor %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% if (out0_d2*out0_d3)%128 %}BEQ LR6 {{ cr.sr_last }} store_tail ;;{% endif %}
ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR2 ; INC LR2 1 ; INC LR10 {{ 1 if stride == 1 else kh*kw }} ; INC LR6 1 ; BLT.S LR6 {{ cr.sr_last }} output_row ;;
{% if (out0_d2*out0_d3)%128 %}
BEQ LR0 CR0 next_channel ;;
store_tail:
ACTIVATE.QUANTIZE {{ act }} {{ cr.tail }}.L {{ qo }} {{ cr.out0 }} LR2 ; INC LR2 1 ;;
next_channel:
{% endif %}
SET LR7 LR8 ; INC LR14 1 ; BLT.S LR14 LR13 same_group ;;
ADD LR3 LR3 LR15 ; SET LR14 CR0 ;;
same_group:
INC LR4 1 ; BLT.S LR4 LR5 output_channel ;;
HALT ;;

next_input_channel:
LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ; {% if stride == 2 %}SET LR1 LR9 ;{% endif %} BEQ LR0 CR0 input_channel ;;
