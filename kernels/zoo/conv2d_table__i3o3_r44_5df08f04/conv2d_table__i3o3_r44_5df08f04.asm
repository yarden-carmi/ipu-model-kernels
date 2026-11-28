{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set ds = cr.input_tail ~ '.L' %}
{% set ir = (in0_d2*w+127)//128 %}
{% set window = stride == 1 and w <= 128 %}
{% set fast = stride == 2 and w == 256 and groups == 1 and cin <= 3 %}
{% set gc = cin//groups %}
{% set first = (-w-1)//128 %}
{% set parts = 2 %}
{% set compact = stride == 1 and w in [8,16,32] and groups == 1 and gc > 1 %}
{% set short_bias = stride == 1 and w == 64 and gc == 1 %}
{% set direct = stride == 1 and w in [64,128] and gc == 1 and (in0_d2*w)%128 == 0 and ir >= 3 and in0_d2 == out0_d2 %}
{% set packed64 = direct and w == 64 %}
{% set half_plane = stride == 2 and gc == 1 and w == 16 and in0_d2 == 16 and out0_d2 == in0_d2//2 and out0_d3 == w//2 %}
{% set scalar_dw = stride == 2 and gc == 1 and in0_d2*w%128 == 0 and out0_d2*out0_d3%128 == 0 and out0_d3 in [16,32,64] %}
{% set wk = 3-short_bias+parts*gc*kh*kw %}
{% set dw_window = window and gc==1 %}
{% set fused_store = dw_window and (out0_d2*out0_d3)%128 == 0 %}
{% macro bump(r,n) %}
{% if n>0 %}INC {{ r }} {{ n }} ;{% elif n<0 %}DEC {{ r }} {{ -n }} ;{% endif %}
{% endmacro %}
{% macro store(active) %}
ACTIVATE.QUANTIZE {{ 'generic' if act_out0 == 'silu' else act_out0 }} {{ active }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; INC LR2 1 ;
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

# Copy input planes between zero guards for cyclic reads at the top and bottom.
{% if not direct and not half_plane %}
{{ imm('LR0',0) }}
{{ imm('LR1',128) }}
{{ imm('LR2',-1) }}
{{ imm('LR3',-1) }}
{{ imm('LR4',0) }}
{{ imm('LR5',cin-1) }}
{{ imm('LR6',ir-2 if (in0_d2*w)%128 == 0 and ir > 1 else ir-1) }}
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
{{ guard('copy_top',2 if dw_window and w == 64 else 4) }}
{% if (in0_d2*w)%128 == 0 and ir > 1 %}
SET LR8 CR0 ; LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ;;
copy_row:
MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.guard }} LR3 ; INC LR3 1 ; INC LR8 1 ; BLT.S LR8 LR6 copy_row ;;
MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.guard }} LR3 ; INC LR3 1 ;;
{% else %}
SET LR8 CR0 ;;
copy_row:
{% if (in0_d2*w)%128 %}BEQ LR8 LR6 copy_last ;;{% endif %}
{{ copy(ds) }} INC LR8 1 ; BLT.S LR8 LR6 copy_row ;;
{% if (in0_d2*w)%128 %}
copy_last:
{{ copy(cr.input_tail ~ '.H') }} ;;
{% endif %}
{% endif %}
{{ guard('copy_bottom',2 if dw_window and w == 64 else 6) }}
INC LR4 1 ; BLT.S LR4 LR5 copy_channel ;;
{% if compact %}{{ guard('copy_lookahead',ir+6) }}{% endif %}
{% else %}
{{ imm('LR0',0) }}
{{ imm('LR3',-1) }}
MULT.RC.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.guard }} LR3 ; INC LR3 1 ;;
{% endif %}

