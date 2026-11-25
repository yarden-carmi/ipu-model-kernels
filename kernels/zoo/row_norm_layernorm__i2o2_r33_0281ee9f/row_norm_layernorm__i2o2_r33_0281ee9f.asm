{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set one = cr.ds1 ~ '.L' %}
{% set fine = cr.ds1 ~ '.H' %}
{% set lo = 'CR15.L' %}
{% set hi = cr.dsl ~ '.L' %}
{% macro at(reg,n) %}
 SET {{ reg }} CR0 ;;
 {% if n >= 256 %}
  {{ add_const(reg,n // 256) }}
  {% for _ in range(8) %}ADD {{ reg }} {{ reg }} {{ reg }} ;;{% endfor %}
 {% endif %}
 {{ add_const(reg,n % 256) }}
{% endmacro %}
{% macro add_const(reg,n) %}
 {% if n %}INC {{ reg }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro seq(a,b) %}
 SET LR{{ a }} {{ cr.seq }} ; SET LR{{ b }} {{ cr.seq_hi }} ;
{% endmacro %}
{% macro scalar(op='ADD',ds=lo,tail='') %}
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }} {{ tail }} ;;
{% endmacro %}

{% if false %}
{# Gather eight logical rows at a time. The view advances by rows elements
   between channels in the unpadded storage stream. #}
{{ at('LR10',39 + 4 * rows) }}{{ at('LR11',rows // 8) }}
{{ at('LR14',channels) }}{{ at('LR15',128) }}
SET LR12 CR0 ; SET LR13 CR0 ; SET LR7 CR0 ;;
gather_tile:
SET LR5 LR12 ; SET LR6 LR13 ; SET LR8 CR0 ;;
INC LR8 {{ channels // 16 }} ;;
gather_block:
{{ seq(2,3) }} INC LR10 1 ;;
SET LR9 CR0 ;;
INC LR9 16 ;;
gather_channel:
SET LR4 LR5 ; {{ seq(0,1) }} BLT.S LR6 LR15 gather_low ;;
INC LR4 1 ;;
gather_low:
INC.MODP2 LR7 LR6 7 ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
ADDB LRD0 LR7 ; SET LR7 CR0 ; {% if rows % channels %}INC LR6 {{ rows % channels }} ;{% endif %}
MULT.VE LR7 CR1 0 LR7 {{ lo }} {{ q }} ; ACC.RESHAPE LRD0 LRD2 0 ;;
{% if rows % channels %}
BLT.S LR6 LR14 gather_nowrap ;;
SUB LR6 LR6 LR14 ; INC LR5 2 ;;
gather_nowrap:
{% endif %}
{% if rows // channels %}INC LR5 {{ 2 * (rows // channels) }} ;{% endif %}
DEC LR9 1 ; ADDBI LRD2 8 ;;
BNE LR9 CR0 gather_channel ;;
DEC LR8 1 ; ACTIVATE.QUANTIZE identity {{ lo }} {{ fine }} {{ cr.tmp }} LR10 ;;
BNE LR8 CR0 gather_block ;;
INC LR13 8 ; DEC LR11 1 ;;
BLT.S LR13 LR14 gather_next ;;
SUB LR13 LR13 LR14 ; INC LR12 2 ;;
gather_next:
BNE LR11 CR0 gather_tile ;;

{# Undo the 8x16 interleave and write pairs in output row order. #}
{{ at('LR4',40 + 4 * rows) }}{{ at('LR11',rows // 8) }}
{{ at('LR13',rows // 2) }}{{ at('LR14',40) }}
SET LR12 CR0 ; SET LR6 {{ cr.seq }} ; SET LR7 {{ cr.seq_hi }} ;;
{% for _ in range(3) %}ADD LR6 LR6 LR6 ; ADD LR7 LR7 LR7 ;;{% endfor %}
unpack_tile:
SET LR5 CR0 ; SET LR9 LR14 ;;
unpack_row:
SET LR10 LR4 ; SET LR0 LR6 ; SET LR1 LR7 ; LD.MULT R0 LR10 {{ cr.tmp }} ;;
ADDB LRD0 LR5 ;;
{% for h in range(2) %}
 {{ seq(2,3) }} {% if h %}ADDBI LRD0 -64 ;{% endif %} ;;
 {% for j in range(8 if h == 0 else channels // 16 - 8) %}
  {% if h and loop.last %}INC LR9 1 ;{% endif %}
  {% if j %}ADDBI LRD0 -64 ; ADDBI LRD2 8 ;{% endif %}
  MULT.VE LR12 CR1 0 LR12 {{ lo }} {{ fine }} ; ACC.RESHAPE LRD0 LRD2 0 ;;
  ADDBI LRD0 64 ; ADDBI LRD2 8 ; INC LR10 1 ;
  MULT.VE LR12 CR1 0 LR12 {{ lo }} {{ fine }} ; ACC.RESHAPE LRD0 LRD2 0 ;
  {% if not (h and loop.last) %}LD.MULT R0 LR10 {{ cr.tmp }} ;{% endif %}
  {% if loop.last %}ACTIVATE.QUANTIZE identity {{ hi if h else lo }} {{ fine }} {{ cr.tmp }} LR9 ;{% endif %} ;;
 {% endfor %}
{% endfor %}
INC LR5 1 ; DEC LR9 1 ; SET LR15 CR0 ;;
ADD LR9 LR9 LR13 ; INC.MODP2 LR15 LR5 2 ;;
BNE LR15 CR0 unpack_row ;;
SET LR9 LR14 ; SET LR15 CR0 ;;
INC LR9 2 ; INC LR15 8 ;;
BLT.S LR5 LR15 unpack_row ;;
INC LR14 4 ; INC LR4 {{ channels // 16 }} ; DEC LR11 1 ;;
BNE LR11 CR0 unpack_tile ;;
{% endif %}

{# Gather each view row in batch/time order. Keep a residual so that changing
   the row scale in the transpose does not discard input precision. #}
{% macro gather(label,n,ds) %}
 SET LR2 CR0 ; SET LR3 CR0 ; SET LR9 CR0 ;;
 INC LR9 {{ n }} ;;
 {{ label }}:
 SET LR10 LR6 ; BLT.S LR7 LR13 {{ label }}_low ;;
 INC LR10 1 ;;
 {{ label }}_low:
 SET LR1 CR0 ; LD.MULT R0 LR10 {{ cr.in0 }} ; DEC LR9 1 ;;
 INC.MODP2 LR1 LR7 7 ; {% if rows % channels %}INC LR7 {{ rows % channels }} ;{% endif %} ;;
 MULT.EE LR1 CR1 0 LR0 {{ lo }} {{ q }} ; ACC.RESHAPE LRD0 LRD2 7 ;;
 {% if rows % channels %}
 BLT.S LR7 LR14 {{ label }}_nowrap ;;
 SUB LR7 LR7 LR14 ; INC LR6 2 ;;
 {{ label }}_nowrap:
 {% endif %}
 {% if rows // channels %}INC LR6 {{ 2 * (rows // channels) }} ;{% endif %}
 ADDBI LRD2 1 ; BNE LR9 CR0 {{ label }} ;;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ fine }} {{ cr.tmp }} LR8 ;;
 LD.MULT R0 LR8 {{ cr.tmp }} ;;
 INC LR8 1 ; MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ fine }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ fine }} {{ cr.tmp }} LR8 ;;
 INC LR8 1 ;;
{% endmacro %}
SET LR0 CR0 ; SET LR12 CR0 ;;
{{ at('LR8',40) }}{{ at('LR13',128) }}{{ at('LR14',channels) }}{{ at('LR15',4) }}
gather_batch:
SET LR4 CR0 ; SET LR5 LR12 ;;
{{ at('LR11',in0_d1) }}
gather_row:
SET LR6 LR4 ; SET LR7 LR5 ;;
{{ gather('gfull',128,lo) }}
{{ gather('gtail',channels - 128,hi) }}
INC LR5 4 ; DEC LR11 1 ;;
BLT.S LR5 LR14 gather_row_next ;;
SUB LR5 LR5 LR14 ; INC LR4 2 ;;
gather_row_next:
BNE LR11 CR0 gather_row ;;
INC LR12 1 ;;
BLT.S LR12 LR15 gather_batch ;;

{# Split mean, centered input and affine factors to preserve precision. #}
SET LR0 CR0 ; SET LR3 CR0 ; SET LR8 CR0 ;;
INC LR3 128 ; INC LR8 32 ;;
ADD LR4 LR3 LR3 ;;
ADD LR12 LR4 LR3 ;;
{{ at('LR14',40) }}{{ at('LR6',27) }}{{ at('LR7',9) }}
{{ at('LR13',rows) }}{{ at('LR11',8) }}{{ at('LR15',39 + 4 * rows) }}
row_loop:
SET LR1 CR0 ; LD.MULT.CYCLIC LR1 {{ cr.crow }} LR0 ; SET LR5 LR14 ;;
DEC LR13 1 ; LD.MULT R0 LR5 {{ cr.tmp }} ;;
{% set halves = [lo,hi] %}
INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.crow }} LR3 ;;
{% for ds in halves %}
 {% set h = loop.index0 %}
 {% for part in range(2) %}
  MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ fine }} ; AGG.SUM{% if not h and not part %}.FIRST{% endif %} LR0 {{ ds }} ;;
  MULT.RC.VV LR3 R0 0 LR0 {{ ds }} {{ fine }} ; AGG.SUM LR0 {{ ds }} ;
  {% if h == 0 or part == 0 %}INC LR5 1 ; LD.MULT R0 LR5 {{ cr.tmp }} ;{% endif %} ;;
 {% endfor %}
{% endfor %}
SET LR1 LR6 ; SET LR5 LR14 ; SET LR9 LR8 ; ACTIVATE.QUANTIZE identity {{ lo }} {{ q }} {{ cr.tmp }} LR1 ;;
LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ scalar('SUB',tail='; INC LR1 1 ; LD.MULT R0 LR5 ' ~ cr.tmp ~ ' ; ACTIVATE.QUANTIZE identity ' ~ lo ~ ' ' ~ q ~ ' ' ~ cr.tmp ~ ' LR1') }}
{% for ds in halves %}
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ fine }} ; ACC.ADD.FIRST ; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.tmp }} ;;
 SET LR1 LR6 ; {% if not loop.first %}DEC LR9 1 ;{% endif %} MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ fine }} ; ACC.ADD ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for n in range(2) %}
  MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;
  {% if not loop.last %}INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% else %}ACTIVATE.QUANTIZE identity {{ ds }} {{ fine }} {{ cr.tmp }} LR9{% endif %} ;;
 {% endfor %}
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ fine }} ; ACC.SUB ; INC LR9 2 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ fine }} {{ cr.tmp }} LR9
 {% if loop.first %}; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.tmp }}{% endif %} ;;
{% endfor %}
LD.MULT.CYCLIC LR8 {{ cr.tmp }} LR0 ;;
DEC LR9 2 ; MULT.RC.VS LR0 0 LR0 {{ lo }} {{ fine }} ; AGG.SUM.FIRST LR0 {{ lo }} ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR3 ;;
MULT.RC.VS LR3 0 LR0 {{ lo }} {{ fine }} ; AGG.SUM LR0 {{ lo }} ; LD.MULT R0 LR0 {{ cr.epsilon }} ;;
{{ scalar(ds=one,tail='; SET LR5 LR8 ; SET LR10 CR0 ; LD.MULT.CYCLIC LR10 ' ~ cr.gamma ~ ' LR0 ; ACTIVATE.QUANTIZE rsqrt ' ~ one ~ ' ' ~ fine ~ ' ' ~ cr.tmp ~ ' LR11') }}
LD.MULT R1 LR11 {{ cr.tmp }} ;;
{% for h in range(2) %}
 {% for i in range(2) %}
  MULT.RC.VE LR0 LR3 0 LR0 {{ lo }} {{ fine }} ; ACC.ADD{% if not i %}.FIRST{% endif %} ;
  {% if not i %}INC LR10 2 ; LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0{% else %}SET LR1 LR7 ; LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR4 ; ACTIVATE.QUANTIZE identity {{ lo }} {{ fine }} {{ cr.tmp }} LR1{% endif %} ;;
 {% endfor %}
 INC LR5 2 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ lo }} {{ fine }} ; ACC.SUB ; INC LR1 1 ; ACTIVATE.QUANTIZE identity {{ lo }} {{ fine }} {{ cr.tmp }} LR1 ; LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR12 ;;
 MULT.RC.VV LR12 R0 0 LR0 {{ lo }} {{ fine }} ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.RC.VV LR4 R0 0 LR0 {{ lo }} {{ fine }} ; ACC.ADD ; DEC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.RC.VV LR4 R0 0 LR0 {{ lo }} {{ fine }} ; ACC.ADD ; DEC LR5 1 ; SET LR10 {{ 'CR0' if not h else 'CR1' }} ; LD.MULT R0 LR10 {{ cr.beta }} ;;
 {{ scalar(tail='; INC LR10 2 ; LD.MULT R0 LR10 ' ~ cr.beta) }}
 INC LR15 1 ; MULT.VE LR0 CR1 0 LR0 {{ lo }} {{ q }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ halves[h] }} {{ fine }} {{ cr.tmp }} LR15 ;;
 LD.MULT R0 LR15 {{ cr.tmp }} ;;
 INC LR15 1 ; MULT.VE LR0 CR1 0 LR0 {{ lo }} {{ fine }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ halves[h] }} {{ fine }} {{ cr.tmp }} LR15 ;
 {% if not h %}SET LR10 CR1 ; LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0{% else %}INC LR14 4 ; BNE LR13 CR0 row_loop{% endif %} ;;
{% endfor %}

