{% set H = in0_d2 %}
{% set ni = cin // groups %}
{% set no = cout // groups %}
{% set pack = [1,(128//out0_d2)//((4 if out0_d2 < 64 else 2) if stride == 2 else 1)]|max %}
{% set nx = (out0_d3+pack-1)//pack %}
{% set phases = 2 if H == 256 and stride == 1 else 1 %}
{% set tiles = nx*phases %}
{% set ir = ((in0_d3+[1,128//H]|max-1)//([1,128//H]|max)) * (2 if H==256 else 1) %}
{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% macro num(r,n) %}
SET {{r}} CR0 ;;
{% for k in range(0,n|abs,255) %}
{{'INC' if n>0 else 'DEC'}} {{r}} {{[255,n|abs-k]|min}} ;;
{% endfor %}
{% endmacro %}
{% macro guarded(slot,delta,name,cond='',bound='') %}
{% if cond %}
{{cond}} LR10 {{bound}} zero_{{name}} ;;
{% endif %}
SET LR6 LR5 ;;
{% if delta %}{{'INC' if delta>0 else 'DEC'}} LR6 {{delta|abs}} ;;{% endif %}
LD.MULT.CYCLIC LR6 {{cr.in0}} {{slot}} {% if cond %}; BEQ CR0 CR0 loaded_{{name}}{% endif %} ;;
{% if cond %}
zero_{{name}}:
LD.MULT.CYCLIC LR0 {{cr.pad}} {{slot}} ;;
loaded_{{name}}:
{% endif %}
{% endmacro %}
{% macro tap(s,dy,dx,half=0) %}
{% set offset = (128 + dy + (0 if H==256 else dx*H) + 128*half) % 512 %}
{{num('LR12',offset)}}
LD.MULT R0 LR8 {{cr.masks}} ; INC LR8 1 ;;
MULT.RC.VV LR12 R0 0 LR0 {{ds}} {{qi}} ;
{% if stride == 1 %}
ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR9 ; INC LR9 1 ;;
{% else %}
ACC.STRIDE {{[16,[H,64]|min]|max}} on {{'on' if H<=64 else 'off'}} {{'LR2' if half == 0 else 'LR3'}}
{% if H != 256 or half == 1 %}; ACTIVATE.QUANTIZE identity {{cr.dsout}}.L {{qi}} {{cr.pad}} LR9 ; INC LR9 1{% endif %} ;;
{% endif %}
{% endmacro %}

{{num('LR0',0)}}
{{num('LR1',128)}}
{{num('LR2',256)}}
{{num('LR3',384)}}
MULT.VE LR0 CR0 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR0 ;;
{% if stride == 2 and H == 256 %}
SET LR2 CR0 ; SET LR3 CR0 ;;
INC LR3 2 ; INC LR2 0 ;;
{% endif %}
{{num('LR7',-1)}}
{{num('LR9',0)}}
{{num('LR4',0)}}
{{num('LR10',0)}}
{{num('LR13',nx-1)}}
{{num('LR15',cin-1)}}
stage_x:
{% macro stage(phase) %}
SET LR5 LR4 ; SET LR11 CR0 ;;
{% if phase %}INC LR5 1 ;;{% endif %}
stage_c{{phase}}:
SET LR8 LR7 ;;
{% if H != 256 %}
{{guarded('LR0',-1,'prev','BEQ','CR0')}}
{{guarded('LR1',0,'center')}}
{% if stride == 2 and H==128 %}
{% set lastnext = nx-1+(1 if in0_d3 % 2 == 0 else 0) %}
{{num('LR14',lastnext)}}
{{guarded('LR2',1,'next','BEQ','LR14')}}
{% else %}
{{guarded('LR2',1,'next','BEQ','LR13')}}
{% endif %}
{% for dx in range(-1,2) %}
{% for dy in range(-1,2) %}{{tap(0,dy,dx)}}{% endfor %}
{% endfor %}
{% else %}
{% for dx in range(-1,2) %}
{% set delta = 2*dx-phase %}
{% set name = 'p' ~ phase ~ 'd' ~ loop.index %}
{% if dx==1 and stride==2 and in0_d3%2==0 %}ADD LR14 LR13 CR1 ;;{% endif %}
{% set cmp = ('BEQ' if dx else '') %}
{% set bound = 'CR0' if dx < 0 else ('LR14' if stride==2 and in0_d3%2==0 else 'LR13') %}
{% if stride == 2 %}
{{guarded('LR1',delta,name ~ 'a',cmp,bound)}}
{# The second half is loaded into slot 256; its stride destination is LR3. #}
{{num('LR14',256)}}
{% if dx==1 and in0_d3%2==0 %}
{{guarded('LR14',delta+1,name ~ 'b')}}
{% else %}
{{guarded('LR14',delta+1,name ~ 'b',cmp,bound)}}
{% endif %}
{% for dy in range(-1,2) %}{{tap(0,dy,dx,0)}}{{tap(0,dy,dx,1)}}{% endfor %}
{% else %}
{{guarded('LR1',delta+phase,name ~ 'a',cmp,bound)}}
{% if phase == 0 %}
{{guarded('LR2',delta+1,name ~ 'b',cmp,bound)}}
{% else %}
{{guarded('LR0',delta,name ~ 'b',cmp,bound)}}
{% endif %}
{% for dy in range(-1,2) %}{{tap(0,dy,dx)}}{% endfor %}
{% endif %}
{% endfor %}
{% endif %}
ADD LR5 LR5 {{cr.irows}} ; INC LR11 1 ; BLT.S LR11 LR15 stage_c{{phase}} ;;
SET LR7 LR8 ;;
{% endmacro %}
{% for ph in range(phases) %}{{stage(ph)}}{% endfor %}
INC LR4 {{2*stride if H==256 else (stride if H==128 else 1)}} ; INC LR10 1 ; BLT.S LR10 LR13 stage_x ;;

{{num('LR2',0)}}
{% for j in range(5) %}
LD.LUT {{j}} {{cr.lut}} LR2 ;;
INC LR2 1 ;;
{% endfor %}
{{num('LR4',0)}}
{{num('LR5',0)}}
{{num('LR6',0)}}
{{num('LR7',1)}}
{{num('LR9',0)}}
{{num('LR10',groups-1)}}
{{num('LR11',no-1)}}
{{num('LR12',tiles-1)}}
{{num('LR13',ni//8-1)}}

{% macro block(n,repeat) %}
{% for part in range(2) %}
SET LR8 LR2 ; SUB LR3 LR0 CR1 ;;
LD.MULT R0 LR1 {{cr.weights}} ;;
INC LR1 1 ;;
LD.MULT.CYCLIC LR8 {{cr.pad}} LR0 ;;
{% for c in range(n) %}
{% for t in range(9) %}
{% if c==n-1 and t==8 %}
MULT.RC.VE LR0 LR3 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR3 1 ; {% if part %}INC LR2 {{9*n}} ; {% if repeat %}INC LR14 1 ; BLT.S LR14 LR13 coeff_loop ;{% endif %}{% endif %} ;;
{% else %}
MULT.RC.VE LR0 LR3 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR3 1 ; INC LR8 1 ; LD.MULT.CYCLIC LR8 {{cr.pad}} LR0 ;;
{% endif %}
{% endfor %}
{% endfor %}
{% endfor %}
{% endmacro %}
output_group:
SET LR15 CR0 ;;
output_channel:
SET LR1 LR4 ; SET LR6 CR0 ; SET LR2 LR7 ;;
output_tile:
SET LR1 LR4 ; SET LR14 CR0 ; SET LR3 CR0 ;;
LD.MULT R0 LR1 {{cr.weights}} ;;
MULT.EE LR3 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; INC LR1 1 ; LD.MULT R0 LR1 {{cr.weights}} ;;
MULT.EE LR3 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR1 1 ;;
{% if ni>=8 %}
coeff_loop:
{{block(8,true)}}
{% endif %}
{% if ni%8 %}{{block(ni%8,false)}}{% endif %}
{% if out0_d3%pack and tiles > 1 %}
BEQ LR6 LR12 output_tail ;;
{% endif %}
{% macro store(d) %}
ACTIVATE.QUANTIZE generic {{d}}.L {{qo}} {{cr.out0}} LR5 ;;
{% endmacro %}
{{store(cr.tail if out0_d3%pack and tiles == 1 else cr.dsout)}}
{% if out0_d3%pack and tiles > 1 %}
BEQ CR0 CR0 output_advance ;;
output_tail:
{{store(cr.tail)}}
output_advance:
{% endif %}
{% if tiles > 1 %}
INC LR5 1 ; INC LR6 1 ; ADD LR2 LR2 {{cr.tile_jump}} ; BLT.S LR6 LR12 output_tile ;;
{% else %}
INC LR5 1 ;;
{% endif %}
SET LR4 LR1 ; INC LR15 1 ; BLT.S LR15 LR11 output_channel ;;
ADD LR7 LR7 {{cr.stage_group}} ; INC LR9 1 ; BLT.S LR9 LR10 output_group ;;
HALT ;;
