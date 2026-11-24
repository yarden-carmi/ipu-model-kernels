{# The first nine tmp rows are work space; the rest hold the input transpose. #}
{% set qi = cr.qi ~ '.L' %}
{% set di = cr.channels ~ '.H' %}
{% set do = cr.channels ~ '.L' %}
{% set scalar = cr.qi ~ '.H' %}
{% set last = cr.dot_bounds ~ '.H' %}
{% set width_ds = cr.output ~ '.L' %}
{% set iw = cr.input_steps ~ '.L' %}
{% macro ix(n) %}
    SET LR11 CR0 ;;
    {% if n %}INC LR11 {{ n }} ;;{% endif %}
{% endmacro %}
{% macro tmp(n, reg, ra=false) %}
{{ ix(n) }}
{% if ra %}LD.MULT {{ reg }} LR11 {{ cr.tmp }} ;;
{% else %}LD.MULT.CYCLIC LR11 {{ cr.tmp }} {{ reg }} ;;{% endif %}
{% endmacro %}
{% macro helper(n, ra) %}
{{ ix(n) }}
    LD.MULT {{ ra }} LR11 {{ cr.helpers }} ;;
{% endmacro %}
{% macro ve(reg, s='CR1', op='ADD.FIRST', ds=di, q=qi) %}
    MULT.RC.VE {{ reg }} {{ s }} 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }}
{%- endmacro %}
{% macro vv(reg, ra, op='ADD.FIRST', ds=di) %}
    MULT.RC.VV {{ reg }} {{ ra }} 0 LR0 {{ ds }} {{ qi }} ; ACC.{{ op }}
{%- endmacro %}
{% macro ee(idx, op='ADD.FIRST', ds=di) %}
    MULT.EE {{ idx }} CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.{{ op }}
{%- endmacro %}
{% macro store(ds=di, fn='identity') %}
    ACTIVATE.QUANTIZE {{ fn }} {{ ds }} {{ qi }} {{ cr.tmp }} LR11
{%- endmacro %}
{% macro reduce(reg, slot='LR0') %}
    MULT.RC.VE {{ reg }} CR1 0 LR0 {{ di }} {{ qi }} ; AGG.MAX.FIRST {{ slot }} {{ di }} ; {{ store(scalar) }} ;;
{% endmacro %}
{% macro not_clamped() %}
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR2 ;;
    {{ ee('LR1') }} ;;
    {{ ve('LR2','CR1','SUB') }} ; {{ store(di,'relu') }} ;;
{% endmacro %}
{% macro threshold(k, negative, first) %}
    SET LR10 CR0 ;;
    INC LR10 {{ k + 4 }} ;;
    SET LR9 CR0 ;;
    INC LR9 {{ 3 if negative else 2 }} ;;
{{ ix(3) }}
{% if k % 2 == 0 %}
    {{ ve('LR0','LR9') }} ;;
    {{ ve('LR1','LR10','SUB') }} ; {{ store(di,'relu6') }} ;;
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR2 ;;
    {{ ee('LR8','SUB.FIRST') }} ;;
    {{ ve('LR2','CR1','ADD') }} ; {{ store(di,'relu') }} ;;
{% else %}
    {% if k == 3 %}{{ tmp(0,'LR2') }}{{ ix(3) }}{% endif %}
    {{ ve('LR1','LR10') }} ;;
    {{ ve('LR0','LR9','SUB') }}{% if k == 3 %} ;;
    {{ ve('LR2','CR1','ADD') }}{% endif %} ; {{ store(di,'relu6') }} ;;
    {{ not_clamped() }}
{% endif %}
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR2 ;;
{{ ix(6) }}
{% if first %}
    {{ ve('LR2') }} ; {{ store() }} ;;
{% else %}
    {{ ve('LR3') }} ;;
    {{ ve('LR2','CR1','SUB' if negative else 'ADD') }} ; {{ store() }} ;;
{% endif %}
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR3 ;;
{% endmacro %}
{% macro half_tie_down(i) %}
    SET LR10 CR0 ;;
    INC LR10 {{ 11 + i }} ;;
    {{ ix(3) }}
    {{ ve('LR2','LR10') }} ;;
    {{ ve('LR1','LR0','SUB') }} ; {{ store() }} ;;
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR3 ;;
    {{ ve('LR3','CR1','SUB.FIRST') }} ;;
    {{ ve('LR3','CR1','MAX') }} ; {{ store(di,'relu6') }} ;;
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR3 ;;
    {{ ee('LR8') }} ;;
    {{ ve('LR3','CR1','SUB') }} ; {{ store(di,'relu') }} ;;
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR3 ;;
    {{ ix(0) }}
    {% if i %}
      LD.MULT R1 LR11 {{ cr.tmp }} ;;
      {{ ve('LR3') }} ;;
      MULT.VE LR1 CR1 0 LR0 {{ di }} {{ qi }} ; ACC.MAX ; {{ store() }} ;;
      {{ helper(0,'R1') }}
    {% else %}
      {{ ve('LR3') }} ; {{ store() }} ;;
    {% endif %}
{% endmacro %}
{% macro wload(reg='LR0',ra=false) %}
{% if ra %}LD.MULT {{ reg }} LR9 {{ cr.weights }} ; INC LR9 1 ;;
{% else %}LD.MULT.CYCLIC LR9 {{ cr.weights }} {{ reg }} ; INC LR9 1 ;;{% endif %}
{% endmacro %}
{% macro dot_term(ra,op='ADD',step=false) %}
    {{ wload() }}
    {{ ve('LR0',ra,op,do) }}{% if step %} ; INC LR10 1{% endif %} ;;
{% endmacro %}

