{% set iq = cr.qf_in0 ~ '.L' %}
{% set oq = cr.qf_out0 ~ '.L' %}
{% set wq = cr.work ~ '.H' %}
{% set tail = cr.work ~ '.L' %}
{% set padded = channels == 144 %}
{% set tiles = (rows + 127) // 128 %}
{% set blocks = (out0_d1 + 127) // 128 %}
{% macro setn(reg, n) %}
 SET {{ reg }} CR0 ;;
 {% for j in range((n+254)//255) %}INC {{ reg }} {{ [n-255*j,255]|min }} ;;{% endfor %}
{% endmacro %}
{% macro st(ptr,fmt=wq,fn='identity',ds='CR15.L') %}ACTIVATE.QUANTIZE {{ fn }} {{ ds }} {{ fmt }} {{ cr.tmp }} {{ ptr }}{% endmacro %}
{% macro ve(op,src='CR1',fmt=wq,reg='LR9') %}MULT.VE {{ reg }} {{ src }} 0 LR9 CR15.L {{ fmt }} ; ACC.{{ op }}{% endmacro %}
{% macro cv(reg,op,src='R0') %}MULT.RC.VV {{ reg }} {{ src }} 0 LR9 CR15.L {{ wq }} ; ACC.{{ op }}{% endmacro %}
{% macro ld(ptr,slot='LR9') %}LD.MULT.CYCLIC {{ ptr }} {{ cr.tmp }} {{ slot }}{% endmacro %}

{# Gather channel planes. Within each tile, map token and batch bits so
   ACC.STRIDE can later extract a batch's 32 consecutive tokens in one word. #}
 SET LR4 CR0 ; SET LR5 CR0 ; SET LR9 CR0 ;;
 SET LR12 {{ cr.indices0 }} ; SET LR13 {{ cr.indices0 }} ;;
 ADDBI LRD12 4 ;;
 {{ setn('LR10',tiles) }}
 {{ setn('LR15',8 + 3 * channels) }}
tile_loop:
 SET LR6 LR4 ; SET LR7 CR0 ; SET LR8 CR0 ;;
 INC LR7 {{ channels }} ; INC LR8 {{ 8 if rows % 128 else 7 }} ;;
 {% if padded or rows % 128 %}
 {% set step = 16 if padded else 64 %}
 {% for p in range(step,channels if padded else 128,step) %}
 {{ setn('LR11',p) }}
 BLT.S LR5 LR11 {{ 'prime' if padded and not rows % 128 else 'gather' }}_{{ p-step }} ;;
 {% endfor %}
 B {{ 'prime' if padded and not rows % 128 else 'gather' }}_{{ channels-step if padded else 64 }} ;;
 {% endif %}

{% macro gather(phase) %}
 {% set span = channels if padded else 128 %}
 {% set stride = 2 if padded else 1 %}
 {% set next = (phase+rows) % span %}
 {% set advance = stride * ((phase+rows)//span) %}
 {% set pipe = padded and not rows % 128 %}
 {% set pred = (phase-rows)%span %}
 {% set lastlane = ((pred+232)%span)%128 %}
 {% if pipe %}
 prime_{{ phase }}:
 SET LR0 {{ cr.indices0 }} ; SET LR1 LR13 ; SET LR12 LR6 ;;
 {% if lastlane %}ADDBI LRD0 {{ lastlane }} ; {% endif %}{% if phase >= 128 %}INC LR12 1 ; {% endif %}LD.MULT R0 LR12 {{ cr.in0 }} ;;
 SET LR2 {{ cr.dest0 }} ; SET LR3 {{ cr.dest1 }} ;;
 ADDBI LRD2 108 ;;
 {% endif %}
gather_{{ phase }}:
 {% if not pipe %}
 {% if phase >= 128 %}
 SET LR0 {{ cr.indices0 }} ; SET LR1 LR13 ; SET LR12 LR6 ;;
 INC LR12 1 ; LD.MULT R0 LR12 {{ cr.in0 }} ;;
 {% else %}
 SET LR0 {{ cr.indices0 }} ; SET LR1 LR13 ; SET LR12 LR6 ; LD.MULT R0 LR12 {{ cr.in0 }} ;;
 {% endif %}
 {% endif %}
  {% for k in range(8 if rows == 64 else 16) %}
   {# Keep alternating 16-element bands in separate tiles so their
      shared NX8 scales do not suppress the smaller band. #}
   {% set x = 32*(k//2)+8*(k%2) if padded else 8*k %}
   {% set xp = 32*((k-1)//2)+8*((k-1)%2) if padded else 8*(k-1) %}
   {% set xn = 32*((k+1)//2)+8*((k+1)%2) if padded else 8*(k+1) %}
  {% set lane = ((phase+x)%span)%128 %}
   {% set prev = ((phase+xp)%span)%128 if k else (lastlane if pipe else 0) %}
  {% set addr = stride*((phase+x)//span) + ((phase+x)%span)//128 %}
  {% set addrnext = stride*((phase+xn)//span) + ((phase+xn)%span)//128 %}
  {% if k == 8 and rows % 128 and rows != 64 %}BEQ LR10 CR1 gather_tail_{{ phase }} ;;{% endif %}
 {% if loop.first and not pipe %}SET LR2 {{ cr.dest0 }} ; SET LR3 {{ cr.dest1 }} ; {% endif %}
 {% if lane != prev %}ADDBI LRD0 {{ lane-prev }} ; {% endif %}
 {% if k %}
 {% set kp = (k%2 + 2*(k//8) + 4*((k//2)%4)) if padded else k %}
 {% set j = k-1 %}
 {% set jp = (j%2 + 2*(j//8) + 4*((j//2)%4)) if padded else j %}
 ADDBI LRD2 {{ 32*(kp//4-jp//4) + 4*(kp%4-jp%4) }} ;
 {% elif pipe %}ADDBI LRD2 -108 ;
 {% endif %}
 {% if pipe and k == 0 %}INC LR8 1 ; {% endif %}
 {% if pipe and k == 12 %}{{ 'ADD LR11 LR6 CR1' if next >= 128 else 'SET LR11 LR6' }} ; {% endif %}
 {% if not rows % 128 and k == 2 and advance %}INC LR6 {{ advance }} ; {% endif %}
 {% if not rows % 128 and k == 14 %}DEC LR7 1 ; {% endif %}
 {% if not loop.last and addr != addrnext %}
  {% if k == 7 and rows % 128 and rows != 64 %}
 INC LR12 {{ addrnext-addr }} ; MULT.VE LR9 CR1 0 LR9 CR15.L {{ iq }} ; ACC.RESHAPE LRD0 LRD2 0 ;;
 BEQ LR10 CR1 gather_tail_{{ phase }} ;;
 LD.MULT R0 LR12 {{ cr.in0 }} ;;
 {% else %}
 INC LR12 {{ addrnext-addr }} ; LD.MULT R0 LR12 {{ cr.in0 }} ; MULT.VE LR9 CR1 0 LR9 CR15.L {{ iq }} ; ACC.RESHAPE LRD0 LRD2 0 {% if pipe and k == 14 %}; BEQ LR7 CR1 finish_{{ phase }}{% endif %} ;;
 {% endif %}
 {% else %}
   MULT.VE LR9 CR1 0 LR9 CR15.L {{ iq }} ; ACC.RESHAPE LRD0 LRD2 0 {% if pipe and k == 14 %}; BEQ LR7 CR1 finish_{{ phase }}{% endif %}{% if loop.last and not rows % 128 %}; {% if pipe %}SET LR12 LR11 ; LD.MULT R0 LR11 {{ cr.in0 }} ; {% else %}INC LR8 1 ; {% endif %}{{ st('LR8',iq) }} ; {{ 'B' if pipe else 'BNE LR7 LR9' }} gather_{{ next }}{% endif %} ;;
 {% endif %}
 {% endfor %}
 {% if pipe %}
 finish_{{ phase }}:
 {% set shift = ((phase+232)%span)%128 - ((phase+224)%span)%128 %}
 {% if shift %}ADDBI LRD0 {{ shift }} ; {% endif %}ADDBI LRD2 4 ; MULT.VE LR9 CR1 0 LR9 CR15.L {{ iq }} ; ACC.RESHAPE LRD0 LRD2 0 ; {{ st('LR8',iq) }} ;;
 {% endif %}
 {% if rows % 128 %}gather_tail_{{ phase }}:
 {{ st('LR8',iq) }} ;;
 INC LR8 1 ; DEC LR7 1 ; {% if advance %}INC LR6 {{ advance }} ; {% endif %}BNE LR7 CR1 gather_{{ next }} ;;
 {% endif %}
 B normalize ;;
{% endmacro %}
{% for p in (range(0,channels,16) if padded else (range(0,128,64) if rows%128 else [0])) %}{{ gather(p) }}{% endfor %}

normalize:
 {% if not rows % 128 %}INC LR8 1 ;;{% endif %}
 {{ setn('LR0',8) }}
 SET LR7 LR8 ; SET LR11 CR1 ;;
 DEC LR7 2 ;;
 SET LR1 LR0 ; {{ ld('LR0') }} ;;
 MULT.RC.VE LR9 CR1 0 LR9 CR15.L {{ iq }} ; ACC.ADD.FIRST ; INC LR1 1 ; {{ ld('LR1') }} ;;
sum_loop:
 MULT.RC.VE LR9 CR1 0 LR9 CR15.L {{ iq }} ; ACC.ADD ; INC LR1 1 ; {{ ld('LR1') }} ; BLT.S LR1 LR7 sum_loop ;;
 MULT.RC.VE LR9 CR1 0 LR9 CR15.L {{ iq }} ; ACC.ADD ; {{ st('LR9') }} ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ ve('SUB') }} ; {{ st('LR11') }} ; {{ ld('LR9') }} ;;
 LD.MULT R0 LR9 {{ cr.crow }} ;;
 {{ setn('LR12',128) }}
 {{ ld('LR11','LR12') }} ;;
 {# Crow shares the internal format. #}
 MULT.RC.VE LR9 LR9 0 LR9 CR15.L {{ wq }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR12 LR9 0 LR9 CR15.L {{ wq }} ; ACC.ADD ; LD.MULT R0 LR11 {{ cr.crow }} ;;
 SET LR2 CR1 ;;
 INC LR2 1 ;;
 MULT.RC.VE LR9 LR9 0 LR9 CR15.L {{ wq }} ; ACC.ADD ; {{ st('LR2') }} ;;
 LD.MULT R0 LR2 {{ cr.tmp }} ; SET LR3 LR2 ;;
 INC LR3 1 ;;
 {{ ve('SUB') }} ; {{ st('LR3') }} ; {{ ld('LR2','LR9') }} ;;
 {{ ld('LR3','LR12') }} ; SET LR1 LR0 ; SET LR2 LR8 ;;
 SET LR3 LR8 ; INC LR7 1 ;;
 INC LR3 {{ channels-1 }} ; DEC LR2 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
center_loop:
 {{ ve('ADD.FIRST',fmt=iq) }} ; INC LR1 1 ; INC LR2 1 ; INC LR3 1 ;;
 MULT.RC.VE LR9 CR1 0 LR9 CR15.L {{ wq }} ; ACC.SUB ;;
 MULT.RC.VE LR12 CR1 0 LR9 CR15.L {{ wq }} ; ACC.SUB ; {{ st('LR2') }} ;;
 LD.MULT R0 LR2 {{ cr.tmp }} ;;
 {{ ve('SUB') }} ; {{ st('LR3') }} ; LD.MULT R0 LR1 {{ cr.tmp }} ; BLT.S LR1 LR7 center_loop ;;
 {# The branch compares pre-increment values; finish the last channel. #}
 {{ ve('ADD.FIRST',fmt=iq) }} ; INC LR2 1 ; INC LR3 1 ;;
 MULT.RC.VE LR9 CR1 0 LR9 CR15.L {{ wq }} ; ACC.SUB ;;
 MULT.RC.VE LR12 CR1 0 LR9 CR15.L {{ wq }} ; ACC.SUB ; {{ st('LR2') }} ;;
 LD.MULT R0 LR2 {{ cr.tmp }} ;;
 {{ ve('SUB') }} ; {{ st('LR3') }} ;;

 SET LR1 LR8 ; SET LR7 LR2 ; {{ ld('LR8') }} ;;
 SET LR2 LR8 ;;
 INC LR2 {{ channels }} ; LD.MULT R0 LR2 {{ cr.tmp }} ;;
 {% if padded %}{{ ld('LR2','LR12') }} ;;{% endif %}
 MULT.RC.VS LR9 0 LR9 CR15.L {{ wq }} ; ACC.ADD.FIRST ;;
variance_cross:
 {{ cv('LR9','ADD') }} ;;
 {{ cv('LR9','ADD') }} ; BEQ LR1 LR7 variance_done ; INC LR1 1 ; INC LR2 1 ; {{ ld('LR1') }} ;;
 {% if padded %}MULT.RC.VS LR12 0 LR9 CR15.L {{ wq }} ; ACC.ADD ; {{ ld('LR2','LR12') }} ;;{% endif %}
 MULT.RC.VS LR9 0 LR9 CR15.L {{ wq }} ; ACC.ADD ; LD.MULT R0 LR2 {{ cr.tmp }} ; B variance_cross ;;
 variance_done:
 {% if padded %}MULT.RC.VS LR12 0 LR9 CR15.L {{ wq }} ; ACC.ADD ;;{% endif %}
 DEC LR7 1 ; DEC LR2 1 ;;
 {{ setn('LR14',2) }}
 LD.MULT R0 LR14 {{ cr.crow }} ;;
 {{ setn('LR14',4) }}
 {% if rows % 128 %}
 BEQ LR10 CR1 inverse_half ;;
 {% endif %}
 {{ ve('ADD') }} ; {{ st('LR14',fn='rsqrt') }} ;;
 {% if rows % 128 %}
 B inverse_ready ;;
inverse_half:
 {{ ve('ADD') }} ; {{ st('LR14',fn='rsqrt',ds=cr.half ~ '.L') }} ;;
inverse_ready:
 {% endif %}
 {# Newton refinement: keep variance and inverse-square in two pieces. #}
 {% set vd = cr.half ~ '.L' if rows == 64 else 'CR15.L' %}
 {{ st('LR9',ds=vd) }} ;;
 {{ ld('LR14') }} ; SET LR1 CR1 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ ve('SUB') }} ; {{ st('LR1',ds=vd) }} ;;
 {{ setn('LR2',2) }}
 {{ setn('LR3',3) }}
 MULT.RC.VS LR9 0 LR9 CR15.L {{ wq }} ; ACC.ADD.FIRST ; {{ st('LR2',ds=vd) }} ;;
 LD.MULT R0 LR2 {{ cr.tmp }} ;;
 {{ ve('SUB') }} ; {{ st('LR3',ds=vd) }} ; {{ ld('LR2') }} ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ; {{ setn('LR6',5) }}
 {{ cv('LR9','SUB.FIRST') }} ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ cv('LR9','SUB') }} ; {{ ld('LR3') }} ;;
 {{ cv('LR9','SUB') }} ; LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ cv('LR9','SUB') }} ; LD.MULT R0 LR3 {{ cr.crow }} ;;
 MULT.EE LR9 CR1 0 LR9 CR15.L {{ wq }} ; ACC.ADD ;;
 MULT.EE LR9 CR1 0 LR9 CR15.L {{ wq }} ; ACC.ADD ; {{ st('LR6',ds=vd) }} ; {{ ld('LR14') }} ;;
 LD.MULT R0 LR6 {{ cr.tmp }} ;;
 {{ cv('LR9','ADD.FIRST') }} ; INC LR6 1 ; {{ st('LR6',ds=vd) }} ;;
 {{ ld('LR6','LR12') }} ;;
 LD.MULT R0 LR3 {{ cr.crow }} ;;
 MULT.RC.VE LR12 LR9 0 LR9 CR15.L {{ wq }} ; ACC.ADD.FIRST ; {{ st('LR6',ds=vd) }} ;;
 {{ setn('LR3',256) }}
 {{ ld('LR6','LR3') }} ;;
 {{ ld('LR14') }} ; SET LR1 LR8 ; SET LR2 LR8 ;;
 INC LR2 {{ channels }} ; SET LR11 CR0 ; SET LR6 LR15 ;;
 {{ setn('LR14',channels) }}
 DEC LR6 1 ; INC LR7 1 ; LD.MULT R0 LR11 {{ cr.gamma }} ;;
 {{ setn('LR13',tiles*channels) }}
 ADD LR13 LR6 LR13 ; {% if padded %}SET LR15 LR5 ; {% endif %}SET LR5 CR0 ;;
affine_loop:
 MULT.RC.VE LR9 LR9 0 LR9 CR15.L {{ wq }} ; ACC.ADD.FIRST ; {{ st('LR0') }} ; {{ ld('LR1','LR12') }} ;;
 MULT.RC.VE LR3 LR9 0 LR9 CR15.L {{ wq }} ; ACC.ADD ; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.gamma }} ;;
 MULT.RC.VE LR9 LR9 0 LR9 CR15.L {{ wq }} ; ACC.ADD ; LD.MULT R0 LR0 {{ cr.tmp }} ;;
 {{ ve('SUB') }} ; {{ st('LR9') }} ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ cv('LR12','ADD.FIRST') }} ; LD.MULT R0 LR0 {{ cr.tmp }} ;;
 {{ cv('LR12','ADD') }} ; {{ ld('LR2','LR12') }} ;;
  {{ cv('LR12','ADD') }} ; LD.MULT R1 LR11 {{ cr.beta }} ; INC LR6 1 ;;
 {{ ve('ADD',fmt=iq,reg='LR12') }} ; LD.MULT R1 LR14 {{ cr.beta }} ; INC LR11 1 ; INC LR2 1 ;;
 {{ ve('ADD',fmt=iq,reg='LR12') }} ; {{ st('LR6',iq) }} ; INC LR5 1 ;;
 LD.MULT R0 LR6 {{ cr.tmp }} ;;
 {{ ve('SUB',fmt=iq) }} ; {{ st('LR13') }} ; INC LR13 1 ; INC LR1 1 ; INC LR14 1 ; LD.MULT R0 LR5 {{ cr.gamma }} ; BLT.S LR1 LR7 affine_loop ;;
 SET LR12 {{ cr.indices0 }} ; SET LR13 {{ cr.indices0 }} ; SET LR5 {{ 'LR15' if padded else 'CR0' }} ;;
 ADDBI LRD12 4 ;;
 SET LR15 LR6 ; DEC LR10 1 ;;
 INC LR15 1 ;;
 {% if padded %}
 SET LR6 CR0 ;;
 INC.MODP2 LR6 LR10 1 ;;
 BEQ LR6 CR0 tile_even ;;
 INC LR5 16 ; B tile_wrap ;;
tile_even:
 INC LR5 240 ;;
tile_wrap:
 {{ setn('LR11',144) }}
tile_wrap_again:
 BLT.S LR5 LR11 tile_not_wrapped ;;
 SUB LR5 LR5 LR11 ; INC LR4 2 ; B tile_wrap_again ;;
tile_not_wrapped:
 {% else %}
 INC LR4 1 ;;
 {% endif %}
 BNE LR10 LR9 tile_loop ;;

 {# Four 32-token strips, selected directly into their final lane offsets. #}
 {{ setn('LR15',8 + 3 * channels) }}
 SET LR3 CR1 ; SET LR4 CR1 ; SET LR5 CR1 ;;
 INC LR4 1 ; INC LR5 2 ;;
 SET LR6 CR0 ;;
 DEC LR6 1 ;;
 {% if padded %}
 {{ setn('LR6',8+3*channels+2*tiles*channels-1) }}
 {% endif %}
 {% macro merge(batch) %}
 SET LR7 LR15 ; {{ setn('LR8',channels) }}
 {{ setn('LR10',tiles*channels) }}
 SET LR1 LR7 ; ADD LR11 LR7 LR10 ; LD.MULT R0 LR7 {{ cr.tmp }} ;;
 merge_{{ batch }}:
 {% for b in range(blocks) %}
 {% set count = [4,tiles-4*b]|min %}
 {% set ds = tail if b == blocks-1 else 'CR15.L' %}
 {% if padded %}
 {% for part in range(2) %}
 {% set fmt = wq if part else iq %}
 {% set ptr = 'LR11' if part else 'LR1' %}
 {% for t in range(4) %}
 MULT.VE LR9 CR1 0 LR9 CR15.L {{ fmt }} ; ACC.STRIDE 16 {{ 'on' if batch%2 == 0 else 'on_inv' }} {{ 'on' if batch<2 else 'on_inv' }} {{ ['LR9','LR3','LR4','LR5'][t] }} ; {% if t < 3 %}INC {{ ptr }} {{ channels }} ; LD.MULT R0 {{ ptr }} {{ cr.tmp }}{% elif not part %}{{ st('LR9',iq) }} ; LD.MULT R0 LR11 {{ cr.tmp }}{% else %}LD.MULT R0 LR9 {{ cr.tmp }} {% if b == blocks-1 %}; INC LR7 1 ; DEC LR8 1{% else %}; INC LR1 {{ channels }} ; INC LR11 {{ channels }}{% endif %}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {{ ve('ADD',fmt=iq) }} ; INC LR6 1 ; {{ st('LR6',oq) }} {% if loop.last %}; SET LR1 LR7 ; ADD LR11 LR7 LR10 ; LD.MULT R0 LR7 {{ cr.tmp }} ; BNE LR8 CR0 merge_{{ batch }}{% else %}; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
 {% else %}
 {% for part in range(2) %}
 {% set fmt = wq if part else iq %}
 {% set ptr = 'LR11' if part else 'LR1' %}
 {% for t in range(count) %}
 MULT.VE LR9 CR1 0 LR9 CR15.L {{ fmt }} ; ACC.STRIDE 16 {{ 'on' if batch%2 == 0 else 'on_inv' }} {{ 'on' if batch<2 else 'on_inv' }} {{ ['LR9','LR3','LR4','LR5'][t] }} ;
 {% if not loop.last %}INC {{ ptr }} {{ channels }} ; LD.MULT R0 {{ ptr }} {{ cr.tmp }}
 {% elif not part %}{{ st('LR9',iq,ds=ds) }} ; LD.MULT R0 LR11 {{ cr.tmp }}
 {% else %}LD.MULT R0 LR9 {{ cr.tmp }} {% if b == blocks-1 %}; INC LR7 1 ; DEC LR8 1{% endif %}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {{ ve('ADD',fmt=iq) }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ oq }} {{ cr.out0 }} LR6 ; INC LR6 1 {% if loop.last %}; SET LR1 LR7 ; ADD LR11 LR7 LR10 ; LD.MULT R0 LR7 {{ cr.tmp }} ; BLT.S CR0 LR8 merge_{{ batch }}{% endif %} ;;
 {% if b < blocks-1 %}INC LR1 {{ channels }} ; INC LR11 {{ channels }} ; LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
 {% endif %}
 {% endfor %}
 {% endmacro %}
 {% for b in range(4) %}{{ merge(b) }}{% endfor %}
 {% if padded %}
 {{ setn('LR7',8+3*channels+2*tiles*channels) }}
 {{ setn('LR8',tiles*channels) }}
 {# Move between the two strip orders by exchanging token bits 2 and 5.
    The three destination masks select the unchanged lanes and the two shifts. #}
 SET LR6 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 INC LR3 28 ; DEC LR2 28 ; DEC LR6 1 ;;
 {% for m in range(3) %}
 {{ setn('LR4',4+m) }}
 LD.MULT R0 LR4 {{ cr.crow }} ;;
 {{ ve('ADD.FIRST') }} ; {{ st('LR4',oq) }} ;;
 {% endfor %}
 {{ setn('LR4',4) }}{{ setn('LR5',5) }}{{ setn('LR11',6) }}
 ADD LR8 LR7 LR8 ; LD.MULT R1 LR4 {{ cr.tmp }} ;;
 DEC LR8 2 ; LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR9 ;;
 rejoin:
 {% macro swap_row(next) %}
 MULT.RC.VV LR9 R1 0 LR9 CR15.L {{ oq }} ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.RC.VV LR2 R0 0 LR9 CR15.L {{ oq }} ; ACC.ADD ; LD.MULT R0 LR11 {{ cr.tmp }} ;;
 MULT.RC.VV LR3 R0 0 LR9 CR15.L {{ oq }} ; ACC.ADD ; INC LR6 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ oq }} {{ cr.out0 }} LR6 {% if next %}; INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR9 ; BLT.S LR7 LR8 rejoin{% endif %} ;;
 {% endmacro %}
 {{ swap_row(true) }}{{ swap_row(false) }}
 {% endif %}
 HALT ;;
