{% set q = cr.qf_in0 ~ '.L' %}
{% set qr = cr.qf_in1 ~ '.L' %}
{% set full = 'CR15.L' %}
{% set tail = cr.tail ~ '.L' %}
{% set krows = (s0_k+127)//128 %}
{% set stride = in1_d0*in1_d1 %}
{% set narrow = krows <= 4 and (s0_n-128)*krows < s0_k %}
{% macro at(r,n) %}
 SET {{ r }} CR0 ;;
 {% for i in range(n//255) %}INC {{ r }} 255 ;;{% endfor %}
 {% if n%255 %}INC {{ r }} {{ n%255 }} ;;{% endif %}
{% endmacro %}
{% macro v(op='ADD',imm='CR1',extra='',ds=full) %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }} {{ extra }} ;;
{% endmacro %}
{% macro st(r,ds=full,act='identity') %}ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ q }} {{ cr.tmp }} {{ r }}{% endmacro %}
{% macro encode(r,ds=full) %}
 {{ st(r,ds) }} ;;
 LD.MULT R0 {{ r }} {{ cr.tmp }} ;;
 {{ v('SUB',extra='; INC ' ~ r ~ ' 1 ; ' ~ st(r,ds)) }}
{% endmacro %}
{% macro parts(r,op='ADD',ds=full,base=cr.tmp,extra='') %}
 LD.MULT R0 {{ r }} {{ base }} ;;
 {{ v(op,extra='; INC ' ~ r ~ ' 1 ; LD.MULT R0 ' ~ r ~ ' ' ~ base,ds=ds) }}
 {{ v(op.split('.')[0],extra=extra,ds=ds) }}
{% endmacro %}
{% macro rc(r='LR0',op='ADD',extra='',ds=full) %}
 MULT.RC.VV {{ r }} R0 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }} {{ extra }} ;;
{% endmacro %}
{% macro save(n,ds=full) %}{{ at('LR1',n) }}{{ encode('LR1',ds) }}{% endmacro %}

 SET LR8 CR0 ; SET LR9 CR0 ; SET LR12 CR0 ;;
 {{ at('LR15',in0_d0) }}
 {% if stride == 64 %}
 SET LR14 {{ cr.pair_dst }} ;;
 {% for i in range(6) %}ADD LR14 LR14 LR14 ;;{% endfor %}
 {% else %}{{ at('LR14',128) }}{% endif %}
 batch:
 SET LR10 LR9 ; SET LR13 CR0 ;;
 {{ at('LR11',in0_d1) }}
 token:
 SET LR7 LR10 ; SET LR1 LR13 ; SET LR4 CR0 ;;
 {% macro gather(label,count) %}
 SET LR2 CR0 ; SET LR3 CR0 ;;
 {% if stride%128 == 0 or stride == 64 %}
 {% set paired = stride == 64 %}
 {% set step = 1 if paired else stride//128 %}
 {% set width = 2 if paired else 1 %}
 {% set ptr = 'LR5' if paired else 'LR1' %}
 {% if paired %}
 SET LR5 LR1 ; SET LR1 LR14 ; SET LR3 {{ cr.pair_dst }} ;;
 {% endif %}
 {{ at('LR6',count//width-2) }}
 LD.MULT R0 {{ ptr }} {{ cr.in1 }} ;;
 {% macro scatter(first=false,last=false) %}
 {% if paired %}MULT.VE LR7 CR1 0 LR0 {{ full }} {{ qr }}{% else %}MULT.EE LR7 CR1 0 LR0 {{ full }} {{ qr }}{% endif %} ; ACC.RESHAPE LRD0 LRD2 {{ 8-width }} ; INC {{ ptr }} {{ step }} {% if not first %}; ADDBI LRD2 {{ width }}{% endif %}{% if not last %}; LD.MULT R0 {{ ptr }} {{ cr.in1 }}{% if not first %}; DEC LR6 1 ; BLT.S CR1 LR6 gather_{{ label }}{% endif %}{% endif %} ;;
 {% endmacro %}
 {{ scatter(first=true) }}
 gather_{{ label }}:
 {{ scatter() }}
 {{ scatter(last=true) }}
 {% if stride == 64 %}
 SET LR1 LR5 ;;
 {% endif %}
 {% else %}
 {{ at('LR6',count) }}
 gather_{{ label }}:
 LD.MULT R0 LR1 {{ cr.in1 }} ;;
 MULT.EE LR7 CR1 0 LR0 {{ full }} {{ qr }} ; ACC.RESHAPE LRD0 LRD2 7 ; DEC LR6 1 {% if stride//128 %}; INC LR1 {{ stride//128 }}{% endif %} ;;
 {% if stride%128 %}
 INC LR7 {{ stride%128 }} ;;
 BLT.S LR7 LR14 gather_{{ label }}_nowrap ;;
 DEC LR7 128 ; INC LR1 1 ;;
 gather_{{ label }}_nowrap:
 {% endif %}
 ADDBI LRD2 1 ; BNE LR6 CR0 gather_{{ label }} ;;
 {% endif %}
 {% endmacro %}
 {% macro dot(label,count) %}
 LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR4 1 ; SET LR3 CR0 ;;
 {% if count > 1 %}
 LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; DEC LR3 1 ; SET LR6 CR0 ;;
 {% if count >= 4 %}INC LR6 {{ count-3 }} ;;{% elif count == 2 %}DEC LR6 1 ;;{% endif %}
 {{ label }}:
 MULT.RC.VE LR0 LR3 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; INC LR3 1 ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; BLT.S LR3 LR6 {{ label }} ;;
 {% else %}LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; DEC LR3 1 ;;{% endif %}
 MULT.RC.VE LR0 LR3 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; INC LR3 1 ; INC LR1 1 ;;
 {% endmacro %}
 {% macro gemm(label) %}
 SET LR1 LR8 ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% if krows > 1 %}
 {{ at('LR2',krows-1) }}
 gemm_chunk_{{ label }}:
 {{ dot('gemm_full_' ~ label,128) }}
 DEC LR2 1 ;;
 BNE LR2 CR0 gemm_chunk_{{ label }} ;;
 {% endif %}
 {{ dot('gemm_tail_' ~ label,(s0_k-1)%128+1) }}
 {% endmacro %}
 {# Keep the wide tile output-parallel; pack narrow-tail weights along K. #}
 {{ gather('head',128) }}
 SET LR5 LR1 ;;
 {{ gemm('head') }}
 {{ save(32) }}
 INC LR4 1 ; SET LR1 LR5 ;;
 {{ gather('tail',s0_n-128) }}
 {% if narrow %}
 LD.MULT R0 LR4 {{ cr.w }} ;;
 {{ v(ds=tail) }}
 SET LR1 LR8 ; SET LR3 CR0 ;;
 DEC LR1 1 ; DEC LR3 1 ;;
 {% set slots = ['LR0','LR5','LR6','LR7'] %}
 {% for j in range(krows) %}
 {% if j %}{{ at(slots[j],128*j) }}{% endif %}
 LD.MULT.CYCLIC LR1 {{ cr.in0 }} {{ slots[j] }} ; INC LR1 1 ;;
 {% endfor %}
 {{ at('LR2',s0_n-130-(1 if krows == 1 else 0)) }}
 INC LR4 1 ; LD.MULT R0 LR4 {{ cr.w }} ;;
 narrow_tail:
 {% macro narrow_dot(last=false) %}
 {% for j in range(krows) %}
 MULT.RC.VV {{ slots[j] }} R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR3 {{ full }} {% if not (last and loop.last) %}; INC LR4 1 ; LD.MULT R0 LR4 {{ cr.w }}{% endif %}{% if loop.first %}; INC LR3 1{% endif %}{% if loop.last and not last %}; BLT.S LR3 LR2 narrow_tail{% endif %} ;;
 {% endfor %}
 {% endmacro %}
 {{ narrow_dot() }}
 {{ narrow_dot(last=true) }}
 {% else %}{{ gemm('tail') }}{% endif %}
 {{ save(34,tail) }}

 {# Reduce directly into scalar lane zero, then broadcast the compensated sum. #}
 {% macro reduce(src,ds,first=false) %}
 {{ at('LR1',src) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.SUM{% if first %}.FIRST{% endif %} LR0 {{ ds }} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 {% endmacro %}
 {% macro avg() %}
 {# Only lane zero contains the sum; store with a one-lane DS. #}
 {{ save(0,cr.scalar ~ '.L') }}
 SET LR1 CR0 ; SET LR2 CR0 ;;
 LD.MULT.CYCLIC LR2 {{ cr.crow }} LR0 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; INC LR2 1 ; LD.MULT.CYCLIC LR2 {{ cr.crow }} LR0 ;;
 MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; SET LR1 CR0 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% endmacro %}
 {{ reduce(32,full,true) }}
 {{ reduce(34,tail) }}
 {{ avg() }}
 {{ save(2) }}

 {{ at('LR5',128) }}
 {{ at('LR6',256) }}
 {{ at('LR1',2) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR5 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR6 ;;
 {% for ds in [full,tail] %}
 {{ at('LR1',32+2*loop.index0) }}
 {{ parts('LR1','ADD.FIRST',ds) }}
 MULT.RC.VE LR5 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
 MULT.RC.VE LR6 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
 {{ save(36+2*loop.index0,ds) }}
 {% endfor %}

 {% for ds in [full,tail] %}
 {{ at('LR1',36+2*loop.index0) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 MULT.RC.VS LR0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM{% if loop.first %}.FIRST{% endif %} LR0 {{ ds }} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR5 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 MULT.RC.VS LR5 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 {% endfor %}
 {{ avg() }}
 {{ at('LR1',2) }}
 LD.MULT R0 LR1 {{ cr.crow }} ;;
 {{ v() }}
 {{ at('LR1',4) }}
 {{ st('LR1',act='rsqrt') }} ;;
 {{ save(6) }}
 {# Refine the stored reciprocal root with one Newton step. #}
 {{ at('LR1',4) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 LD.MULT R0 LR1 {{ cr.crow }} ;;
 {{ rc(op='ADD.FIRST',extra='; INC LR1 4 ; ' ~ st('LR1')) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ rc(op='ADD.FIRST') }}
 {{ save(10) }}
 {{ at('LR1',3) }}
 LD.MULT R0 LR1 {{ cr.crow }} ;;
 {{ v('ADD.FIRST') }}
 {% for a in [10,11] %}
 {{ at('LR1',a) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {{ at('LR1',6) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ rc(op='SUB',extra='; INC LR1 1 ; LD.MULT R0 LR1 ' ~ cr.tmp) }}
 {{ rc(op='SUB') }}
 {% endfor %}
 {{ save(12) }}
 {{ at('LR1',4) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {{ at('LR1',12) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ rc(op='ADD.FIRST',extra='; INC LR1 1 ; LD.MULT R0 LR1 ' ~ cr.tmp) }}
 {{ rc() }}
 {{ save(14) }}

 {{ at('LR1',14) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR5 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR6 ;;
 {% for ds in [full,tail] %}
 {% set i = loop.index0 %}
 {{ at('LR4',2*i) }}
 {{ at('LR1',16) }}
 LD.MULT R0 LR4 {{ cr.affine }} ;;
 {{ rc('LR5','ADD.FIRST',ds=ds) }}
 {{ rc('LR6',extra='; INC LR4 1 ; LD.MULT R0 LR4 ' ~ cr.affine,ds=ds) }}
 {{ rc('LR5',ds=ds) }}
 {{ rc('LR6',extra='; ' ~ st('LR1',ds),ds=ds) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ v('SUB',extra='; INC LR1 1 ; ' ~ st('LR1',ds),ds=ds) }}
 DEC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {{ at('LR4',36+2*i) }}
 LD.MULT R0 LR4 {{ cr.tmp }} ;;
 {{ rc(op='ADD.FIRST',extra='; INC LR1 1 ; LD.MULT.CYCLIC LR1 ' ~ cr.tmp ~ ' LR0',ds=ds) }}
 {{ rc(extra='; INC LR4 1 ; LD.MULT R0 LR4 ' ~ cr.tmp,ds=ds) }}
 {{ rc(extra='; DEC LR1 1 ; LD.MULT.CYCLIC LR1 ' ~ cr.tmp ~ ' LR0',ds=ds) }}
 {{ rc(ds=ds) }}
 {{ at('LR4',4+2*i) }}
 {{ parts('LR4',base=cr.affine,ds=ds,extra='; ACTIVATE.QUANTIZE ' ~ (act_out0 | default('identity')) ~ ' ' ~ ds ~ ' ' ~ cr.qf_out0 ~ '.L ' ~ cr.out0 ~ ' LR12') }}
 INC LR12 1 ;;
 {% endfor %}

 INC LR8 {{ krows }} ; INC LR10 {{ in1_d0 }} ; DEC LR11 1 ;;
 {% if stride != 64 %}
 BLT.S LR10 LR14 token_nowrap ;;
 DEC LR10 128 ; INC LR13 1 ;;
 token_nowrap:
 {% endif %}
 BNE LR11 CR0 token ;;
 INC LR9 1 ; DEC LR15 1 ;;
 BNE LR15 CR0 batch ;;
 HALT ;;