{# Walk one site at a time. Adding the channel stride advances both
   the packed row and its lane, with a carry at eight packed scanlines. #}
    ADD LR11 LR0 {{ iw }} ;;
    {% for i in range(3) %}ADD LR11 LR11 LR11 ;;{% endfor %}
    INC LR6 9 ;;
    INC LR13 9 ;;
input_site:
    SET LR3 CR0 ; SET LR8 CR0 ;;
    SET LR9 LR4 ; ADD LR7 LR10 LR5 ;;
input_channel:
    LD.MULT R0 LR9 {{ cr.in0 }} ;;
    MULT.EE LR7 CR1 0 LR0 {{ scalar }} {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
    INC LR8 1 ;;
    BGE.S LR8 {{ cr.dot_bounds }}.L input_store ;;
    ADDBI LRD2 1 ; ADD LR9 LR9 {{ cr.input_steps }}.H ; ADD LR7 LR7 LR12 ;;
    BLT.S LR7 LR11 input_channel ;;
    SUB LR7 LR7 LR11 ; INC LR9 1 ; BNE CR0 CR1 input_channel ;;
input_store:
    ACTIVATE.QUANTIZE identity {{ di }} {{ qi }} {{ cr.tmp }} LR6 ;;
    INC LR6 1 ;;
    BGE.S LR6 LR13 input_done ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ iw }} input_site ;;
    SET LR5 CR0 ; ADD LR10 LR10 {{ iw }} ;;
    BLT.S LR10 LR11 input_site ;;
    SET LR10 CR0 ; INC LR4 1 ; BNE CR0 CR1 input_site ;;
input_done:
    SET LR2 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR12 CR0 ; DEC LR13 9 ;;
    INC LR1 128 ;;
    ADD LR2 LR1 LR1 ;;
    ADD LR3 LR2 LR1 ;;
