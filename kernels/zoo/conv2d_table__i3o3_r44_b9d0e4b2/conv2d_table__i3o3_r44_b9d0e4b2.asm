{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.input_tail ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% set ir = (in0_d2*w+127)//128 %}
{% set single = stride == 1 and ir == 1 %}
{% set wk = 3+3*(cin//groups)*kh*kw %}
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

# Copy spatial planes with zero guard rows. Input padding is already zero.
{% if single %}
{{ imm('LR0',0) }}
{{ imm('LR3',-1) }}
MULT.RC.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.guard }} LR3 ; INC LR3 1 ;;
{% else %}
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
{% endif %}

# Align the spatial vector for every tap, shared across output channels.
{% if stride == 2 %}
{{ imm('LR2',-1) }}
{{ imm('LR4',0) }}
{{ imm('LR13',4) }}
{{ imm('LR14',ir+10) }}
{% macro piece(d,offset,acc,last) %}
SET LR6 LR3 ; SET LR7 LR0 ;;
{% if d//128+offset %}{{ bump('LR6',d//128+offset) }} ;;{% endif %}
{% if d%128 %}
LD.MULT.CYCLIC LR6 {{ cr.guard }} LR0 ; INC LR7 {{ d%128 }} ;;
LD.MULT.CYCLIC LR6 {{ cr.guard }} LR1 ; INC LR6 1 ;;
{% else %}
LD.MULT.CYCLIC LR6 {{ cr.guard }} LR0 ;;
{% endif %}
MULT.RC.VE LR7 CR1 0 LR0 {{ ds }} {{ qi }} ; {{ acc }} ;
{% if last %}ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.stencil }} LR2 ; INC LR2 1 ;{% endif %} ;;
{% endmacro %}
{% macro tap(ky,kx) %}
{% set d = (ky-padding)*w+kx-padding %}
{% if stride == 1 %}
{{ piece(d,0,'ACC.ADD.FIRST',true) }}
{% elif w <= 64 %}
{% for p in range(4) %}
{{ imm('LR9',p) }}
{{ piece(d,p,'ACC.STRIDE '~([16,w]|max)~' on on LR9',p==3) }}
{% endfor %}
{% else %}
{{ piece(d,0,'ACC.STRIDE 64 on off LR0',false) }}
{{ imm('LR9',2) }}
{{ piece(d,2 if w==128 else 1,'ACC.STRIDE 64 on off LR9',true) }}
{% endif %}
{% endmacro %}
stage_channel:
SET LR3 LR13 ; SET LR8 CR0 ;;
stage_row:
{% for ky in range(kh) %}{% for kx in range(kw) %}
{{ tap(ky,kx) }}
{% endfor %}{% endfor %}
INC LR3 {{ stride*stride }} ; INC LR8 1 ; BLT.S LR8 {{ cr.sr_last }} stage_row ;;
ADD LR13 LR13 LR14 ; INC LR4 1 ; BLT.S LR4 LR5 stage_channel ;;
{% endif %}

{{ imm('LR2',-1) }}
{% for i in range(5) %}
LD.LUT {{ i }} {{ cr.lut }} LR2 ; INC LR2 1 ;;
{% endfor %}
{{ imm('LR2',-1) }}
{{ imm('LR3',0 if single else (4 if stride == 1 else -1)) }}
{{ imm('LR4',0) }}
{{ imm('LR5',cout-1) }}
{{ imm('LR7',-1) }}
{{ imm('LR13',cout//groups-1) }}
{{ imm('LR14',0) }}
{{ imm('LR12',128) }}
{% if single %}{{ imm('LR6',256) }}{% endif %}

output_channel:
{% if not single %}SET LR6 CR0 ;{% endif %} SET LR10 LR3 ;;
output_row:
SET LR8 LR7 ;;
{% if out0_d3>128 %}
SET LR11 LR6 ;;
INC.MODP2 LR11 CR0 1 ;;
BEQ LR11 LR0 bias_load ;;
{{ imm('LR1',wk) }}
ADD LR8 LR8 LR1 ;;
bias_load:
{% endif %}
LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ; INC LR8 1 ;;
LD.MULT.CYCLIC LR8 {{ cr.weights }} LR12 ; INC LR8 1 ;;
MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; SET LR9 LR10 ; LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ; INC LR8 1 ;;
MULT.RC.VE LR12 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; SET LR11 CR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
{% if single %}
LD.MULT.CYCLIC LR0 {{ cr.guard }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.guard }} LR6 ;;
{% endif %}
input_channel:
{% if single %}
LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR12 ;;
{% elif stride == 2 %}
SET LR1 LR9 ;;
{% endif %}
{% macro product(t) %}
{% if single %}
{% set d = (t//kw-padding)*w+t%kw-padding %}
SET LR1 LR12 ;;
{% if d %}{{ bump('LR1',d) }} ;;{% endif %}
{% set rc = 'LR1' %}
{% elif stride == 1 %}
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
LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;;
MULT.RC.VV {{ rc }} R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ;;
MULT.RC.VV {{ rc }} R1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;;
MULT.RC.VV {{ rc }} R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
{%- endmacro %}
{% for t in range(kh*kw) %}
{{ product(t) }} {% if loop.last %}ADD LR9 LR9 {{ cr.plane }} ; INC LR11 1 ; BLT.S LR11 {{ cr.gc_last }} input_channel ;{% endif %} ;;
{% endfor %}
{% if single %}
ACTIVATE.QUANTIZE {{ act }} {{ tail }} {{ qo }} {{ cr.out0 }} LR2 ; INC LR2 1 ;;
{% else %}
{% if (out0_d2*out0_d3)%128 %}BEQ LR6 {{ cr.sr_last }} store_tail ;;{% endif %}
ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR2 ; INC LR2 1 ; INC LR10 {{ 1 if stride == 1 else kh*kw }} ; INC LR6 1 ; BLT.S LR6 {{ cr.sr_last }} output_row ;;
{% if (out0_d2*out0_d3)%128 %}
BEQ LR0 CR0 next_channel ;;
store_tail:
ACTIVATE.QUANTIZE {{ act }} {{ tail }} {{ qo }} {{ cr.out0 }} LR2 ; INC LR2 1 ;;
next_channel:
{% endif %}
{% endif %}
SET LR7 LR8 ; INC LR14 1 ; BLT.S LR14 LR13 same_group ;;
ADD LR3 LR3 LR15 ; SET LR14 CR0 ;;
same_group:
INC LR4 1 ; BLT.S LR4 LR5 output_channel ;;
HALT ;;
