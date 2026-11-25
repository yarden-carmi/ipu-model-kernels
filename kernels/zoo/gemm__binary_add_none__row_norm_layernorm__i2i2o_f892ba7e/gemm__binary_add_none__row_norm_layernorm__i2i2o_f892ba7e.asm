{% set q = cr.qf_in0 ~ '.L' %}
{% set work = cr.work_config ~ '.H' %}
{% set qr = cr.qf_in1 ~ '.L' %}
{% set rootq = cr.scalar ~ '.H' %}
{% set kr = (s0_k+127)//128 %}
{% set pair = 2 if s0_m == 64 else 1 %}
{% set wide = pair == 1 %}
{% set parts = 3 if wide else 2 %}
{% set aq = cr.tile_config ~ '.H' %}
{% set step = (s0_m+127)//128 %}
{% set slots = ['LR0','LR5','LR6','LR7'] %}
{% macro v(op='ADD', fmt=work, extra='') %}
MULT.VE LR0 CR1 0 LR0 CR15.L {{ fmt }} ; ACC.{{ op }} {{ extra }} ;;
{% endmacro %}
{% macro vv(slot='LR0',op='ADD',extra='',fmt=work) %}
MULT.RC.VV {{ slot }} R0 0 LR0 CR15.L {{ fmt }} ; ACC.{{ op }} {{ extra }} ;;
{% endmacro %}
{% macro st(ptr,fmt=work,act='identity') %}ACTIVATE.QUANTIZE {{ act }} CR15.L {{ fmt }} {{ cr.tmp }} {{ ptr }}{% endmacro %}
{% macro split(ptr) %}
{{ st(ptr) }} ;;
LD.MULT R0 {{ ptr }} {{ cr.tmp }} ;;
{{ v('SUB',extra='; INC '~ptr~' 1 ; '~st(ptr)) }}
{% endmacro %}
{% macro start() %}
SET LR11 {{ cr.tile_config }}.L ; SET LR10 CR0 ;;
INC LR10 {{ 48 if wide else 16 }} ;;
{% endmacro %}
SET LR0 CR0 ; SET LR5 CR0 ; SET LR12 CR0 ;;
INC LR5 128 ; SET LR8 CR0 ; SET LR14 CR0 ;;
ADD LR6 LR5 LR5 ; INC LR14 64 ;;
ADD LR7 LR5 LR6 ;;
block:
{{ start() }}
SET LR4 CR0 ; SET LR9 LR12 ;;
{% if wide %}DEC LR10 1 ;;{% endif %}
channel:
LD.MULT R0 LR9 {{ cr.in1 }} {% if wide %}; INC LR10 1{% endif %} ;;
{{ v('ADD.FIRST',qr,'; LD.MULT.CYCLIC LR4 '~cr.w~' LR0 ; SET LR2 CR0 ; SET LR3 CR0') }}
{% for p in range(pair) %}
{% set limit = (p+1)*128//pair - 2 - (1 if kr == 1 else 0) %}
{% for j in range(kr) %}
{% if j or p %}INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slots[j] }} {% if j == 1 %}; INC LR3 {{ limit if not p else 64 }}{% endif %} {% if j==2 and not p %}; DEC LR2 1{% endif %} ;;{% endif %}
{% endfor %}
{% if kr < 3 and not p %}DEC LR2 1 ;;{% endif %}
{% if kr == 1 %}INC LR3 {{ limit if not p else 64 }} ;;{% endif %}
SET LR1 LR8 ; LD.MULT R0 LR8 {{ cr.in0 }} ;;
token_{{ p }}:
{% macro dot(p,last=false) %}
{% for j in range(kr) %}
MULT.RC.VV {{ slots[j] }} R0 0 LR0 CR15.L {{ q }} ; AGG.SUM LR2 CR15.L {% if j==0 %}; INC LR2 1{% endif %}
{% if not (last and loop.last) %}; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.in0 }}{% elif p+1 == pair %}; INC LR4 1 ; LD.MULT R0 LR4 {{ cr.w }}{% endif %}
{% if loop.last and not last %}; BLT.S LR2 LR3 token_{{ p }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{{ dot(p) }}
{{ dot(p,true) }}
{% endfor %}
{% if wide %}{{ v(fmt=q,extra='; INC LR4 1 ; LD.MULT R0 LR4 '~cr.w) }}{% endif %}
{{ v(fmt=q,extra='; '~st('LR10')~' ; INC LR4 1 ; INC LR9 '~step) }}
LD.MULT R0 LR10 {{ cr.tmp }} ;;
{% if wide %}{% for i in range(2) %}
{{ v('SUB',extra='; INC LR10 1 ; '~st('LR10')) }}
LD.MULT R0 LR10 {{ cr.tmp }} ;;
{% endfor %}{% endif %}
{{ v('SUB',extra='; INC LR10 1 ; '~st('LR10')~' ; DEC LR11 1' ~ (' ; BLT.S CR1 LR11 channel' if wide else '')) }}
{% if not wide %}
INC LR10 1 ; BNE LR11 CR0 channel ;;
{% endif %}

{% if wide %}
{# Small, wide-exponent expansions for the block's normalization scalars. #}
{% macro seek(reg,n) %}SET {{ reg }} CR0 ;;{% if n %}INC {{ reg }} {{ n }} ;;{% endif %}{% endmacro %}
{% macro expand(n,count) %}
{{ seek('LR1',n) }}
{{ st('LR1') }} ;;
{% for i in range(count-1) %}
LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ v('SUB',extra='; INC LR1 1 ; '~st('LR1')) }}
{% endfor %}
{% endmacro %}
{% macro mul(a,b,na=3,nb=3) %}
{{ seek('LR1',b) }}
{% for j in range(nb) %}
{% if j %}INC LR1 1 ; {% endif %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} {{ slots[j] }} ;;
{% endfor %}
{{ seek('LR1',a) }}
LD.MULT R0 LR1 {{ cr.tmp }} ;;
{% for i in range(na) %}
{% for j in range(nb) %}
{{ vv(slots[j],op='ADD.FIRST' if i==0 and j==0 else 'ADD',extra='; INC LR1 1 ; LD.MULT R0 LR1 '~cr.tmp if loop.last and i+1<na else '') }}
{% endfor %}
{% endfor %}
{% endmacro %}
{# Re-encode the reciprocal coefficient once, rather than narrowing the sum. #}
SET LR13 CR0 ; LD.MULT R0 LR0 {{ cr.crow }} ;;
{{ v('ADD.FIRST',aq,'; INC LR13 1 ; LD.MULT R0 LR13 '~cr.crow) }}
{{ v(fmt=aq) }}
{{ expand(0,4) }}
{{ start() }}
LD.MULT R0 LR10 {{ cr.tmp }} ;;
MULT.VE LR0 CR0 0 LR0 CR15.L {{ work }} ; ACC.ADD.FIRST ; DEC LR11 1 ;;
wide_sum:
{% macro wsum(last=false) %}
{% for i in range(4) %}
{{ v(extra='; INC LR10 1 ; LD.MULT R0 LR10 '~cr.tmp ~ (' ; DEC LR11 1 ; BLT.S CR1 LR11 wide_sum' if loop.last else '') if not(last and loop.last) else '') }}
{% endfor %}
{% endmacro %}
{{ wsum() }}
{{ wsum(true) }}
{{ expand(4,4) }}
{{ mul(4,0,4,4) }}
{{ expand(8,4) }}

{{ start() }}
MULT.VE LR0 CR0 0 LR0 CR15.L {{ work }} ; ACC.ADD.FIRST ; DEC LR11 1 ;;
LD.MULT.CYCLIC LR10 {{ cr.tmp }} LR0 ;;
wide_var:
{% macro wvar(last=false) %}
MULT.RC.VS LR0 0 LR0 CR15.L {{ work }} ; ACC.ADD ; INC LR10 1 ; LD.MULT R0 LR10 {{ cr.tmp }} ;;
{{ vv(extra='; LD.MULT.CYCLIC LR10 '~cr.tmp~' LR5') }}
{{ vv(extra='; INC LR10 1 ; LD.MULT R0 LR10 '~cr.tmp) }}
{{ vv() }}
{{ vv() }}
MULT.RC.VS LR5 0 LR0 CR15.L {{ work }} ; ACC.ADD {% if not last %}; INC LR10 2 ; LD.MULT.CYCLIC LR10 {{ cr.tmp }} LR0 ; DEC LR11 1 ; BLT.S CR1 LR11 wide_var{% endif %} ;;
{% endmacro %}
{{ wvar() }}
{{ wvar(true) }}
{{ expand(4,4) }}
{{ mul(4,0,4,4) }}
{{ expand(12,4) }}
{{ mul(8,8,4,4) }}
{{ expand(32,4) }}
{% for i in range(4) %}
{{ seek('LR1',12+i) }}
LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ v('ADD' if i else 'ADD.FIRST') }}
{% endfor %}
{% for i in range(4) %}
{{ seek('LR1',32+i) }}
LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ v('SUB') }}
{% endfor %}
{# Preserve the variance while quantizing epsilon in the wider format. #}
{{ expand(12,4) }}
{{ seek('LR13',2) }}
LD.MULT R0 LR13 {{ cr.crow }} ;;
{{ v('ADD.FIRST',aq) }}
{{ seek('LR1',16) }}
{{ st('LR1') }} ;;
LD.MULT R0 LR1 {{ cr.tmp }} ;;
{% for i in range(4) %}
{{ seek('LR1',12+i) }}
LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ work }} ; ACC.ADD ;;
{% endfor %}
{{ seek('LR1',17) }}
{{ st('LR1',rootq,'rsqrt') }} ;;
{{ expand(12,4) }}
{{ seek('LR1',17) }}
LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ v('ADD.FIRST',rootq) }}
{{ expand(18,3) }}
{{ seek('LR13',3) }}
SET LR3 CR0 ;;
INC LR3 2 ;;
refine:
{{ mul(18,18) }}
{{ expand(21,3) }}
{{ mul(12,21,4,3) }}
{{ expand(24,3) }}
{{ mul(18,24) }}
{{ expand(27,3) }}
LD.MULT R0 LR13 {{ cr.crow }} ;;
{{ v('ADD.FIRST',aq) }}
{{ seek('LR1',31) }}
{{ st('LR1') }} ;;
LD.MULT R0 LR1 {{ cr.tmp }} ;;
{% for i in range(3) %}
{{ seek('LR1',18+i) }}
LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
{{ vv(op='ADD.FIRST' if loop.first else 'ADD') }}
{% endfor %}
{% for i in range(3) %}
{{ seek('LR1',27+i) }}
LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
{{ vv(op='SUB') }}
{% endfor %}
{% for i in range(3) %}
{{ seek('LR1',18+i) }}
LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ work }} ; ACC.ADD ;;
{% endfor %}
{{ expand(18,3) }}
DEC LR3 1 ; BLT.S CR1 LR3 refine ;;
{{ mul(8,18,4,3) }}
{{ expand(36,3) }}
{% for i in range(3) %}
{{ seek('LR1',18+i) }}
LD.MULT.CYCLIC LR1 {{ cr.tmp }} {{ slots[i+1] }} ;;
{% endfor %}
{% else %}
{% macro avg() %}
SET LR1 CR0 ; SET LR13 CR0 ;;
{{ split('LR1') }}
LD.MULT R0 LR13 {{ cr.crow }} ; SET LR1 CR0 ;;
{% for j in range(2) %}
{% for i in range(2) %}
LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
{% if pair==2 %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR5 ;;{% endif %}
{{ vv(op='ADD.FIRST' if i==0 and j==0 else 'ADD',extra=('; INC LR1 1' if i==0 else '')) }}
{% if pair==2 %}{{ vv('LR14') }}{% endif %}
{% endfor %}
INC LR13 1 ; {% if loop.first %}LD.MULT R0 LR13 {{ cr.crow }} ; SET LR1 CR0{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro clear() %}MULT.VE LR0 CR0 0 LR0 CR15.L {{ q }} ; ACC.ADD.FIRST ;;{% endmacro %}
{{ start() }}
{{ clear() }}
LD.MULT R0 LR10 {{ cr.tmp }} ; DEC LR11 1 ;;
sum:
{{ v(extra='; INC LR10 1 ; LD.MULT R0 LR10 '~cr.tmp) }}
{{ v(extra='; INC LR10 1 ; LD.MULT R0 LR10 '~cr.tmp~' ; DEC LR11 1 ; BLT.S CR1 LR11 sum') }}
{{ v(extra='; INC LR10 1 ; LD.MULT R0 LR10 '~cr.tmp) }}
{{ v() }}
{{ avg() }}
SET LR1 CR0 ;;
INC LR1 2 ; {{ st('LR1') }} ;;
LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ v('SUB',extra='; INC LR1 1 ; '~st('LR1')) }}
LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR6 ;;
DEC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR5 ;;
{{ start() }}
center:
LD.MULT R0 LR10 {{ cr.tmp }} ; SET LR1 LR10 ;;
{{ v('ADD.FIRST',extra='; INC LR10 1 ; LD.MULT R0 LR10 '~cr.tmp) }}
{{ v() }}
{% for slot in ['LR5','LR6'] %}
MULT.RC.VE {{ slot }} CR1 0 LR0 CR15.L {{ work }} ; ACC.SUB {% if loop.last %}; {{ st('LR1') }}{% endif %} ;;
{% endfor %}
LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ v('SUB',extra='; INC LR1 1 ; '~st('LR1')~' ; INC LR10 1 ; DEC LR11 1 ; BLT.S CR1 LR11 center') }}

