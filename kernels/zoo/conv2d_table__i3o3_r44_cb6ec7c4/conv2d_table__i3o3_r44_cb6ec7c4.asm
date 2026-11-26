{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set ds = cr.input_tail ~ '.L' %}
{% set ir = (in0_d2*w+127)//128 %}
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

# Stage input planes with zero rows on both sides.
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
{% macro copy(active) %}
LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ;;
MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
ACTIVATE.QUANTIZE identity {{ active }} {{ qi }} {{ cr.guard }} LR3 ; INC LR3 1 ;
{% endmacro %}
copy_channel:
{{ guard('copy_top',4) }}
SET LR8 CR0 ;;
copy_row:
{% if (in0_d2*w)%128 %}BEQ LR8 LR6 copy_last ;;{% endif %}
{{ copy(ds) }} INC LR8 1 ; BLT.S LR8 LR6 copy_row ;;
{% if (in0_d2*w)%128 %}
copy_last:
{{ copy(cr.input_tail ~ '.H') }} ;;
{% endif %}
{{ guard('copy_bottom',6) }}
INC LR4 1 ; BLT.S LR4 LR5 copy_channel ;;

# Compact stride-two taps into the output lane order, once per input plane.
{% if stride == 2 %}
{{ imm('LR2',-1) }}
{{ imm('LR4',0) }}
{{ imm('LR13',4) }}
{{ imm('LR14',ir+10) }}
{% macro piece(d,offset,acc,last) %}
SET LR6 LR3 ; SET LR7 LR0 ;;
{% if d//128+offset %}{{ bump('LR6',d//128+offset) }} ;;{% endif %}
LD.MULT.CYCLIC LR6 {{ cr.guard }} LR0 ; {% if d%128 %}INC LR7 {{ d%128 }} ;{% endif %} ;;
{% if d%128 %}LD.MULT.CYCLIC LR6 {{ cr.guard }} LR1 ; INC LR6 1 ;;{% endif %}
MULT.RC.VE LR7 CR1 0 LR0 {{ ds }} {{ qi }} ; {{ acc }} ;
{% if last %}ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.stencil }} LR2 ; INC LR2 1 ;{% endif %} ;;
{% endmacro %}
{% macro stage_tap(t) %}
{% set d = (t//kw-padding)*w+t%kw-padding %}
{% if w <= 64 %}
{% for p in range(4) %}
{{ imm('LR9',p) }}
{{ piece(d,p,'ACC.STRIDE '~w~' on on LR9',p==3) }}
{% endfor %}
{% else %}
{{ piece(d,0,'ACC.STRIDE 64 on off LR0',false) }}
{{ imm('LR9',2) }}
{{ piece(d,2,'ACC.STRIDE 64 on off LR9',true) }}
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
SET LR8 LR7 ;;
LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ; INC LR8 1 ;;
LD.MULT.CYCLIC LR8 {{ cr.weights }} LR12 ; INC LR8 1 ;;
MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; SET LR9 LR10 ; LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ; INC LR8 1 ;;
MULT.RC.VE LR12 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; SET LR11 CR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
input_channel:
{% if stride == 2 %}SET LR1 LR9 ;;{% endif %}
{% macro product(t) %}
{% if stride == 1 %}
{% set d = (t//kw-padding)*w+t%kw-padding %}
SET LR1 LR9 ;;
{% if d//128 %}{{ bump('LR1',d//128) }} ;;{% endif %}
LD.MULT.CYCLIC LR1 {{ cr.guard }} LR0 ;;
{% if d%128 %}
LD.MULT.CYCLIC LR1 {{ cr.guard }} LR12 ; INC LR1 1 ;;
SET LR1 CR0 ;;
INC LR1 {{ d%128 }} ;;
{% else %}
SET LR1 CR0 ;;
{% endif %}
{% set rc = 'LR1' %}
{% else %}
LD.MULT.CYCLIC LR1 {{ cr.stencil }} LR0 ; INC LR1 1 ;;
{% set rc = 'LR0' %}
{% endif %}
{% for p in range(3) %}
LD.MULT R{{ p%2 }} LR8 {{ cr.weights }} ; INC LR8 1 ;
{% if p %}MULT.RC.VV {{ rc }} R{{ (p-1)%2 }} 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;{% endif %} ;;
{% endfor %}
MULT.RC.VV {{ rc }} R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
{% endmacro %}
{% for t in range(kh*kw) %}
{{ product(t) }} {% if loop.last %}ADD LR9 LR9 {{ cr.plane }} ; INC LR11 1 ; BLT.S LR11 {{ cr.gc_last }} input_channel ;{% endif %} ;;
{% endfor %}
{% macro store(active) %}
ACTIVATE.QUANTIZE {{ 'generic' if act_out0 == 'silu' else act_out0 }} {{ active }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; INC LR2 1 ;
{% endmacro %}
{% if (out0_d2*out0_d3)%128 %}BEQ LR6 {{ cr.sr_last }} store_tail ;;{% endif %}
{{ store(ds) }} INC LR10 {{ 1 if stride == 1 else kh*kw }} ; INC LR6 1 ; BLT.S LR6 {{ cr.sr_last }} output_row ;;
{% if (out0_d2*out0_d3)%128 %}
BEQ LR0 CR0 next_channel ;;
store_tail:
{{ store(cr.tail ~ '.L') }} ;;
next_channel:
{% endif %}
SET LR7 LR8 ; INC LR14 1 ; BLT.S LR14 LR13 same_group ;;
ADD LR3 LR3 LR15 ; SET LR14 CR0 ;;
same_group:
INC LR4 1 ; BLT.S LR4 LR5 output_channel ;;
HALT ;;