# Compact stride-two input taps into the output's spatial lane order.
# For scalar depthwise taps, stage the even and odd columns only. The left
# tap is the odd row shifted by one lane, with each scanline's first lane masked.
{% if half_plane %}
# The 16x16 plane occupies two banks. Keep zeros on either side and
# decimate two shifted windows per tap into the 64 live output lanes.
{{ imm('LR2',-1) }}
{{ imm('LR3',-1) }}
{{ imm('LR4',1) }}
{{ imm('LR5',cin-1) }}
{{ imm('LR6',0) }}
{{ imm('LR10',256) }}
{{ imm('LR11',384) }}
{{ imm('LR12',128) }}
LD.MULT.CYCLIC LR0 {{ cr.guard }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.guard }} LR11 ;;
half_plane_channel:
LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR12 ; INC LR3 1 ; SET LR7 CR0 ;;
LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR10 ; INC LR3 1 ; DEC LR7 17 ;;
{% for t in range(9) %}
MULT.RC.VE LR7 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 16 on on LR0 ; {% if loop.first %}INC LR7 128 ;{% else %}DEC LR7 {{ 114 if t%3==0 else 127 }} ;{% endif %} ;;
MULT.RC.VE LR7 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 16 on on LR4 ; ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ qi }} {{ cr.stencil }} LR2 ; INC LR2 1 ; INC LR7 128 ;
{% if loop.last %}BLT.S LR6 LR5 half_plane_channel ; INC LR6 1 ;{% endif %} ;;
{% endfor %}
{% elif stride == 2 %}
{{ imm('LR2',-1) }}
{{ imm('LR4',0) }}
{{ imm('LR13',4+(-w-1)//128+(1 if w==128 else 0)) }}
{{ imm('LR14',ir+10) }}
{{ imm('LR9',-1 if w <= 64 else -2) }}
{{ imm('LR10',256) }}
{{ imm('LR11',384) }}
{% macro stage_tap(t) %}
{% set right = w >= 128 and t%kw == 2 %}
{% set d = (t//kw-padding)*w+(0 if right else t%kw-padding) %}
{% set next = (1 if t==8 else t+1+(1 if t%3==2 else 0)) if scalar_dw else (t+1)%(kh*kw) %}
{% set nd = (next//kw-padding)*w+(0 if w>=128 and next%kw==2 else next%kw-padding) %}
{% set n = 4 if w <= 64 else 2 %}
{% set step = 2 if w == 128 else 1 %}
{% set overlap = d%128 and w != 128 %}
{% set start = 1 if d%128 and w == 128 else 0 %}
{% set banks = ['LR0','LR1','LR10','LR11'] %}
{% set prev = t-1-(1 if scalar_dw and t%3==1 else 0) %}
{% set pd = (prev//kw-padding)*w+(0 if w>=128 and prev%kw==2 else prev%kw-padding) %}
{% set opt = w == 128 and not fast %}
{% set delta = (d%128-128-(pd%128+128*(n-1) if t != (1 if scalar_dw else 0) else 0)+256)%512-256 %}
{% set advance = nd//128+(1 if nd%128 and w==128 else 0)-d//128-start+(4 if t==8 else 0) %}
{% if fast and t%kw==0 %}
INC LR2 1 ; INC LR3 1 ; {{ bump('LR7', (d%128+128-(pd%128+128 if t else 0)+256)%512-256) }} ;;
{% else %}
LD.MULT.CYCLIC LR6 {{ cr.guard }} {{ banks[start] }} ; SET LR6 LR3 ; {% if not opt %}{% if delta == -256 %}ADD LR7 LR7 LR10 ;{% else %}{{ bump('LR7',delta) }}{% endif %} {{ bump('LR3',advance) }}{% endif %} ;;
{% if overlap %}LD.MULT.CYCLIC LR6 {{ cr.guard }} LR1 ; INC LR6 1 ;;{% endif %}
{% for p in range(n) %}
MULT.RC.VE LR7 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE {{ [16,[w,64]|min]|max }} {{ 'on_inv' if right else 'on' }} {{ 'on' if w <= 64 else 'off' }} {{ ('LR0' if p == 0 else 'LR9') if opt else 'LR9' }} ; {% if opt and loop.first %}{% set change = (delta+128+256)%512-256 %}{% if change == -256 %}ADD LR7 LR7 LR10 ;{% else %}{{ bump('LR7',change) }}{% endif %} {{ bump('LR3',advance) }}{% else %}INC LR7 128 ;{% endif %} {% if not opt %}INC LR9 {{ 1 if w <= 64 else 2 }} ;{% endif %}
{% if loop.last %}ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.stencil }} LR2 ; INC LR2 {{2 if scalar_dw and t%3==1 else 1}} ;
{% else %}LD.MULT.CYCLIC LR6 {{ cr.guard }} {{ banks[(p+1+(1 if overlap else 0)+start)%4] }} ; INC LR6 {{ step }} ;{% endif %} {% if not (opt and loop.last and t < kh*kw-1) %};;{% endif %}
{% endfor %}
{% endif %}
{% endmacro %}
stage_channel:
SET LR3 LR13 ; SET LR6 LR13 ; SET LR8 CR0 ;;
SET LR7 CR0 ;;
stage_row:
{% for t in range(kh*kw) if not scalar_dw or t%3!=0 %}{{ stage_tap(t) }}{% endfor %}
SET LR7 CR0 ; INC LR8 1 ; BLT.S LR8 {{ cr.sr_last }} stage_row ;;
ADD LR13 LR13 LR14 ; INC LR4 1 ; BLT.S LR4 LR5 stage_channel ;;
{% endif %}

{{ imm('LR2',-1) }}
{% for i in range(5) %}
LD.LUT {{ i }} {{ cr.lut }} LR2 ; INC LR2 1 ;;
{% endfor %}
{% if direct and not packed64 %}
{# Full spatial lanes; keep the three scanlines in a rolling cyclic window. #}
{{ imm('LR2',-1) }}
{{ imm('LR5',cout-1) }}
{{ imm('LR9',-1) }}
{{ imm('LR12',128) }}
{{ imm('LR15',256) }}
SET LR14 {{ cr.sr_last }} ; DEC LR8 1 ;;
DEC LR14 2 ;;
wide_channel:
LD.MULT.CYCLIC LR0 {{ cr.guard }} LR0 ; SET LR6 CR0 ; SET LR11 LR12 ;;
LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR12 ; INC LR9 1 ;;
LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR15 ; INC LR9 1 ; ADD LR13 LR12 LR15 ;;
LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ; ADD LR7 LR8 CR1 ;;
{% macro wide_row(mode) %}
MULT.VE LR0 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD.FIRST ; LD.MULT R0 LR8 {{cr.weights}} ; INC LR8 1 ; SUB LR1 LR11 LR12 ;;
MULT.VE LR0 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; LD.MULT R0 LR8 {{cr.weights}} ; INC LR8 1 ; DEC LR1 1 ;;
{% for t in range(9) %}
{% for p in range(1 if t in [1,4,7] else 2) %}
MULT.RC.VV LR1 R0 0 LR0 {{ds}} {{qw}} ; ACC.ADD ;
{% if t and loop.first %}INC LR1 {{126 if t%3==0 else 1}} ;{% endif %}
{% if t == 8 and loop.last %}
{{store(ds)}}
{% if mode != 'last' %}LD.MULT R0 LR7 {{cr.weights}} ; SET LR8 LR7 ; {% endif %}
{% if mode == 'middle' %}BLT.S LR6 LR14 wide_middle ; INC LR6 1 ;{% endif %}
{% else %}
LD.MULT R0 LR8 {{cr.weights}} ; INC LR8 1 ;
{% if t == 0 and loop.first %}INC.MODP2 LR13 LR12 9 ;{% endif %}
{% if t == 1 and loop.first %}INC.MODP2 LR11 LR12 9 ;{% endif %}
{% endif %} ;;
{% endfor %}
{% endfor %}
{% endmacro %}
wide_middle:
LD.MULT.CYCLIC LR9 {{cr.in0}} LR13 ; INC LR9 1 ;;
{{wide_row('middle')}}
LD.MULT.CYCLIC LR0 {{cr.guard}} LR13 ;;
{{wide_row('penultimate')}}
{{wide_row('last')}}
INC LR4 1 ; BLT.S LR4 LR5 wide_channel ;;
HALT ;;
{% elif short_bias or direct %}
{{ imm('LR2',-1) }}
{{ imm('LR3',-1 if direct else 2) }}
{{ imm('LR4',0) }}
{{ imm('LR5',cout-1) }}
{{ imm('LR7',0) }}
{{ imm('LR12',128) }}
{{ imm('LR10',256) }}
SET LR14 {{ cr.sr_last }} ;;
{% if direct %}DEC LR14 1 ; {% if not packed64 %}DEC LR15 10 ;{% endif %}{% else %}INC LR14 1 ;{% endif %} ;;
{% if packed64 %}
{{ imm('LR15',65) }}
{{ imm('LR10',384) }}
LD.MULT.CYCLIC LR0 {{ cr.guard }} LR0 ; SET LR9 LR3 ; SET LR11 LR12 ; SET LR13 LR12 ;;
LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR11 ; INC LR9 1 ; INC.MODP2 LR13 LR12 9 ;;
LD.MULT.CYCLIC LR7 {{ cr.weights }} LR10 ; SET LR8 LR7 ;;
LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ;;
{% endif %}
short_channel:
{% if packed64 %}
# The drain has already prefetched the first packed row.
LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR13 ; INC LR9 1 ; ADD LR8 LR7 CR1 ; SET LR6 CR0 ;;
{% elif direct %}
LD.MULT.CYCLIC LR0 {{ cr.guard }} LR0 ; SET LR6 CR0 ; SET LR9 LR3 ; SET LR11 LR12 ;;
LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR12 ; INC LR9 1 ; {% if packed64 %}ADD LR13 LR12 LR12 ; SET LR8 LR7 ;{% endif %} ;;
LD.MULT.CYCLIC LR9 {{ cr.in0 }} {{ 'LR13' if packed64 else 'LR10' }} ; INC LR9 1 ; {% if not packed64 %}SET LR13 LR10 ;{% endif %} ;;
{% else %}
SET LR6 CR0 ; SET LR9 LR3 ; SET LR11 LR12 ;;
DEC LR9 2 ;;
LD.MULT.CYCLIC LR9 {{ cr.guard }} LR0 ; INC LR9 1 ;;
LD.MULT.CYCLIC LR9 {{ cr.guard }} LR12 ; INC LR9 1 ;;
LD.MULT.CYCLIC LR9 {{ cr.guard }} LR10 ; INC LR9 1 ; SET LR13 LR10 ;;
{% endif %}
{% if not packed64 %}LD.MULT R1 LR7 {{ cr.weights }} ; SET LR8 LR7 ;;{% endif %}
{% macro short_body(last,end=false) %}
{% if packed64 %}
# Bias is a product of a cyclic vector and an R1 scalar. R1 also holds
# two middle-column tap residuals, freeing load slots for input and R1 prefetch.
MULT.RC.VE LR10 LR12 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; SUB LR1 LR11 LR15 ; LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;;
{% for t in range(9) %}
{% for p in range(2) %}
{% if end and t == 4 and loop.last %}drain_prefetched:{% endif %}
{% if t in [4,7] and p == 1 %}MULT.RC.VE LR1 LR10 0 LR0 {{ ds }} {{ qw }} {% else %}MULT.RC.VV LR1 R0 0 LR0 {{ ds }} {{ qw }} {% endif %}; ACC.ADD ;
{% if t and loop.first %}INC LR1 {{ 62 if t%3 == 0 else 1 }} ;{% endif %}
{% if t == 8 and loop.last %}
# Prefetch the bias factor into the bank no longer needed by this row.
LD.MULT.CYCLIC LR7 {{ cr.weights }} LR10 ; INC.MODP2 LR10 LR12 9 ; {% if end %}INC LR4 1 ; BLT.S LR4 LR5 short_channel ;{% else %}ADD LR8 LR7 CR1 ; {% if not last %}BLT.S LR6 LR14 short_row ;{% endif %}{% endif %} {{ store(ds) }}
{% else %}
{% if t == 4 and p == 0 %}
{% if end %}LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR13 ;
{% elif last %}LD.MULT.CYCLIC LR0 {{ cr.guard }} LR13 ;{% else %}LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR13 ;{% endif %}
{% elif t == 7 and p == 1 %}
{% if end %}LD.MULT R1 LR6 {{ cr.weights }} ; INC LR6 1 ;{% else %}INC.MODP2 LR11 LR12 9 ;{% endif %}
{% else %}
LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;
{% endif %}
{% if t == 0 and loop.first %}INC.MODP2 LR13 LR12 9 ; SET LR10 LR12 ;{% endif %}
{% if t == 1 and loop.last %}INC LR10 1 ;{% endif %}
{% if t == 2 and not loop.first %}{% if not last or end %}INC LR9 1 ;{% endif %} INC LR6 1 ;{% endif %}
{% if end and t == 3 and loop.last %}INC LR7 18 ; BEQ LR4 LR5 drain_final ;{% endif %}
{% if t == 5 and loop.last %}INC LR10 1 ;{% endif %}
{% if end and t == 5 and loop.last %}SET LR6 LR7 ;{% endif %}
{% if end and t == 6 and loop.first %}SET LR11 LR13 ;{% endif %}
{% if end and t == 6 and loop.last %}INC.MODP2 LR13 LR12 9 ;{% endif %}
{% if t == 8 and p == 0 %}SET LR10 LR13 ;{% endif %}
{% endif %} ;;
{% endfor %}
{% endfor %}
{% else %}
MULT.VE LR12 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; SET LR1 LR11 ; LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;;
MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; DEC LR1 {{ w+1 }} ; LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;;
{% for t in range(4) %}
MULT.RC.VV LR1 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ; {% if t %}INC LR1 {{ 1 if t%3 else w-2 }} ;{% else %}INC.MODP2 LR13 LR12 9 ;{% endif %} ;;
MULT.RC.VV LR1 R1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;;
{% endfor %}
MULT.RC.VV LR1 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR1 1 ; LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ;;
MULT.RC.VE LR1 LR12 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;;
{% for t in [5,6] %}
MULT.RC.VV LR1 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR1 {{ 1 if t == 5 else w-2 }} ; LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;;
MULT.RC.VV LR1 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ; {% if t == 6 %}INC LR6 1 ; INC LR9 1 ;{% endif %} ;;
{% endfor %}
MULT.RC.VV LR1 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR1 1 ; SUB LR10 LR10 LR12 ; LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;;
MULT.RC.VE LR1 LR10 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR10 1 ; LD.MULT R1 LR7 {{ cr.weights }} ; INC.MODP2 LR11 LR12 9 ;;
MULT.RC.VV LR1 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR1 1 ; LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;;
MULT.RC.VV LR1 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; SET LR8 LR7 ; ADD LR10 LR12 LR12 ; {% if direct and last %}LD.MULT.CYCLIC LR0 {{ cr.guard }} LR13 ;{% else %}LD.MULT.CYCLIC LR9 {{ cr.in0 if direct else cr.guard }} LR13 ;{% endif %} {{ store(ds) }} {% if not last %}BLT.S LR6 LR14 short_row ;{% endif %} ;;
{% endif %}
{% endmacro %}
short_row:
{{ short_body(false) }}
{% if direct %}{{ short_body(true) }}{{ short_body(true,packed64) }}{% endif %}
{% if not packed64 %}INC LR7 {{ 1+2*kh*kw }} ; ADD LR3 LR3 LR15 ; INC LR4 1 ; BLT.S LR4 LR5 short_channel ;;
{% endif %}
HALT ;;
{% if packed64 %}
drain_final:
MULT.RC.VV LR1 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR1 1 ; BEQ LR0 CR0 drain_prefetched ;;
{% endif %}
{% else %}
{{ imm('LR2',-1) }}
{{ imm('LR3',(2 if dw_window and w == 64 else 4) if stride == 1 else -1) }}
{{ imm('LR4',0) }}
{{ imm('LR5',cout-1) }}
{{ imm('LR7',-1) }}
{{ imm('LR13',cout//groups-1) }}
{{ imm('LR14',0) }}
{{ imm('LR12',128) }}
{% if fast %}{{ imm('LR15',256) }}{% endif %}
{% if scalar_dw %}{{ imm('LR13',1) }}{{ imm('LR14',127) }}{% endif %}
{% if compact %}{{ imm('LR13',256) }}{% endif %}

output_channel:
SET LR6 CR0 ; SET LR10 LR3 ;;
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
MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; SET LR9 LR10 ; {% if short_bias %}LD.MULT R0 LR8 {{ cr.weights }} ;{% else %}LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ;{% endif %} INC LR8 1 ;;
{% if short_bias %}
MULT.RC.VE LR12 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; SET LR11 CR0 ; LD.MULT.CYCLIC LR9 {{ cr.guard }} LR0 ; {{ bump('LR9',first) }} ;;
{% else %}
MULT.RC.VE LR12 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; SET LR11 {{ 'CR1' if fast else 'CR0' }} ; {% if dw_window %}LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;{% elif fast %}LD.MULT.CYCLIC LR9 {{ cr.stencil }} LR12 ; INC LR9 3 ; SET LR14 LR12 ;{% endif %} ;;
MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {% if dw_window %}LD.MULT.CYCLIC LR9 {{ cr.guard }} LR0 ; {{ bump('LR9',first) }}{% else %}LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;{% endif %} ;;
{% endif %}
{% if scalar_dw %}
LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ; SET LR1 LR9 ; SET LR11 CR0 ;;
LD.MULT.CYCLIC LR1 {{ cr.stencil }} LR12 ; INC LR1 3 ;;
{% for t in range(9) %}
{% set bank = ['LR14','LR0','LR12'][t%3] %}
{% set mask = 'LR13' if t%3 == 0 else 'LR0' %}
MULT.RC.VE {{ bank }} LR11 0 {{ mask }} {{ cr.input_tail }}.H {{ qw }} ; ACC.ADD ; {% if t %}DEC LR11 127 ;{% endif %} {% if t%3==0 %}LD.MULT.CYCLIC LR1 {{ cr.stencil }} LR0 ; DEC LR1 1 ;{% elif loop.last %}INC LR10 9 ;{% endif %} ;;
MULT.RC.VE {{ bank }} LR11 0 {{ mask }} {{ cr.input_tail }}.H {{ qw }} ; ACC.ADD ; INC LR11 128 ; {% if loop.last %}{{ store(ds) }} INC LR6 1 ; BLT.S LR6 {{ cr.sr_last }} output_row ;{% elif t%3==2 %}LD.MULT.CYCLIC LR1 {{ cr.stencil }} LR12 ; INC LR1 4 ;{% endif %} ;;
{% endfor %}
{% elif fast %}
{% for ch in range(cin) %}
{% if loop.first %}LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ; SET LR1 LR9 ; SET LR13 CR0 ;;{% endif %}
{% for t in range(kh*kw) %}
{% set rc = 'LR14' if t%kw==0 else (('LR15' if ch and t==2 else 'LR12') if t%kw==2 else 'LR0') %}
MULT.RC.VE {{ rc }} LR13 0 {{ 'LR11' if t%kw == 0 else 'LR0' }} {{ ds }} {{ qw }} ; ACC.ADD ; {% if t %}DEC LR13 127 ;{% elif ch %}DEC LR13 {{ 128+kh*kw-1 }} ;{% endif %}
{% if t==0 %}{{ bump('LR14',128 if ch else -1) }}{% elif t==1 and ch %}DEC LR14 128 ;{% endif %}
{% if t==6 and ch<cin-1 %}ADD LR9 LR9 {{ cr.plane }} ;{% endif %}
{% if t==7 and ch<cin-1 %}LD.MULT.CYCLIC LR9 {{ cr.stencil }} LR15 ;;{% else %}
{% if loop.last and ch<cin-1 %}LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;{% endif %} ;;
{% endif %}
MULT.RC.VE {{ rc }} LR13 0 {{ 'LR11' if t%kw == 0 else 'LR0' }} {{ ds }} {{ qw }} ; ACC.ADD ;
{% if not loop.last %}INC LR13 128 ;{% if t%kw == 0 %}LD.MULT.CYCLIC LR1 {{ cr.stencil }} LR0 ; DEC LR1 1 ;{% elif t%kw == 2 %}LD.MULT.CYCLIC LR1 {{ cr.stencil }} LR12 ; INC LR1 4 ;{% endif %}
{% else %}INC LR13 128 ;{% if ch < cin-1 %}LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ; SET LR1 LR9 ;{% endif %}{% endif %} ;;
{% endfor %}
{% endfor %}
{% else %}
{% for ch in range(cin//groups if stride == 2 and 1 < cin//groups <= 3 else 1) %}
{% if loop.first %}input_channel:{% endif %}
{% if stride == 2 %}SET LR1 LR9 ;;{% endif %}
{% if compact %}
# Refill cyclic banks once the packed center taps have finished using them.
{% macro load_bank(bank) %}LD.MULT.CYCLIC LR9 {{ cr.guard }} {{ bank }} ; INC LR9 1 ;{% endmacro %}
DEC LR9 2 ;;
{{ load_bank('LR0') }} ;;
{{ load_bank('LR12') }} SET LR15 LR12 ;;
{{ load_bank('LR13') }} ;;
DEC LR9 1 ;;
packed_channel:
{% for t in [0,2,3,5,6,8] %}
MULT.RC.VV LR15 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ; {% if loop.first %}DEC LR9 1 ; DEC LR15 {{ w+1 }} ;{% else %}INC LR15 {{ 2 if t%3 == 2 else w-2 }} ;{% endif %} ;;
MULT.RC.VV LR15 R1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ; {% if loop.last %}SET LR1 CR0 ;{% endif %} ;;
{% endfor %}
{% for t in range(3) %}
MULT.RC.VE LR15 LR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {{ bump('LR15',[-2*w-1,2*w,-w][t]) }} {% if not t %}LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ;{% else %}DEC LR1 127 ; {% if loop.last %}LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;{% endif %}{% endif %} ;;
MULT.RC.VE LR15 LR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR9 {{ cr.guard }} {{ ['LR0','LR13','LR12'][t] }} ; INC LR1 128 ; {% if not t %}ADD LR9 LR9 {{ cr.plane }} ;{% elif not loop.last %}INC LR9 2 ;{% else %}DEC LR9 1 ; INC LR11 1 ; BLT.S LR11 {{ cr.gc_last }} packed_channel ;{% endif %} ;;
{% endfor %}
{% elif window %}
# Keep the contiguous spatial window resident across all nine taps.
{% set last = 1 %}
{% for bank in range(last-first+1) %}
{% if bank or not dw_window %}LD.MULT.CYCLIC LR9 {{ cr.guard }} {{ 'LR0' if not bank else 'LR1' }} ; {{ bump('LR9',1 if bank else first) }} {% if bank==1 %}SET LR1 LR12 ;{% elif bank %}INC LR1 128 ;{% endif %} ;;{% endif %}
{% endfor %}
{% endif %}
{% if not compact %}
{% macro product(t) %}
{% if window %}
{% set rc = 'LR1' %}
{% if w == 128 and t == 6 %}
LD.MULT.CYCLIC LR9 {{ cr.guard }} LR0 ; INC LR9 2 ;;
DEC LR9 2 ;;
{% endif %}
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
MULT.RC.VV {{ rc }} R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {% if parts > 1 %}LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ;{% endif %}
{% if window %}{% if not t %}DEC LR9 1 ; {{ bump('LR1',255 if w==128 else -129-w) }}{% else %}INC LR1 {{ 1 if t%kw else w-2 }} ;{% endif %}{% endif %} {% if parts > 1 %};;{% endif %}
{% if parts == 3 %}
MULT.RC.VV {{ rc }} R1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;;
MULT.RC.VV {{ rc }} R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
{% elif parts == 2 %}
MULT.RC.VV {{ rc }} R1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
{% endif %}
{% if t+1 < kh*kw or (window and gc>1) %}LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;{% endif %}
{% endmacro %}
{% for t in range(kh*kw) %}
{{ product(t) }} {% if loop.last %}{% if fused_store %}{{ store(ds) }} INC LR10 1 ; INC LR6 1 ; BLT.S LR6 {{ cr.sr_last }} output_row ;{% elif stride == 2 and 1 < gc <= 3 %}{% if ch < gc-1 %}ADD LR9 LR9 {{ cr.plane }} ; LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;{% endif %}{% elif gc > 1 %}ADD LR9 LR9 {{ cr.plane }} ; INC LR11 1 ; BLT.S LR11 {{ cr.gc_last }} {{ 'input_channel' if window else 'next_input_channel' }} ;{% endif %}{% endif %} ;;
{% endfor %}
{% endif %}
{% endfor %}
{% endif %}
{% if window and gc>1 %}DEC LR8 1 ;;{% endif %}
{% if not fused_store and not scalar_dw %}
{% if (out0_d2*out0_d3)%128 %}BEQ LR6 {{ cr.sr_last }} store_tail ;;{% endif %}
{{ store(ds) }} INC LR10 {{ 1 if stride == 1 else kh*kw }} ; INC LR6 1 ; BLT.S LR6 {{ cr.sr_last }} output_row ;;
{% if (out0_d2*out0_d3)%128 %}
BEQ LR0 CR0 next_channel ;;
store_tail:
{{ store(cr.tail ~ '.L') }} ;;
next_channel:
{% endif %}
{% endif %}
{% if scalar_dw %}
SET LR7 LR8 ; ADD LR3 LR3 LR15 ; INC LR4 1 ; BLT.S LR4 LR5 output_channel ;;
{% elif fast %}
SET LR7 LR8 ; INC LR4 1 ; BLT.S LR4 LR5 output_channel ;;
{% else %}
SET LR7 LR8 ; INC LR14 1 ; BLT.S LR14 LR13 same_group ;;
ADD LR3 LR3 LR15 ; SET LR14 CR0 ;;
same_group:
INC LR4 1 ; BLT.S LR4 LR5 output_channel ;;
{% endif %}
HALT ;;

{% if not window and not fast and gc > 1 and not (stride == 2 and gc <= 3) %}
next_input_channel:
LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ; BEQ LR0 CR0 input_channel ;;
{% endif %}
{% endif %}
