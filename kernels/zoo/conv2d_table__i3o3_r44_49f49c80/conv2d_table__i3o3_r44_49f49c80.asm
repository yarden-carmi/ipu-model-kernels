{% set ix = (in0_d3+127)//128 %}
{% set ox = (out0_d3+127)//128 %}
{% set width = out0_d3 %}
{% set full = [out0_d2,[1,128//width]|max]|min %}
{% set pack = full if out0_d2 % full == 0 else 1 %}
{% set tiles = out0_d2//pack %}
{% set row = kw*ox %}
{% set gc = cin//groups %}
{% set resident = gc == 1 %}
{% set ds = cr.ds128 ~ '.L' %}
{% set di = cr.ds_line ~ '.L' %}
{% set do = cr.ds_out ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set staged = cr.packed if pack>1 else cr.shifted %}
{% macro adjust(r,n) %}
{% for i in range(0,n|abs,255) %}
{{ 'INC' if n>0 else 'DEC' }} {{ r }} {{ [255,n|abs-i]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro init(r,n) %}
SET {{ r }} CR0 ;;
{{ adjust(r,n) }}
{% endmacro %}
{% macro zeros(label,n) %}
{{ init('LR13',n-1) }}
SET LR12 CR0 ;;
{{ label }}:
MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1 ; INC LR12 1 ; BLT.S LR12 LR13 {{ label }} ;;
{% endmacro %}

{# Convert input scanlines to output x coordinates, leaving vertical padding
   as zero scanlines. A shifted load can span the two input row fragments. #}
SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
DEC LR4 1 ; DEC LR5 1 ; SET LR6 CR0 ;;
{{ init('LR1',128) }}
{{ init('LR2',256) }}
{{ init('LR3',384) }}
{{ init('LR9',2) }}
{{ init('LR10',in0_d2-1) }}
{{ init('LR11',cin-1) }}
{{ zeros('sentinel',1) }}
LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR3 ;;
{% if ix==1 %}LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR2 ;;{% endif %}
shift_channel:
{{ zeros('top',padding*row) }}
SET LR7 CR0 ;;
shift_y:
LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR1 ; INC LR4 1 ;;
{% if ix==2 %}LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR2 ; INC LR4 1 ;;{% endif %}
{% if in0_d3%128 %}
{% set last = 'LR1' if ix==1 else 'LR2' %}
SET LR14 LR5 ;;
MULT.RC.VE {{ last }} CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
ACTIVATE.QUANTIZE identity {{ cr.ds_input }}.L {{ qi }} {{ cr.shifted }} LR14 ; INC LR14 1 ;;
LD.MULT.CYCLIC LR14 {{ cr.shifted }} {{ last }} ;;
{% endif %}
{% macro horizontal(k,x) %}
SET LR8 {{ (['LR1','LR2'] if stride==1 else ['LR1','LR3'])[x] }} ;;
{{ adjust('LR8',k-padding) }}
{% if stride==1 %}
MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
{% else %}
MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
{% if width-128*x > 64 %}
INC LR8 128 ;;
MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR9 ;
{% endif %}
{% endif %}
ACTIVATE.QUANTIZE identity {{ di if x+1==ox else ds }} {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1 ;;
{% endmacro %}
{% for k in range(kw) %}{% for x in range(ox) %}{{ horizontal(k,x) }}{% endfor %}{% endfor %}
INC LR7 1 ; BLT.S LR7 LR10 shift_y ;;
{{ zeros('bottom',(padding+stride*(pack-1))*row) }}
INC LR6 1 ; BLT.S LR6 LR11 shift_channel ;;

{% if pack>1 %}
{# Join cropped scanlines for adjacent output y positions. Slot 0 is
   zero; each scanline in slot 1 already has a zero tail. #}
SET LR5 CR0 ; SET LR6 CR1 ; SET LR7 CR0 ;;
{{ init('LR10',(in0_d2+2*padding)*row-1) }}
{{ init('LR14',pack-2) }}
LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR0 ;;
pack_channel:
SET LR4 CR0 ;;
pack_row:
SET LR8 LR6 ; SET LR9 LR1 ; SET LR12 CR0 ;;
LD.MULT.CYCLIC LR8 {{ cr.shifted }} LR1 ; INC LR6 1 ; INC LR9 {{ width }} ;;
MULT.RC.VE LR9 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; DEC LR9 {{ width }} ;;
pack_join:
LD.MULT.CYCLIC LR8 {{ cr.shifted }} LR1 ; INC LR8 {{ stride*row }} ;;
MULT.RC.VE LR9 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; DEC LR9 {{ width }} ; INC LR12 1 ; BLT.S LR12 LR14 pack_join ;;
ACTIVATE.QUANTIZE identity {{ do }} {{ qi }} {{ cr.packed }} LR5 ; INC LR5 1 ; INC LR4 1 ; BLT.S LR4 LR10 pack_row ;;
{% for i in range(0,stride*(pack-1)*row,255) %}
INC LR5 {{ [255,stride*(pack-1)*row-i]|min }} ; INC LR6 {{ [255,stride*(pack-1)*row-i]|min }} ;;
{% endfor %}
INC LR7 1 ; BLT.S LR7 LR11 pack_channel ;;
{% endif %}

{{ init('LR13',-1) }}
{% for i in range(5) %}
LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
{% endfor %}
{{ init('LR10',-1) }}
{{ init('LR5',-1) }}
SET LR6 CR0 ; SET LR2 CR0 ;;
{% if resident %}{{ init('LR2',256) }}{% endif %}
{{ init('LR3',1-groups) }}
output_group:
SET LR7 CR0 ;;
output_channel:
SET LR4 LR6 ; SET LR15 CR0 ;;
{% if resident %}
LD.MULT.CYCLIC LR10 {{ cr.weights }} LR0 ; INC LR10 1 ;;
LD.MULT.CYCLIC LR10 {{ cr.weights }} LR1 ; INC LR10 1 ;;
LD.MULT R0 LR10 {{ cr.weights }} ; INC LR10 1 ;;
LD.MULT R1 LR10 {{ cr.weights }} ; INC LR10 1 ;;
{% endif %}
{% macro convolve(x) %}
{% set slot = 'LR2' if resident else 'LR0' %}
SET LR13 LR4 ; SET LR11 LR10 ;;
{{ adjust('LR13',x+1-ox) }}
{% if resident %}
MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ;
LD.MULT.CYCLIC LR13 {{ staged }} {{ slot }} ; INC LR13 {{ ox }} ;;
MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
{% else %}
LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ;;
MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; LD.MULT R1 LR11 {{ cr.weights }} ; INC LR11 1 ;;
MULT.VE LR1 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
SET LR12 LR13 ; SET LR14 CR0 ;;
input_{{ x }}:
LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ;;
LD.MULT R1 LR11 {{ cr.weights }} ; INC LR11 1 ;;
LD.MULT.CYCLIC LR13 {{ staged }} {{ slot }} ; INC LR13 {{ ox }} ;;
{% endif %}
SET LR8 LR0 ; SET LR9 LR1 ;;
DEC LR8 1 ; DEC LR9 1 ;;
{% for t in range(kh*kw) %}
MULT.RC.VE {{ slot }} LR8 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR8 1 ;;
MULT.RC.VE {{ slot }} LR9 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR9 1 ;
{% if not loop.last %}LD.MULT.CYCLIC LR13 {{ staged }} {{ slot }} ; INC LR13 {{ ox }} ;{% endif %} ;;
{% endfor %}
{% if not resident %}
ADD LR12 LR12 {{ cr.span }} ; INC LR14 1 ;;
SET LR13 LR12 ; BLT.S LR14 LR2 input_{{ x }} ;;
{% endif %}
ACTIVATE.QUANTIZE generic {{ do if x+1==ox else ds }} {{ qo }} {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endmacro %}
{% if not resident %}{{ init('LR2',gc) }}{% endif %}
{{ init('LR14',tiles-1) }}
ADD LR15 LR14 CR0 ;;
output_y:
{% for x in range(ox) %}{{ convolve(x) }}{% endfor %}
{{ adjust('LR4',stride*pack*row) }}
DEC LR15 1 ; BLT.S CR0 LR15 output_y ;;
{% if not resident %}SET LR10 LR11 ;;{% endif %}
INC LR7 1 ;;
{{ init('LR14',cout//groups) }}
BLT.S LR7 LR14 output_channel ;;
{% if groups>1 %}
{% if gc==1 %}
ADD LR6 LR6 {{ cr.span }} ;
{% else %}
SET LR14 CR0 ;;
next_group_plane:
ADD LR6 LR6 {{ cr.span }} ; INC LR14 1 ;;
BLT.S LR14 LR2 next_group_plane ;
{% endif %}
INC LR3 1 ; BLT.S LR3 CR0 output_group ;;
{% endif %}
HALT ;;