{{ start() }}
{{ clear() }}
LD.MULT.CYCLIC LR10 {{ cr.tmp }} LR0 ; DEC LR11 1 ;;
{% macro var(last=false) %}
MULT.RC.VS LR0 0 LR0 CR15.L {{ work }} ; ACC.ADD ; INC LR10 1 ; LD.MULT R0 LR10 {{ cr.tmp }} ;;
{{ vv() }}
{{ vv(extra='; INC LR10 1 ; LD.MULT.CYCLIC LR10 '~cr.tmp~' LR0 ; DEC LR11 1 ; BLT.S CR1 LR11 variance' if not last else '') }}
{% endmacro %}
variance:
{{ var() }}
{{ var(true) }}
{{ avg() }}
SET LR1 CR0 ; LD.MULT R0 LR13 {{ cr.crow }} ;;
{{ v(extra='; INC LR1 4 ; '~st('LR1',rootq,'rsqrt')) }}
LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ v('ADD.FIRST',rootq,'; INC LR1 1 ; '~st('LR1')) }}
LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ v('SUB',extra='; LD.MULT.CYCLIC LR1 '~cr.tmp~' LR5') }}
INC LR1 1 ; {{ st('LR1') }} ;;
LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR6 ;;
{% endif %}
{{ start() }}
SET LR9 LR12 ; SET LR13 CR0 ; SET LR15 CR0 ;;
INC LR15 7 {% if pair==2 %}; SET LR1 CR0 ; ADD LR2 LR7 LR14{% endif %} ;;
{% if wide %}{{ seek('LR2',20) }}{% else %}
INC LR1 9 ;;{% endif %}
{% if wide %}LD.MULT R0 LR10 {{ cr.tmp }} ;;{% endif %}
normalize:
{% if not wide %}LD.MULT R0 LR10 {{ cr.tmp }} ;;{% endif %}
{{ vv('LR5','ADD.FIRST') }}
{% if wide %}{{ vv('LR6') }}{{ vv('LR7',extra='; INC LR10 1 ; LD.MULT R0 LR10 '~cr.tmp) }}
{{ vv('LR5') }}{{ vv('LR6') }}{{ vv('LR7',extra='; INC LR10 1 ; LD.MULT R0 LR10 '~cr.tmp) }}
{{ vv('LR5') }}{{ vv('LR6',extra='; INC LR10 1 ; LD.MULT R0 LR10 '~cr.tmp) }}
{{ vv('LR5',extra='; SET LR1 CR0') }}
INC LR1 36 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ v('SUB',extra='; INC LR1 1 ; LD.MULT R0 LR1 '~cr.tmp) }}
{{ v('SUB',extra='; INC LR1 1 ; LD.MULT R0 LR1 '~cr.tmp) }}
{{ v('SUB',extra='; '~st('LR15',aq)) }}
{% else %}
{{ vv('LR6',extra='; INC LR10 1 ; LD.MULT R0 LR10 '~cr.tmp) }}
{{ vv('LR5') }}
{{ vv('LR6',extra='; '~st('LR15')) }}
{% endif %}
LD.MULT R0 LR15 {{ cr.tmp }} ;;
{{ v('SUB',aq,extra='; LD.MULT.CYCLIC LR15 '~cr.tmp~' LR0 ; INC LR10 1') }}
INC LR15 1 ; {{ st('LR15',aq) }} ; LD.MULT R0 LR13 {{ cr.affine }} ;;
{{ vv('LR0','ADD.FIRST',fmt=aq,extra='; LD.MULT.CYCLIC LR15 '~cr.tmp~' LR7') }}
{{ vv('LR7',extra='; INC LR13 1 ; LD.MULT R0 LR13 '~cr.affine~' ; DEC LR15 1',fmt=aq) }}
{{ vv(fmt=aq) }}
{{ vv('LR7',extra='; INC LR13 1 ; LD.MULT R0 LR13 '~cr.affine,fmt=aq) }}
{{ v(fmt=aq,extra='; INC LR13 1 ; LD.MULT R0 LR13 '~cr.affine) }}
{% set output = 'ACTIVATE.QUANTIZE '~(act_out0|default('identity'))~' '~(cr.scalar~'.L' if pair==2 else 'CR15.L')~' '~cr.qf_out0~'.L '~cr.out0~' LR9' %}
{{ v(fmt=aq,extra='; INC LR13 1 ; DEC LR11 1 ; '~output ~ (' ; LD.MULT.CYCLIC LR2 '~cr.tmp~' LR7' if wide else '')) }}
{% if pair==2 %}
{{ st('LR15') }} ; INC LR9 1 ;;
LD.MULT R0 LR15 {{ cr.tmp }} ;;
{{ v('SUB',extra='; LD.MULT.CYCLIC LR15 '~cr.tmp~' LR0 ; '~st('LR1')) }}
LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR7 ;;
MULT.RC.VE LR14 CR1 0 LR0 CR15.L {{ work }} ; ACC.ADD.FIRST ;;
MULT.RC.VE LR2 CR1 0 LR0 CR15.L {{ work }} ; ACC.ADD ; {{ output }} ;;
{% endif %}
INC LR9 {{ step }} {% if wide %}; LD.MULT R0 LR10 {{ cr.tmp }}{% endif %} ; BNE LR11 CR0 normalize ;;
INC LR8 {{ 128*kr if kr==1 else 128 }} ; INC LR12 1 ;;
{% if kr>1 %}{% for i in range(kr-1) %}INC LR8 128 ;;{% endfor %}{% endif %}
BLT.S LR12 {{ cr.work_config }}.L block ;;
HALT ;;