site:
    SET LR11 LR4 ;;
    INC LR11 9 ;;
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR0 ;;
    {{ ix(0) }}
    {{ ve('LR0') }} ; {{ store() }} ;;
    {{ ix(1) }}
    {{ ve('LR0','CR1','SUB.FIRST') }} ;;
    {{ ve('LR0','CR1','MAX') }} ; {{ store() }} ;;
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR1 ;;
    {{ ix(2) }}
    {{ reduce('LR1') }}
    LD.MULT R1 LR11 {{ cr.tmp }} ;;
    {{ ix(7) }}
    {{ ee('LR1') }} ; {{ store() }} ;;
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR2 ;;
    {{ helper(1,'R0') }}
    {{ ix(3) }}
    {{ ve('LR2','LR0') }} ;;
    {{ ve('LR1','LR0','SUB') }} ; {{ store(di,'relu6') }} ;;
    {{ helper(0,'R1') }}
    {{ ix(3) }}
    {{ not_clamped() }}
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR2 ;;
    {{ helper(2,'R0') }}
    {{ ix(3) }}
    {{ vv('LR2','R0') }} ; {{ store() }} ;;
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR2 ;;
    {{ ix(2) }}
    {{ reduce('LR2') }}
    LD.MULT R0 LR11 {{ cr.tmp }} ;;
    {{ ix(3) }}
    {{ ee('LR1') }} ;;
    {{ ee('LR0','SUB') }} ;;
    {{ ve('LR2','CR1','ADD') }} ; {{ store(di,'relu') }} ;;
    LD.MULT R0 LR11 {{ cr.tmp }} ;;
    {{ ix(5) }}
    {{ vv('LR0','R0') }} ; {{ store() }} ;;
    {{ tmp(3,'LR2') }}
    {{ ix(4) }}
    {{ ee('LR1') }} ;;
    {{ ve('LR2','CR1','SUB') }} ; {{ store() }} ;;
    LD.MULT R0 LR11 {{ cr.tmp }} ;;
    {{ ix(3) }}
    {{ vv('LR1','R0') }} ; {{ store() }} ;;
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR2 ;;
    {{ ix(2) }}
    {{ reduce('LR2') }}
    LD.MULT R1 LR11 {{ cr.tmp }} ;;
    {{ ix(7) }}
    {{ ee('LR1') }} ; {{ store() }} ;;
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR1 ;;

    {{ helper(1,'R0') }}
    {{ helper(3,'R1') }}
    {# For e2 significands 32, 39, 57, rounding max/7 puts the
       FP32 quotient just below the exact 3.5 boundary. #}
    {{ ix(3) }}
    {{ ve('LR1') }} ;;
    {{ ve('LR1','LR1','SUB') }} ; {{ store() }} ;;
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR2 ;;
    {{ ve('LR1') }} ;;
    {{ ve('LR2','CR1','SUB') }} ; {{ store() }} ;;
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR2 ;;
    {{ helper(0,'R1') }}
    ADD LR8 LR1 CR0 ;;
    INC LR8 4 ;;
    {% for i in range(3) %}{{ half_tie_down(i) }}{% endfor %}
    ADD LR8 LR1 CR0 ;;
    INC LR8 2 ;;
    {% for k in range(7) %}
      {{ threshold(k,false,k == 0) }}
      {{ threshold(k,true,false) }}
    {% endfor %}
    {{ tmp(4,'R0',true) }}
    {{ ix(6) }}
    {{ vv('LR3','R0') }} ; {{ store() }} ;;

    SUB LR9 LR0 CR1 ;;
    SET LR8 CR0 ;;
    ADD LR6 LR5 CR0 ;;
phase_y:
    SET LR7 CR0 ;;
phase_x:
    {{ tmp(6,'R0',true) }}
    SUB LR10 LR0 CR1 ;;
    {{ dot_term('LR10','ADD.FIRST',true) }}
    BGE.S LR10 {{ last }} integer_done ;;
integer_dot:
    {{ dot_term('LR10','ADD',true) }}
    BLT.S LR10 {{ last }} integer_dot ;;
integer_done:
    {{ ix(8) }}
    {{ store(do) }} ;;
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR2 ;;
    {{ ve('LR2','CR1','SUB',do) }} ; {{ store(do) }} ;;
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR3 ;;

    ADD LR10 LR9 CR0 ;;
    {% for i in range(2) %}ADD LR9 LR9 {{ cr.dot_bounds }}.L ;;{% endfor %}
    {{ wload('R0',true) }}
    {{ vv('LR2','R0','ADD.FIRST',do) }} ;;
    {{ vv('LR3','R0','ADD',do) }} ;;
    {{ wload('R0',true) }}
    {{ vv('LR2','R0','ADD',do) }} ;;
    {{ vv('LR3','R0','ADD',do) }} ; {{ store(do) }} ;;
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR2 ;;
    {{ ve('LR2','CR1','SUB',do) }} ; {{ store(do) }} ;;
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR3 ;;
    {{ tmp(2,'R1',true) }}
    {{ ve('LR2','LR1','ADD.FIRST',do) }} ;;
    {{ ve('LR3','LR1','ADD',do) }} ;;

    {{ tmp(5,'R0',true) }}
    ADD LR9 LR10 CR0 ;;
    SET LR10 CR0 ;;
correction_dot:
    {{ wload() }}
    {{ ve('LR0','LR10','ADD',do) }} ; LD.MULT.CYCLIC LR9 {{ cr.weights }} LR0 ; INC LR9 1 ;;
    {{ ve('LR0','LR10','ADD',do) }} ;;
    INC LR10 1 ; BLT.S LR10 {{ last }} correction_dot ;;
    INC LR9 2 ;;
    {{ wload() }}
    {{ ve('LR0','CR1','ADD',do) }} ;;
    {{ wload() }}
    {{ ve('LR0','CR1','ADD',do) }} ; ACTIVATE.QUANTIZE identity {{ do }} {{ qi }} {{ cr.stage }} LR6 ;;

    INC LR6 1 ;;
    INC LR7 1 ;;
    BLT.S LR7 LR14 phase_x ;;
    ADD LR6 LR6 {{ cr.row_gap }} ;;
    INC LR8 1 ;;
    BLT.S LR8 LR15 phase_y ;;
    INC LR4 1 ;;
    BGE.S LR4 LR13 transpose ;;
    ADD LR5 LR5 LR14 ;;
    INC LR12 1 ;;
    BLT.S LR12 {{ iw }} site ;;
    SET LR12 CR0 ;;
    SUB LR5 LR6 {{ cr.row_gap }} ;;
    BNE CR0 CR1 site ;;

{# Emit padded output rows in batch, y, channel order. #}
transpose:
    SUB LR12 LR6 {{ cr.row_gap }} ;;
    ADD LR11 LR14 {{ cr.row_gap }} ;;
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR0 CR0 ;;
scanline:
    SET LR9 CR0 ;;
channel:
    SET LR3 CR0 ; SUB LR6 LR4 CR1 ; SET LR10 LR11 ;;
    LD.MULT R0 LR6 {{ cr.stage }} ; INC LR6 1 ; DEC LR10 1 ;;
    BEQ LR10 CR0 last_x ;;
{% macro scatter() %}
    MULT.EE LR9 CR1 0 LR0 {{ width_ds }} {{ qi }} ; ACC.RESHAPE LRD2 LRD2 7
{%- endmacro %}
{% macro next_x() %}
    {{ scatter() }} ; LD.MULT R0 LR6 {{ cr.stage }} ; INC LR6 1 ; DEC LR10 1
{%- endmacro %}
    {{ next_x() }} ; BEQ LR10 CR1 advance_last_x ;;
gather:
    {{ next_x() }} ; ADDBI LRD2 1 ; BNE LR10 CR1 gather ;;
advance_last_x:
    ADDBI LRD2 1 ;;
last_x:
    {{ scatter() }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ width_ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR9 1 ; INC LR5 1 ;;
    BLT.S LR9 {{ cr.output }}.H channel ;;
    ADD LR4 LR4 LR11 ;;
    BLT.S LR4 LR12 scanline ;;
    HALT ;;
