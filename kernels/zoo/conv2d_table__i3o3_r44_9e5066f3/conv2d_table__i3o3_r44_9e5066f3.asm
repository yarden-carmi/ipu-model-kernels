{% set dw = groups > 1 %}
{% set ip = [1,128 // w]|max if dw else 1 %}
{% set op = [1,128 // out0_d3]|max if dw else ([1,128 // w]|max if stride == 1 else 1) %}
{% set ni = (cin + ip - 1) // ip %}
{% set ix = (w + 127) // 128 %}
{% set row = stride if dw else (1 if op > 1 else 3) %}
{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% macro inc(r,n) %}{% if n %}{{ 'INC' if n>0 else 'DEC' }} {{r}} {{n|abs}} ;{% endif %}{% endmacro %}
{% macro bound(r,n) %}
 SET {{r}} CR0 ;;
 {% for off in range(0,n|abs,255) %}{{inc(r,([255,n|abs-off]|min)*(1 if n>0 else -1))}} ;;{% endfor %}
{% endmacro %}
{% macro zero() %}
 {% for i in range(row) %}
 MULT.VE LR0 CR0 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR5 ; INC LR5 1 ;;
 {% endfor %}
{% endmacro %}

{{bound('LR1',128)}}
{{bound('LR2',256)}}
{{bound('LR3',384)}}
{{bound('LR5',-1)}}
{% if dw %}
{# Stage parity-separated scanlines for a stride-two cyclic gather. #}
{% set pair = stride == 2 and ni % 2 == 0 %}
{{bound('LR10',h-(2 if pair else 1))}}
{% if stride == 2 %}
 {{bound('LR13',2)}}
 {{bound('LR15',ni-1)}}
 {{bound('LR14',(cout+op-1)//op-1)}}
 {{bound('LR8',256-w*ip)}}
{% endif %}
stage_block:
 {{zero()}}
 SET LR7 CR0 ; {% if stride == 1 %}SET LR4 LR6 ;{% else %}ADD LR4 LR6 LR6 ;{% endif %} ;;
{% macro unzip(again) %}
 MULT.RC.VE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.STRIDE 64 on off LR0 ; LD.MULT.CYCLIC LR4 {{cr.in0}} LR2 ; INC LR4 1 ;;
 MULT.RC.VE LR2 CR1 0 LR0 {{ds}} {{qi}} ; ACC.STRIDE 64 on off LR13 ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR5 ; INC LR5 1 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.STRIDE 64 on_inv off LR0 ;;
 MULT.RC.VE LR2 CR1 0 LR0 {{ds}} {{qi}} ; ACC.STRIDE 64 on_inv off LR13 ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR5 ; INC LR5 1 ; ADD LR4 LR4 LR15 ; {% if again %}LD.MULT.CYCLIC LR4 {{cr.in0}} LR0 ; INC LR7 1 ; BLT.S LR7 LR10 stage_y ;{% endif %} ;;
{% endmacro %}
 {% if pair %}LD.MULT.CYCLIC LR4 {{cr.in0}} LR0 ;;{% endif %}
 stage_y:
 {% if stride == 1 %}
 LD.MULT R0 LR4 {{cr.in0}} ;;
 MULT.VE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR5 ; INC LR5 1 ; INC LR7 1 ; ADD LR4 LR4 {{cr.no}} ; BLT.S LR7 LR10 stage_y ;;
 {% elif pair %}
 {{unzip(true)}}
 {{unzip(false)}}
 {% else %}
 LD.MULT.CYCLIC LR4 {{cr.in0}} LR1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; INC LR4 1 ; BEQ LR6 LR14 last_half ;;
 LD.MULT.CYCLIC LR4 {{cr.in0}} LR2 ; BEQ LR0 CR0 join_half ;;
 last_half:
 LD.MULT.CYCLIC LR0 {{cr.pad}} LR2 ;;
 join_half:
 MULT.RC.VE LR8 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR5 ; INC LR5 1 ;;
 LD.MULT.CYCLIC LR5 {{cr.pad}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.STRIDE 64 on off LR0 ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR5 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.STRIDE 64 on_inv off LR0 ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR5 ; INC LR5 1 ; ADD LR4 LR4 LR15 ; INC LR7 1 ; BLT.S LR7 LR10 stage_y ;;
 {% endif %}
 {{zero()}}
 INC LR6 1 ;;
 BLT.S LR6 {{cr.no}} stage_block ;;
{% else %}
{# Dense tiles broadcast each scanline to the packed output channels. #}
{{bound('LR10',h-1)}}
{{bound('LR15',-1)}}
{{bound('LR9',op-2 if op>1 else 2)}}
{{bound('LR8',(cin-1)*ix)}}
{{bound('LR6',(cin-1)*ix-1)}}
stage_channel:
 {{zero()}}
 SET LR4 LR15 ; SET LR7 CR0 ; LD.MULT.CYCLIC LR0 {{cr.pad}} LR0 ;;
 LD.MULT.CYCLIC LR0 {{cr.pad}} LR3 ;;
 stage_y:
 LD.MULT.CYCLIC LR4 {{cr.in0}} LR1 ; INC LR4 1 ; {% if op==1 %}SET LR13 LR1 ; SET LR12 LR2 ;{% endif %} ;;
 {% if ix == 2 %}LD.MULT.CYCLIC LR4 {{cr.in0}} LR2 ; INC LR4 1 ;;{% elif op==1 %}LD.MULT.CYCLIC LR0 {{cr.pad}} LR2 ;;{% endif %}
 {% if op>1 %}
 MULT.RC.VE LR1 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{cr.ds_width}}.L {{qi}} {{cr.pad}} LR5 ; INC LR5 1 ;;
 LD.MULT.CYCLIC LR5 {{cr.pad}} LR1 ; SET LR13 LR1 ;;
 SET LR12 CR0 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; DEC LR5 1 ;;
 replicate:
 MULT.RC.VE LR13 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; DEC LR13 {{w}} ; INC LR12 1 ; BLT.S LR12 LR9 replicate ;;
 ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR5 ; INC LR5 1 ;;
 {% else %}
 {% for k in range(3) %}
 {% set shift = -1 if k==0 else 1 %}
 {% if stride == 2 %}
 MULT.RC.VE LR13 CR1 0 LR0 {{ds}} {{qi}} ; ACC.STRIDE 64 on off LR0 ; {{inc('LR13',shift)}} ;;
 {% if w>128 %}MULT.RC.VE LR12 CR1 0 LR0 {{ds}} {{qi}} ; ACC.STRIDE 64 on off LR9 ; {{inc('LR12',shift)}}{% endif %} ACTIVATE.QUANTIZE identity {{cr.ds_out}}.L {{qi}} {{cr.pad}} LR5 ; INC LR5 1 ;;
 {% else %}
 MULT.RC.VE LR13 CR1 0 LR0 {{ds}} {{qi}} ; {{inc('LR13',shift)}} ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{cr.ds_out}}.L {{qi}} {{cr.pad}} LR5 ; INC LR5 1 ;;
 {% endif %}
 {% endfor %}
 {% endif %}
 ADD LR4 LR4 LR8 ; INC LR7 1 ; BLT.S LR7 LR10 stage_y ;;
 {{zero()}}
 INC LR15 {{ix}} ; BLT.S LR15 LR6 stage_channel ;;
{% endif %}

{{bound('LR13',-1)}}
{% for i in range(5) %}LD.LUT {{i}} {{cr.lut}} LR13 ; INC LR13 1 ;;{% endfor %}
{{bound('LR4',-1)}}
{{bound('LR10',-1)}}
{{bound('LR9',out0_d2-1)}}
SET LR6 CR0 ;;
output_block:
 SET LR7 CR0 ; SUB LR5 LR6 {{cr.no}} ; SET LR12 LR4 ;;
 LD.MULT.CYCLIC LR10 {{cr.weights}} LR0 ; INC LR10 1 ;;
 LD.MULT.CYCLIC LR10 {{cr.weights}} LR3 ; INC LR10 1 ;;
output_y:
 {% if dw or op>1 %}
 MULT.RC.VE LR0 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD.FIRST ; SET LR15 LR10 ; ADD LR13 LR12 CR1 ; LD.MULT.CYCLIC LR13 {{cr.pad}} LR1 ; {% if not dw %}ADD LR14 LR12 CR1 ;{% endif %} ;;
 MULT.RC.VE LR3 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; LD.MULT R0 LR15 {{cr.weights}} ; INC LR15 1 ; SET LR8 LR1 ;;
 {% if not dw %}dense_channel:{% endif %}
 {% for y in range(3) %}
 {% if y %}LD.MULT.CYCLIC LR13 {{cr.pad}} LR1 ; INC LR13 1 ; SET LR8 LR1 ;;{% endif %}
 {% if dw and stride==2 %}LD.MULT.CYCLIC LR13 {{cr.pad}} LR2 ; INC LR13 1 ;;{% endif %}
 {% for k in range(3) %}
 {% set d = k-1 %}
 {% set prev = d-1 %}
 {% set delta = d//stride+128*(d%stride)-(0 if k==0 else prev//stride+128*(prev%stride)) %}
 MULT.RC.VV LR8 R0 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; {{inc('LR8',delta)}} LD.MULT R1 LR15 {{cr.weights}} ; INC LR15 1 ;;
 MULT.RC.VV LR8 R1 0 LR0 {{ds}} {{qw}} ; ACC.ADD ;
 {% if y<2 or k<2 %}LD.MULT R0 LR15 {{cr.weights}} ; INC LR15 1 ;
 {% elif dw %}ACTIVATE.QUANTIZE generic {{cr.ds_out}}.L {{qo}} {{cr.out0}} LR5 ; ADD LR5 LR5 {{cr.no}} ; INC LR12 {{stride*stride}} ; INC LR7 1 ; BLT.S LR7 LR9 output_y ;
 {% else %}LD.MULT R0 LR15 {{cr.weights}} ; INC LR15 1 ; ADD LR14 LR14 {{cr.plane}} ;
 {% endif %} ;;
 {% endfor %}
 {% endfor %}
 {% if not dw %}
 LD.MULT.CYCLIC LR14 {{cr.pad}} LR1 ; SET LR8 LR1 ; SET LR13 LR14 ; BLT.S LR14 {{cr.channel_end}} dense_channel ;;
 ACTIVATE.QUANTIZE generic {{cr.ds_out}}.L {{qo}} {{cr.out0}} LR5 ; ADD LR5 LR5 {{cr.no}} ; INC LR12 1 ; INC LR7 1 ; BLT.S LR7 LR9 output_y ;;
 {% endif %}
 {% else %}
 {# The unbatched output uses two scalar coefficient rows per channel. #}
 MULT.RC.VE LR0 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD.FIRST ; SET LR15 LR10 ; SET LR13 LR12 ; ADD LR14 LR12 CR1 ;;
 MULT.RC.VE LR3 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; LD.MULT R0 LR15 {{cr.weights}} ; INC LR15 1 ;;
 LD.MULT R1 LR15 {{cr.weights}} ; INC LR15 1 ; SUB LR8 LR0 CR1 ; SUB LR11 LR1 CR1 ;;
 LD.MULT.CYCLIC LR13 {{cr.pad}} LR1 ; INC LR13 1 ;;
 scalar_channel:
 {% for t in range(9) %}
 {% set paired = t not in [1,2,3] %}
 {% set data = 'LR1' if t==0 else 'LR2' %}
 {% if paired %}MULT.RC.VE {{data}} LR8 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; INC LR8 1 ;
 {% if t==0 %}SET LR11 LR1 ; LD.MULT.CYCLIC LR13 {{cr.pad}} LR2 ; INC LR13 1 ;
 {% elif t==7 %}ADD LR14 LR14 {{cr.plane}} ; LD.MULT.CYCLIC LR14 {{cr.pad}} LR1 ;
 {% elif t==8 %}SET LR13 LR14 ; LD.MULT R0 LR15 {{cr.weights}} ; INC LR15 1 ;{% endif %} ;;
 {% endif %}
 MULT.RC.VE {{data}} {{'LR11' if paired else 'LR8'}} 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; {% if not paired %}INC LR8 1 ;{% endif %} {% if t %}INC LR11 1 ;{% endif %}
 {% if t==0 %};;
 {% elif t<8 %}LD.MULT.CYCLIC LR13 {{cr.pad}} LR2 ; INC LR13 1 ;;
 {% else %}SUB LR8 LR0 CR1 ; LD.MULT R1 LR15 {{cr.weights}} ; INC LR15 1 ; BLT.S LR14 {{cr.channel_end}} scalar_channel ;;
 {% endif %}
 {% endfor %}
 ACTIVATE.QUANTIZE generic {{cr.ds_out}}.L {{qo}} {{cr.out0}} LR5 ; ADD LR5 LR5 {{cr.no}} ; INC LR12 {{3*stride}} ; INC LR7 1 ; BLT.S LR7 LR9 output_y ;;
 {% endif %}
 {% if dw %}SET LR10 LR15 ; ADD LR4 LR4 {{cr.plane}} ;{% else %}SET LR10 LR15 ;; DEC LR10 {{1 if op>1 else 2}} ;{% endif %} INC LR6 1 ;;
 BLT.S LR6 {{cr.no}} output_block ;;
 HALT ;;
