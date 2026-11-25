{% set dw = 1 < groups == cin == cout and w <= 128 and w % stride == 0 and (2*padding-kw)//stride+1 == 0 %}
{% set ip = 128 // w if dw else 1 %}
{% set op = ip * stride if dw else (128 // w if groups == 1 and stride == 1 and w == out0_d3 and w <= 128 else 1) %}
{% set ni = (cin+ip-1)//ip %}
{% set no = (cout+op-1)//op %}
{% set ix = (in0_d3+127)//128 %}
{% set ox = (out0_d3+127)//128 %}
{% set row = 1 if op > 1 and not dw else kw*ox %}
{% set ds = cr.ds128 ~ '.L' %}
{% set tail = cr.ds_tail ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set act = 'generic' if act_out0 in ['silu', 'hardswish', 'gelu', 'sigmoid', 'tanh'] else act_out0 %}
{% macro inc(r,n) -%}
{% if n > 0 %}INC {{ r }} {{ n }} ;{% elif n < 0 %}DEC {{ r }} {{ -n }} ;{% endif %}
{%- endmacro %}
{% macro adjust(r,n) %}
{% for a in range(0,n|abs,255) %}{{ inc(r,([255,n|abs-a]|min)*(1 if n>0 else -1)) }} ;;{% endfor %}
{% endmacro %}
{% macro set(r,n) %}
SET {{ r }} CR0 ;;
{{ adjust(r,n) }}
{% endmacro %}
{% macro zeros(label) %}
SET LR13 CR0 ;;
{{ label }}:
MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR5 ;
INC LR5 1 ; INC LR13 1 ; BLT.S LR13 LR12 {{ label }} ;;
{% endmacro %}

SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
INC LR1 128 ; INC LR2 128 ; SET LR3 CR0 ;;
INC LR2 128 ; INC LR3 192 ; SET LR5 CR0 ;;
INC LR3 192 ; DEC LR5 1 ; SET LR6 CR0 ;;
{% set piped = dw and stride==2 and w*ip==128 and ni%2==0 and in0_d2>1 %}
{{ set('LR10',in0_d2-(2 if piped else 1)) }}
{# Split two input packs into even/odd spatial phases. Prefetch the next
   row with the last multiply, then peel the final row to stay in bounds. #}
{% macro unzip(next) %}
MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ; LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR2 ; INC LR4 1 ;;
MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR13 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR5 ; INC LR5 1 ;;
MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on_inv off LR0 ;;
MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on_inv off LR13 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR5 ; INC LR5 1 ; ADD LR4 LR4 LR15 ;
{% if next %}LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ; INC LR7 1 ; BLT.S LR7 LR10 dw_stage_y ;{% endif %} ;;
{% endmacro %}
{% if dw %}
{{ set('LR12',padding*stride-1) }}
{% if stride == 2 %}
{{ set('LR8',256-w*ip) }}
{{ set('LR9',384-w*ip) }}
{{ set('LR14',no-1) }}
{{ set('LR15',ni-1) }}
{% endif %}
dw_stage:
{{ zeros('dw_top') }}
{% if stride == 1 %}
SET LR4 LR6 ; SET LR7 CR0 ;;
{% else %}
ADD LR4 LR6 LR6 ; SET LR7 CR0 ;;
{% if w*ip == 128 and ni % 2 == 0 %}
LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ; SET LR13 CR1 ;;
INC LR13 1 ;;
{% else %}
LD.MULT.CYCLIC LR0 {{ cr.pad }} LR1 ;;
LD.MULT.CYCLIC LR0 {{ cr.pad }} LR3 ;;
{% endif %}
{% endif %}
dw_stage_y:
{% if stride == 1 %}
LD.MULT R0 LR4 {{ cr.in0 }} ;;
MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR5 ; INC LR5 1 ; ADD LR4 LR4 {{ cr.no }} ; INC LR7 1 ; BLT.S LR7 LR10 dw_stage_y ;;
{% elif w*ip == 128 and ni % 2 == 0 %}
{% if piped %}{{ unzip(true) }}{% endif %}
{{ unzip(false) }}
{% else %}
LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; INC LR4 1 ; {% if ni % 2 %}BEQ LR6 LR14 dw_missing ;{% endif %} ;;
LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR2 ; {% if ni % 2 %}BEQ LR0 CR0 dw_join ;{% endif %} ;;
{% if ni % 2 %}
dw_missing:
LD.MULT.CYCLIC LR0 {{ cr.pad }} LR2 ;;
dw_join:
{% endif %}
MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;
ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR5 ; INC LR5 1 ;;
LD.MULT.CYCLIC LR5 {{ cr.pad }} LR0 ; SET LR13 CR1 ;;
INC LR13 1 ; MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
MULT.RC.VE LR9 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR13 ;
ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR5 ;;
MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on_inv off LR0 ;;
MULT.RC.VE LR9 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on_inv off LR13 ;
ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR5 ; INC LR5 1 ; ADD LR4 LR4 LR15 ; INC LR7 1 ; BLT.S LR7 LR10 dw_stage_y ;;
{% endif %}
{{ zeros('dw_bottom') }}
INC LR6 1 ;;
BLT.S LR6 {{ cr.no }} dw_stage ;;
{% else %}
{{ set('LR12',padding*row-1) }}
{{ set('LR14',(cin-1)*ix) }}
{{ set('LR11',cin-1) }}
{{ set('LR15',-1) }}
{{ set('LR9',op-2 if op>1 else 2) }}
stage_channel:
{{ zeros('top') }}
LD.MULT.CYCLIC LR0 {{ cr.pad }} LR0 ; SET LR7 CR0 ; SET LR4 LR15 ;;
LD.MULT.CYCLIC LR0 {{ cr.pad }} LR3 ;;
{% if ix == 1 %}LD.MULT.CYCLIC LR0 {{ cr.pad }} LR2 ;;{% endif %}
stage_y:
LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR1 ; INC LR4 1 ;;
{% if ix == 2 %}LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR2 ; INC LR4 1 ;;{% endif %}
{% if op > 1 %}
MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.ds_width }}.L {{ qi }} {{ cr.pad }} LR5 ; INC LR5 1 ;;
LD.MULT.CYCLIC LR5 {{ cr.pad }} LR1 ;;
SET LR8 LR1 ; SET LR13 CR0 ; DEC LR5 1 ;;
MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
replicate:
MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; DEC LR8 {{ w }} ; INC LR13 1 ; BLT.S LR13 LR9 replicate ;;
ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR5 ; INC LR5 1 ;;
{% else %}
{% macro shifted(k,x) %}
SET LR8 {{ 'LR1' if x == 0 else ('LR2' if stride == 1 and x == 1 else 'LR3') }} ;;
{% if k != padding %}{{ inc('LR8',k-padding) }} ;;{% endif %}
{% if stride == 1 %}
MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
{% else %}
MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR9 ; INC LR8 128 ;
{% endif %}
ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR5 ; INC LR5 1 ;;
{% endmacro %}
{% for k in range(kw) %}{% for x in range(ox) %}{{ shifted(k,x) }}{% endfor %}{% endfor %}
{% endif %}
INC LR7 1 ; ADD LR4 LR4 LR14 ; BLT.S LR7 LR10 stage_y ;;
{{ zeros('bottom') }}
INC LR6 1 ; INC LR15 {{ ix }} ; BLT.S LR6 LR11 stage_channel ;;
{% endif %}

{{ set('LR13',-1) }}
{% for i in range(5) %}
LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
{% endfor %}
SET LR6 CR0 ; SET LR4 CR0 ; SET LR10 CR0 ;;
DEC LR4 1 ; DEC LR10 1 ;;
{{ set('LR9',out0_d2-1) }}
{% if dw %}
dw_output:
SET LR7 CR0 ; SET LR5 LR6 ; SET LR12 LR4 ;;
SUB LR5 LR5 {{ cr.no }} ;
LD.MULT.CYCLIC LR10 {{ cr.weights }} LR0 ; INC LR10 1 ;;
LD.MULT.CYCLIC LR10 {{ cr.weights }} LR3 ; INC LR10 1 ;;
dw_y:
MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; ADD LR13 LR12 CR1 ; SET LR15 LR10 ; SET LR8 LR1 ; LD.MULT.CYCLIC LR13 {{ cr.pad }} LR1 ;;
MULT.RC.VE LR3 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R0 LR15 {{ cr.weights }} ; INC LR15 1 ;;
{% macro dw_row(first,last) %}
{% if not first %}LD.MULT.CYCLIC LR13 {{ cr.pad }} LR1 ; INC LR13 1 ; SET LR8 LR1 ;;{% endif %}
{% if stride == 2 %}LD.MULT.CYCLIC LR13 {{ cr.pad }} LR2 ; INC LR13 1 ;;{% endif %}
{% for k in range(kw) %}
{% set d = k-padding %}
{% set prev = d-1 %}
{% set delta = d//stride+128*(d%stride)-(0 if k == 0 else prev//stride+128*(prev%stride)) %}
MULT.RC.VV LR8 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R1 LR15 {{ cr.weights }} ; INC LR15 1 ; {{ inc('LR8',delta) }} ;;
MULT.RC.VV LR8 R1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
{% if not (last and k+1 == kw) %}LD.MULT R0 LR15 {{ cr.weights }} ; INC LR15 1 ;
{% else %}ACTIVATE.QUANTIZE {{ act }} {{ tail }} {{ qo }} {{ cr.out0 }} LR5 ; ADD LR5 LR5 {{ cr.no }} ; INC LR12 {{ stride*stride }} ; INC LR7 1 ; BLT.S LR7 LR9 dw_y ;{% endif %} ;;
{% endfor %}
{% endmacro %}
{% for k in range(kh) %}{{ dw_row(k==0,k+1==kh) }}{% endfor %}
SET LR10 LR15 ; ADD LR4 LR4 {{ cr.plane }} ; INC LR6 1 ;;
BLT.S LR6 {{ cr.no }} dw_output ;;
{% else %}
{{ set('LR8',(no-1)*ox) }}
{% set compact = groups == 1 and stride == 1 and w == out0_d3 == 16 %}
{# Alternate main and residual weight loads. Packed rows need only one
   input load per vertical tap. #}
{% macro dense(x) %}
MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; SET LR15 LR4 ; SET LR11 LR10 ;;
MULT.RC.VE LR3 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ; SET LR12 CR0 ; {{ inc('LR15',x) }} ;;
channel_{{ x }}:
ADD LR13 LR15 CR1 ; LD.MULT.CYCLIC LR13 {{ cr.pad }} {{ 'LR1' if op>1 else 'LR0' }} ;
{% if op>1 %}SET LR14 LR1 ;{% endif %} ;;
{% for t in range(kh*kw) %}
{% set paired = not compact or t//kw == kh//2 %}
{% set rc = 'LR14' if op>1 else 'LR0' %}
{% set shift = (t%kw-padding if t==0 else (1-kw if t%kw==0 else 1)) if op>1 else 0 %}
{% if paired %}
MULT.RC.VV {{ rc }} R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R1 LR11 {{ cr.weights }} ; INC LR11 1 ; {{ inc('LR14',shift) }} {% if t==0 %}ADD LR15 LR15 {{ cr.plane }} ;{% endif %} ;;
{% endif %}
MULT.RC.VV {{ rc }} {{ 'R1' if paired else 'R0' }} 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {% if not paired %}{{ inc('LR14',shift) }} {% if t==0 %}ADD LR15 LR15 {{ cr.plane }} ;{% endif %}{% endif %}
{% if t+1 < kh*kw %}
{% if op>1 %}
LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ;;
{% if (t+1)%kw==0 %}LD.MULT.CYCLIC LR13 {{ cr.pad }} LR1 ; INC LR13 1 ;;{% endif %}
{% else %}
LD.MULT.CYCLIC LR13 {{ cr.pad }} LR0 ; INC LR13 {{ ox }} ;;
LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ;;
{% endif %}
{% else %}
INC LR12 1 ; LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ; BLT.S LR12 {{ cr.gc_last }} channel_{{ x }} ;;
{% endif %}
{% endfor %}
ACTIVATE.QUANTIZE {{ act }} {{ tail if x+1==ox else ds }} {{ qo }} {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endmacro %}
{% if groups>1 %}{{ set('LR1',cout//groups) }}{% endif %}
dense_output:
SET LR7 CR0 ; {% if ox==1 %}SET LR5 LR6 ;{% else %}ADD LR5 LR6 LR6 ;{% endif %} ;;
{% if ox==3 %}ADD LR5 LR5 LR6 ;;{% endif %}
DEC LR5 1 ;;
{{ set('LR2',256) }}
LD.MULT.CYCLIC LR10 {{ cr.weights }} LR2 ; INC LR10 1 ;;
LD.MULT.CYCLIC LR10 {{ cr.weights }} LR3 ; INC LR10 1 ;;
dense_y:
{% for x in range(ox) %}{{ dense(x) }}{% endfor %}
ADD LR5 LR5 LR8 ; INC LR7 1 ; INC LR4 {{ stride*row }} ; BLT.S LR7 LR9 dense_y ;;
SET LR10 LR11 ; INC LR6 1 ;;
{% if groups==1 %}
SET LR4 CR0 ;;
DEC LR4 1 ; BLT.S LR6 {{ cr.no }} dense_output ;;
{% else %}
BLT.S LR6 LR1 same_group ;;
SET LR4 LR15 ;;
{{ adjust('LR4',-((out0_d2-1)*stride*row+ox-1)) }}
{{ adjust('LR1',cout//groups) }}
BLT.S LR6 {{ cr.no }} dense_output ;;
HALT ;;
same_group:
{{ adjust('LR4',-out0_d2*stride*row) }}
BEQ LR0 CR0 dense_output ;;
{% endif %}
{% endif %}
HALT ;;