{# Stream sixteen 8-lane pieces per output row, skipping scratch padding. #}
{{ at('LR4',40 + 4 * rows) }}{{ at('LR11',rows * channels // 128) }}
{{ at('LR14',channels) }}{{ at('LR15',128) }}
SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
SET LR9 CR0 ;;
pack_row:
SET LR12 LR4 ; SET LR13 LR5 ; SET LR10 LR6 ;;
INC LR4 1 ;;
{# LR10 saves the input lane; phase is selected by the source-pointer parity. #}
pack_phase:
{{ seq(2,3) }} SET LR8 CR0 ;;
INC LR8 16 ;;
pack_piece:
{{ seq(0,1) }} LD.MULT R0 LR4 {{ cr.tmp }} ;;
ADDB LRD0 LR6 ; DEC LR8 1 ; INC LR5 8 ;
MULT.VE LR9 CR1 0 LR9 {{ lo }} {{ fine }} ; ACC.RESHAPE LRD0 LRD2 0 ;;
ADDBI LRD2 8 ; INC LR6 8 ; BNE LR5 LR14 pack_cont ;;
SET LR5 CR0 ; SET LR6 CR0 ; INC LR4 2 ; B pack_next ;;
pack_cont:
BNE LR6 LR15 pack_next ;;
SET LR6 CR0 ; INC LR4 2 ;;
pack_next:
BNE LR8 CR0 pack_piece ;;
SET LR8 CR0 ;;
INC.MODP2 LR8 LR4 1 ;;
BEQ LR8 CR0 pack_final ;;
ACTIVATE.QUANTIZE identity {{ lo }} {{ fine }} {{ cr.tmp }} LR9 ;;
SET LR4 LR12 ; SET LR5 LR13 ; SET LR6 LR10 ; B pack_phase ;;
pack_final:
LD.MULT R0 LR9 {{ cr.tmp }} ;;
MULT.VE LR9 CR1 0 LR9 {{ lo }} {{ fine }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ lo }} {{ qo }} {{ cr.out0 }} LR7 ;;
INC LR7 1 ; DEC LR11 1 ;;
BNE LR11 CR0 pack_row ;;
HALT ;;
