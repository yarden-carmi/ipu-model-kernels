{% set q = cr.qf_in0 ~ '.L' %}
{% set qr = cr.qf_in1 ~ '.L' %}
{% set full = 'CR15.L' %}
{% set tail = cr.tail ~ '.L' %}
{% set krows = (s0_k+127)//128 %}
{% set m = in1_d0 * in1_d1 %}
{% set packed = (m == 64 or m % 128 == 0) and in1_d0 in [1,2,4] %}
{% set narrow = krows <= 4 and (s0_n-128)*krows < s0_k %}
{% macro at(r,n) %}
 SET {{ r }} CR0 ;;
 {% for i in range(n//255) %}INC {{ r }} 255 ;;{% endfor %}
 {% if n%255 %}INC {{ r }} {{ n%255 }} ;;{% endif %}
{% endmacro %}
{% macro v(op='ADD',imm='CR1',extra='',ds=full,fmt=q) %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ ds }} {{ fmt }} ; ACC.{{ op }} {{ extra }} ;;
{% endmacro %}
{% macro st(r,ds=full,act='identity') %}ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ q }} {{ cr.tmp }} {{ r }}{% endmacro %}
{% macro rc(r='LR0',op='ADD',extra='',ds=full) %}
 MULT.RC.VV {{ r }} R0 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }} {{ extra }} ;;
{% endmacro %}

 {% macro bytes(lo,hi) %}
 SET {{ lo }} {{ cr.byte_seq }} ; SET {{ hi }} {{ cr.byte_seq }} ;;
 ADDBI LRD{{ lo[2:] }} 4 ;;
 SET {{ lo }} {{ cr.byte_seq }} ;;
 {% endmacro %}
 {% macro move8(extra='') %}
 MULT.VE LR7 CR1 0 LR7 {{ full }} {{ qr }} ; ACC.RESHAPE LRD0 LRD2 0 {{ extra }} ;;
 {% endmacro %}
 SET LR8 CR0 ; SET LR12 CR0 ; SET LR9 CR0 ;;
 {{ at('LR15',in0_d0) }}
 batch:
 SET LR10 LR9 ; SET LR13 CR0 ;;
 {{ at('LR11',in0_d1) }}
 group:
 {% if packed %}
 {# Transpose 8 tokens by 8 channels at a time from the strided residual view. #}
 SET LR14 CR0 ; SET LR4 LR13 ; SET LR7 CR0 ;;
 {{ at('LR5',40) }}
 {{ at('LR6',s0_n//8-1) }}
 {{ bytes('LR0','LR1') }}
 {% for i in range(2 if in1_d0 == 4 else 1 if in1_d0 == 2 else 0) %}
 ADD LR0 LR0 LR0 ; ADD LR1 LR1 LR1 ;;
 {% endfor %}
 ADDB LRD0 LR10 ;;
 {{ bytes('LR2','LR3') }}
 {% if m == 64 %}ADDBI LRD0 64 ;;{% endif %}
 pack_residual:
 LD.MULT R0 LR4 {{ cr.in1 }} ;;
 {% for j in range(8) %}
 {% set reload = j < 7 and (m != 64 or j % 2 == 1) %}
 {{ move8(('; INC LR4 ' ~ (1 if m == 64 else m//128) if m != 64 or j%2 else '') ~
          ('; LD.MULT R0 LR4 ' ~ cr.in1 if reload else '') ~
          ('; ADDBI LRD0 ' ~ (-64 if j%2 == 0 else 64) if m == 64 else '') ~
          ('; ADDBI LRD2 8' if j else '') ~
          ('; ACTIVATE.QUANTIZE identity ' ~ full ~ ' ' ~ qr ~ ' ' ~ cr.tmp ~ ' LR5' if j == 7 else '')) }}
 {% endfor %}
 INC LR5 1 ; DEC LR6 1 ; ADDBI LRD2 -56 ; BLT.S CR0 LR6 pack_residual ;;
 {% endif %}
 token:
 {% macro residual(label,count,src) %}
 {% if packed %}
 SET LR7 CR0 ;;
 {{ bytes('LR0','LR1') }}
 {% for i in range(3) %}ADD LR0 LR0 LR0 ; ADD LR1 LR1 LR1 ;;{% endfor %}
 ADDB LRD0 LR14 ;;
 {{ bytes('LR2','LR3') }}
 {{ at('LR5',src) }}
 {{ at('LR6',count//8-2) }}
 LD.MULT R0 LR5 {{ cr.tmp }} ;;
 {{ move8('; INC LR5 1 ; LD.MULT R0 LR5 ' ~ cr.tmp) }}
 {% if count > 16 %}
 unpack_{{ label }}:
 {{ move8('; ADDBI LRD2 8 ; INC LR5 1 ; LD.MULT R0 LR5 ' ~ cr.tmp ~ ' ; DEC LR6 1 ; BLT.S CR1 LR6 unpack_' ~ label) }}
 {% endif %}
 {{ move8('; ADDBI LRD2 8') }}
 SET LR0 CR0 ;;
 {% else %}
 {% if src == 40 %}SET LR7 LR10 ; SET LR5 LR13 ;;{% endif %}
 SET LR2 CR0 ; SET LR3 CR0 ;;
 {{ at('LR6',count) }}
 {{ at('LR1',128) }}
 gather_{{ label }}:
 LD.MULT R0 LR5 {{ cr.in1 }} ;;
 MULT.EE LR7 CR1 0 LR0 {{ full }} {{ qr }} ; ACC.RESHAPE LRD0 LRD2 7 ; DEC LR6 1 {% if m//128 %}; INC LR5 {{ m//128 }}{% endif %} ;;
 {% if m%128 %}
 INC LR7 {{ m%128 }} ;;
 BLT.S LR7 LR1 nowrap_{{ label }} ;;
 DEC LR7 128 ; INC LR5 1 ;;
 nowrap_{{ label }}:
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
 {% if krows <= 4 %}
 {% for chunk in range(krows-1) %}
 {{ dot('gemm_full_' ~ label ~ '_' ~ chunk,128) }}
 {% endfor %}
 {% else %}
 {{ at('LR2',krows-1) }}
 gemm_chunk_{{ label }}:
 {{ dot('gemm_full_' ~ label,128) }}
 DEC LR2 1 ;;
 BNE LR2 CR0 gemm_chunk_{{ label }} ;;
 {% endif %}
 {{ dot('gemm_tail_' ~ label,(s0_k-1)%128+1) }}
 {% endmacro %}
 {# Keep the wide tile output-parallel; pack narrow-tail weights along K. #}
 {{ residual('head',128,40) }}
 SET LR4 CR0 ;;
 {{ gemm('head') }}
  SET LR1 CR0 ;;
  INC LR1 32 ; {{ st('LR1') }} ;;
  LD.MULT R0 LR1 {{ cr.tmp }} ; INC LR4 1 ;;
  {{ v('SUB',extra='; INC LR1 1 ; ' ~ st('LR1')) }}
 {{ residual('tail',s0_n-128,56) }}
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
 SET LR1 CR0 ;;
 INC LR1 34 ; {{ st('LR1',tail) }} ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ v('SUB',ds=tail,extra='; INC LR1 1 ; ' ~ st('LR1',tail)) }}

 {# Reduce directly into scalar lane zero, then broadcast the compensated sum. #}
 {% macro reduce(ds,first=false) %}
 INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.SUM{% if first %}.FIRST{% endif %} LR0 {{ ds }} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 {% endmacro %}
 {% macro avg() %}
 {# Only lane zero contains the sum; store with a one-lane DS. #}
 SET LR1 CR0 ; SET LR2 CR0 ; LD.MULT.CYCLIC LR0 {{ cr.crow }} LR0 ; {{ st('LR0',cr.scalar ~ '.L') }} ;;
 LD.MULT R0 LR0 {{ cr.tmp }} ;;
 {{ v('SUB',extra='; INC LR1 1 ; ' ~ st('LR1',cr.scalar ~ '.L')) }}
 MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; INC LR2 1 ; LD.MULT.CYCLIC LR2 {{ cr.crow }} LR0 ;;
 MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; SET LR1 CR0 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% endmacro %}
 DEC LR1 4 ;;
 {{ reduce(full,true) }}
 {{ reduce(tail) }}
 {{ avg() }}
 SET LR5 CR0 ;;
 INC LR5 128 ; INC LR1 2 ; {{ st('LR1') }} ;;
 ADD LR6 LR5 LR5 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ v('SUB',extra='; INC LR1 1 ; ' ~ st('LR1')) }}
 DEC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR5 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR6 ;;
 {% for ds in [full,tail] %}
 {{ 'INC LR1 29' if loop.first else 'DEC LR1 3' }} ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ v('ADD.FIRST',extra='; INC LR1 1 ; LD.MULT R0 LR1 ' ~ cr.tmp,ds=ds) }}
 {{ v(ds=ds) }}
 MULT.RC.VE LR5 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
 MULT.RC.VE LR6 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
 INC LR1 3 ; {{ st('LR1',ds) }} ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ v('SUB',ds=ds,extra='; INC LR1 1 ; ' ~ st('LR1',ds)) }}
 {% endfor %}

 {% for ds in [full,tail] %}
 {{ 'DEC LR1 3' if loop.first else 'INC LR1 1' }} ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 MULT.RC.VS LR0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM{% if loop.first %}.FIRST{% endif %} LR0 {{ ds }} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR5 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 MULT.RC.VS LR5 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 {% endfor %}
 {{ avg() }}
 INC LR1 2 ; LD.MULT R0 LR1 {{ cr.crow }} ;;
 {# Positive reciprocal roots fit the unsigned format's seven-bit mantissa. #}
 {{ v(extra='; INC LR1 2 ; ACTIVATE.QUANTIZE rsqrt ' ~ full ~ ' ' ~ cr.scalar ~ '.H ' ~ cr.tmp ~ ' LR1') }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ v('ADD.FIRST',fmt=cr.scalar ~ '.H',extra='; INC LR1 1 ; ' ~ st('LR1')) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ v('SUB',extra='; LD.MULT.CYCLIC LR1 ' ~ cr.tmp ~ ' LR5') }}
 INC LR1 1 ; {{ st('LR1') }} ;;
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR6 ; SET LR4 CR0 ;;
 {% for ds in [full,tail] %}
 {% set i = loop.index0 %}
 {% if i %}DEC LR4 3 ; {% endif %}LD.MULT R0 LR4 {{ cr.affine }} ;;
 {{ rc('LR5','ADD.FIRST',ds=ds,extra='; INC LR1 10' if not i else '') }}
 {{ rc('LR6',extra='; INC LR4 1 ; LD.MULT R0 LR4 ' ~ cr.affine,ds=ds) }}
 {{ rc('LR5',ds=ds) }}
 {{ rc('LR6',extra='; ' ~ st('LR1',ds),ds=ds) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ v('SUB',extra='; INC LR1 1 ; ' ~ st('LR1',ds),ds=ds) }}
 DEC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 INC LR4 35 ; LD.MULT R0 LR4 {{ cr.tmp }} ;;
 {{ rc(op='ADD.FIRST',extra='; INC LR1 1 ; LD.MULT.CYCLIC LR1 ' ~ cr.tmp ~ ' LR0',ds=ds) }}
 {{ rc(extra='; INC LR4 1 ; LD.MULT R0 LR4 ' ~ cr.tmp,ds=ds) }}
 {{ rc(extra='; DEC LR1 1 ; LD.MULT.CYCLIC LR1 ' ~ cr.tmp ~ ' LR0',ds=ds) }}
 {{ rc(ds=ds) }}
 DEC LR4 33 ; LD.MULT R0 LR4 {{ cr.affine }} ;;
 {{ v(extra='; INC LR4 1 ; LD.MULT R0 LR4 ' ~ cr.affine,ds=ds) }}
 {{ v(extra='; ACTIVATE.QUANTIZE ' ~ (act_out0 | default('identity')) ~ ' ' ~ ds ~ ' ' ~ cr.qf_out0 ~ '.L ' ~ cr.out0 ~ ' LR12',ds=ds) }}
 INC LR12 1 ;;
 {% endfor %}

 INC LR8 {{ krows }} ; DEC LR11 1 ;;
 {% if packed %}
 INC.MODP2 LR14 CR1 3 ;;
 BNE LR14 CR0 token ;;
 INC LR10 {{ 8*in1_d0 }} ;;
 {% else %}
 INC LR10 {{ in1_d0 }} ;;
 {% endif %}
 {{ at('LR7',128) }}
 BLT.S LR10 LR7 token_nowrap ;;
 DEC LR10 128 ; INC LR13 1 ;;
 token_nowrap:
 BNE LR11 CR0 group ;;
 INC LR9 1 ; DEC LR15 1 ;;
 BNE LR15 CR0 batch ;;
 HALT ;;
