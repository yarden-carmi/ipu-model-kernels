{% set q = cr.qf_stats ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set slots = ['LR0','LR13','LR14','LR15'] %}
{% macro ptr(r,n) %}
{% if n is number %}
 SET {{r}} CR0 ;;
 {% if n %}INC {{r}} {{n}} ;;{% endif %}
{% else %}SET {{r}} {{n}} ;;{% endif %}
{% endmacro %}
{% macro vec(op='ADD',first=false,scalar='CR1') %}
 MULT.VE LR0 {{scalar}} 0 LR0 {{full}} {{q}} ; ACC.{{op}}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro split(p,b=cr.tmp) %}
 ACTIVATE.QUANTIZE identity {{full}} {{q}} {{b}} {{p}} ;;
 {% for i in range(3) %}
 LD.MULT R0 {{p}} {{b}} ;;
 MULT.VE LR0 CR1 0 LR0 {{full}} {{q}} ; ACC.SUB ; INC {{p}} 1 ; ACTIVATE.QUANTIZE identity {{full}} {{q}} {{b}} {{p}} ;;
 {% endfor %}
{% endmacro %}
{% macro save(n) %}{{ptr('LR10',n)}}{{split('LR10')}}{% endmacro %}
{% macro parts(n,b=cr.tmp,op='ADD',first=false,count=4) %}
 {{ptr('LR11',n)}}
 LD.MULT R0 LR11 {{b}} ;;
 {% for i in range(count) %}
 MULT.VE LR0 CR1 0 LR0 {{full}} {{q}} ; ACC.{{op}}{% if first and loop.first %}.FIRST{% endif %}{% if not loop.last %} ; INC LR11 1 ; LD.MULT R0 LR11 {{b}}{% endif %} ;;
 {% endfor %}
{% endmacro %}
{% macro product(a,b,ab=cr.tmp,bb=cr.tmp,first=true,op='ADD',count=4) %}
 {{ptr('LR10',a)}}
 {% for slot in slots %}
 LD.MULT.CYCLIC LR10 {{ab}} {{slot}}{% if not loop.first %} ; INC LR10 1{% endif %} ;;
 {% endfor %}
 {{ptr('LR11',b)}}
 LD.MULT R0 LR11 {{bb}} ;;
 {% for i in range(count) %}
 {% for slot in slots %}
 MULT.RC.VV {{slot}} R0 0 LR0 {{full}} {{q}} ; ACC.{{op}}{% if first and i == 0 and loop.first %}.FIRST{% endif %}{% if loop.last and i < count-1 %} ; INC LR11 1 ; LD.MULT R0 LR11 {{bb}}{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{% macro avg() %}
 {{save(0)}}{{product(0,0,bb=cr.stats)}}
{% endmacro %}
{% macro store(op,b,p,fmt,label) %}
 BEQ LR7 CR1 {{label}}_tail ;;
 ACTIVATE.QUANTIZE {{op}} {{full}} {{fmt}} {{b}} {{p}} ;;
 B {{label}}_end ;;
{{label}}_tail:
 ACTIVATE.QUANTIZE {{op}} {{tail}} {{fmt}} {{b}} {{p}} ;;
{{label}}_end:
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR4 CR0 ;;
batch:
 SET LR7 LR9 ; SET LR3 LR4 ;;
tile:
 // Gather one output tile from patch positions b + out0_d0*t.
 SET LR1 CR0 ; SET LR5 {{cr.channels}} ; SET LR6 CR0 ;;
 SET LR14 CR0 ;;
channel:
 ADD LR12 LR3 LR1 ; SET LR10 CR0 ; SET LR11 CR0 ;;
 {{ptr('LR13',128)}}
 BNE LR7 CR1 gather ;;
 SET LR13 {{cr.widths}}.L ;;
 {{vec(first=true,scalar='CR0')}}
gather:
 LD.MULT R0 LR12 {{cr.in0}} ;;
 MULT.EE LR6 CR1 0 LR0 {{full}} {{cr.qf_in0}}.L ; ACC.RESHAPE LRD10 LRD10 7 ; ADD LR12 LR12 LR8 ;;
 ADDBI LRD10 1 ; DEC LR13 1 ;;
 BNE LR13 CR0 gather ;;
 {{split('LR14',cr.data)}}
 INC LR14 1 ; INC LR6 1 ; DEC LR5 1 ;;
 BEQ LR5 CR0 statistics ;;
 {{ptr('LR13',128)}}
 BLT.S LR6 LR13 channel ;;
 SET LR6 CR0 ; INC LR1 1 ; B channel ;;

statistics:
 {{ptr('LR13',128)}}
 ADD LR14 LR13 LR13 ;;
 ADD LR15 LR14 LR13 ;;
 SET LR5 {{cr.channels}} ; SET LR6 CR0 ;;
 {{vec(first=true,scalar='CR0')}}
sum:
 {{parts('LR6',cr.data)}}
 INC LR6 4 ; DEC LR5 1 ;;
 BNE LR5 CR0 sum ;;
 {{avg()}}{{save(4)}}

 SET LR5 {{cr.channels}} ; SET LR6 CR0 ;;
center:
 {{parts('LR6',cr.data,first=true)}}{{parts(4,op='SUB')}}
 {{ptr('LR10','LR6')}}{{split('LR10',cr.data)}}
 INC LR6 4 ; DEC LR5 1 ;;
 BNE LR5 CR0 center ;;

 SET LR5 {{cr.channels}} ; SET LR6 CR0 ;;
 {{vec(first=true,scalar='CR0')}}
variance:
 {{product('LR6','LR6',cr.data,cr.data,first=false)}}
 INC LR6 4 ; DEC LR5 1 ;;
 BNE LR5 CR0 variance ;;
 {{avg()}}{{parts(4,cr.stats)}}
 {{ptr('LR10',12)}}
 {{store('rsqrt',cr.tmp,'LR10',q,'seed')}}
 {{save(8)}}
 {{parts(12,first=true,count=1)}}{{save(12)}}
 // Refine y with y + 0.5*y - 0.5*v*y^3.
 {{ptr('LR12',2)}}
refine:
 {{product(12,12)}}{{save(16)}}
 {{product(8,16)}}{{save(20)}}
 {{product(12,20)}}{{save(24)}}
 {{parts(12,first=true)}}
 {{product(12,8,bb=cr.stats,first=false,count=1)}}
 {{product(24,8,bb=cr.stats,first=false,count=1,op='SUB')}}
 {{save(12)}}
 DEC LR12 1 ;;
 BNE LR12 CR0 refine ;;

 SET LR5 LR2 ; SET LR6 CR0 ; SET LR12 CR0 ;;
 SET LR1 {{cr.channels}} ;;
output:
 {{product(12,'LR6',bb=cr.data)}}{{save(16)}}
 {{product(16,'LR12',bb=cr.affine)}}
 SET LR11 LR12 ;;
 INC LR11 4 ;;
 {% for i in range(4) %}
 LD.MULT R0 LR11 {{cr.affine}} ;;
 MULT.VE LR0 CR1 0 LR0 {{full}} {{q}} ; ACC.ADD ; INC LR11 1 ;;
 {% endfor %}
 {{store(act_out0 | default('identity'),cr.out0,'LR5',cr.qf_out0 ~ '.L','result')}}
 ADD LR5 LR5 LR9 ; INC LR6 4 ; INC LR12 8 ;;
 DEC LR1 1 ;;
 BNE LR1 CR0 output ;;
 DEC LR7 1 ;;
 BEQ LR7 CR0 next_batch ;;
 INC LR2 1 ; ADD LR3 LR3 {{cr.tilejump}} ; B tile ;;
next_batch:
 SUB LR2 LR5 LR9 ; ADD LR4 LR4 {{cr.widths}}.H ;;
 INC LR2 1 ;;
 BLT.S LR2 {{cr.size}} batch ;;
 HALT ;;
