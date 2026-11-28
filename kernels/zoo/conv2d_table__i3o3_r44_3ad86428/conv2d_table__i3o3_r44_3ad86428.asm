{% set ow = out0_d3 %}
{% set pack = 128 // ow - (1 if ow == 32 else 0) %}
{% set blocks = (out0_d2 + pack - 1) // pack %}
{% set tail = out0_d2 % pack %}
{% set ix = (w + 127) // 128 %}
{% set dw = groups > 1 %}
{% set reshape = ow < 32 or (ow < 128 and stride == 1) %}
{% set fast_pack = ow == 32 and stride == 2 %}
{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% macro bump(r,n) %}
{% if n|abs % 255 %}{{'INC' if n > 0 else 'DEC'}} {{r}} {{n|abs % 255}} ;;{% endif %}
{% endmacro %}
{% macro setnum(r,n) %}
{% if n >= 256 %}
{{setnum(r,n // 256)}}
{% for j in range(8) %}ADD {{r}} {{r}} {{r}} ;;{% endfor %}
{% else %}SET {{r}} CR0 ;;{% endif %}
{{bump(r,n % 256)}}
{% if n % 256 == 255 %}INC {{r}} 255 ;;{% endif %}
{% endmacro %}
{% macro gather() %}
{% if reshape %}
  SET LR14 LR11 ;;
  {% for e in range(ow // 8) %}
  MULT.RC.VE LR14 CR1 0 LR0 {{ds}} {{qi}} ; ACC.RESHAPE LRD4 LRD6 0 ;;
  {% if loop.last and stride == 1 %}
  BLT.S LR1 LR11 clear_right ;;
  BEQ LR0 CR0 right_done ;;
clear_right:
  MULT.RC.VE LR0 CR0 0 LR0 {{ds}} {{qi}} ; ACC.RESHAPE LRD4 LRD6 7 ;;
right_done:
  {% endif %}
  ADDBI LRD6 8 ; INC LR14 {{8*stride}} ;;
  {% endfor %}
{% elif ow == 128 and stride == 1 %}
  MULT.RC.VE LR11 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ;;
{% elif ow == 128 %}
  MULT.RC.VE LR11 CR1 0 LR0 {{ds}} {{qi}} ; ACC.STRIDE 64 on off LR0 ; SET LR14 LR11 ;;
  INC LR14 128 ;;
  MULT.RC.VE LR14 CR1 0 LR0 {{ds}} {{qi}} ; ACC.STRIDE 64 on off LR2 ;;
{% else %}
  MULT.RC.VE LR11 CR1 0 LR0 {{ds}} {{qi}} ; ACC.STRIDE {{64 if stride == 2 or ow == 64 else 32}} {{'on' if stride == 2 else 'off'}} {{'off' if stride == 2 and ow == 64 else 'on'}} LR13 ;;
{% endif %}
{% endmacro %}
{% macro pack32(s) %}
  {% if s %}INC LR12 2 ; INC LR13 1 ; {% if tail %}INC LR7 2 ;{% endif %} ;;
  {% if tail %}BGE.S LR7 {{cr.plane}} stage_store ;;{% endif %}
  {% endif %}
  BLT.S LR12 CR0 pack_skip_{{s}} ; ADD LR14 LR12 LR3 ;;
  BGE.S LR12 {{cr.plane}} stage_store ;;
  LD.MULT.CYCLIC LR14 {{cr.in0}} LR1 ;;
  MULT.RC.VE LR11 CR1 0 LR0 {{ds}} {{qi}} ; ACC.STRIDE 64 on on LR13 ;;
pack_skip_{{s}}:
{% endmacro %}

{{setnum('LR1',128)}}
{{setnum('LR2',256)}}
MULT.RC.VE LR0 CR0 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR0 ;;
LD.MULT.CYCLIC LR0 {{cr.pad}} LR0 ;;
{% if ix == 1 %}LD.MULT.CYCLIC LR0 {{cr.pad}} LR2 ;;{% endif %}
{% if ow == 128 and stride == 2 %}SET LR2 CR1 ;; INC LR2 1 ;;{% endif %}
{{setnum('LR15',cin*h*ix)}}
{% if reshape %}SET LR4 {{cr.src0}} ;; SET LR5 {{cr.src1}} ;;{% endif %}
stage_channel:
  SET LR8 CR0 ;;
stage_block:
  SET LR10 LR8 ;;
  DEC LR10 {{ix}} ;;
stage_ky:
  SET LR11 LR1 ; SET LR6 LR1 ;;
  DEC LR11 1 ; INC LR6 2 ;;
stage_kx:
  MULT.RC.VE LR0 CR0 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; SET LR12 LR10 ;;
  SET LR13 CR0 ; {% if fast_pack and tail %}SET LR7 LR8 ;{% endif %} ;;
  {% if fast_pack %}
  {% for s in range(3) %}{{pack32(s)}}{% endfor %}
  BEQ LR0 CR0 stage_store ;;
  {% else %}
  {% if reshape %}SET LR6 {{cr.dst0}} ;; SET LR7 {{cr.dst1}} ;;{% endif %}
stage_segment:
  {% if tail %}
  SUB LR14 LR12 LR10 ;; ADD LR14 LR14 LR8 ;; BGE.S LR14 {{cr.plane}} stage_store ;;
  {% endif %}
  BLT.S LR12 CR0 stage_skip ;;
  BGE.S LR12 {{cr.plane}} stage_store ;;
  ADD LR14 LR12 LR3 ;;
  LD.MULT.CYCLIC LR14 {{cr.in0}} LR1 ;;
  {% if ix == 2 %}
  {# Temporarily use LR13 for the second cyclic address; pack is one. #}
  SET LR13 LR1 ;; INC LR13 128 ;; LD.MULT.CYCLIC LR14 {{cr.in0}} LR13 ; INC LR14 1 ;;
  {% endif %}
  {{gather()}}
  {% if pack > 1 and reshape %}BEQ LR0 CR0 stage_advance ;;{% endif %}
stage_skip:
  {% if pack > 1 and not reshape %}BEQ LR0 CR0 stage_advance ;;{% endif %}
  {% if pack > 1 and reshape %}ADDBI LRD6 {{ow}} ;;{% endif %}
{% if pack > 1 %}
stage_advance:
  INC LR12 {{stride*ix}} ;;
  INC LR13 {{2 if ow == 64 else 1}} ;;
  {{setnum('LR14',pack * (2 if ow == 64 else 1))}}
  BLT.S LR13 LR14 stage_segment ;;
{% else %}
  BEQ LR0 CR0 stage_store ;;
{% endif %}
  {% endif %}
stage_store:
  ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR9 ; INC LR9 1 ; INC LR11 1 ;;
  {% if fast_pack %}BLT.S LR11 LR6 stage_kx ;;{% else %}SET LR14 LR1 ;; INC LR14 2 ;; BLT.S LR11 LR14 stage_kx ;;{% endif %}
  INC LR10 {{ix}} ;; SET LR14 LR8 ;; INC LR14 {{2*ix}} ;; BLT.S LR10 LR14 stage_ky ;;
  INC LR8 {{pack*stride*ix}} ;; BLT.S LR8 {{cr.plane}} stage_block ;;
  ADD LR3 LR3 {{cr.plane}} ;; BLT.S LR3 LR15 stage_channel ;;

SET LR2 CR0 ;; DEC LR2 1 ;;
{% for k in range(5) %}LD.LUT {{k}} {{cr.lut}} LR2 ; INC LR2 1 ;;{% endfor %}
{{setnum('LR3',cout*blocks-1)}}
{{setnum('LR4',blocks)}}
{{setnum('LR5',9*blocks-9)}}
{{setnum('LR6',1 if dw else cin)}}
SET LR7 CR0 ;; SET LR8 CR0 ;; SET LR10 CR0 ;; DEC LR7 1 ; DEC LR8 1 ;;
output_channel:
  SET LR11 CR0 ;;
output_block:
  SET LR12 LR8 ;; SET LR13 LR10 ;; SET LR14 CR0 ;;
  {% if tail and blocks > 1 %}
  SET LR15 LR11 ;; INC LR15 1 ;; BNE LR15 LR4 bias_load ;; INC LR12 2 ;;
  {% endif %}
bias_load:
  LD.MULT R0 LR12 {{cr.weights}} ; INC LR12 1 ;;
  MULT.VE LR0 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD.FIRST ; LD.MULT R1 LR12 {{cr.weights}} ; INC LR12 1 ;;
  MULT.VE LR1 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{cr.pad}} LR0 ; INC LR13 1 ;;
  SET LR12 LR8 ;; INC LR12 {{4 if tail and blocks > 1 else 2}} ;;
mac_channel:
  LD.MULT R0 LR12 {{cr.weights}} ; INC LR12 1 ;;
  LD.MULT R1 LR12 {{cr.weights}} ; INC LR12 1 ;;
  SET LR15 CR0 ; SET LR2 LR1 ;; DEC LR15 1 ; DEC LR2 1 ;;
  {% macro tap(k) %}
  MULT.RC.VE LR0 LR15 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; INC LR15 1 ;;
  MULT.RC.VE LR0 LR2 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; INC LR2 1 ; {% if k < 8 %}LD.MULT.CYCLIC LR13 {{cr.pad}} LR0 ; INC LR13 1 ;{% endif %} ;;
  {% endmacro %}
  {% for k in range(9) %}{{tap(k)}}{% endfor %}
  INC LR14 1 ;;
  {% if not dw %}
  BGE.S LR14 LR6 mac_done ;;
  ADD LR13 LR13 LR5 ;;
  LD.MULT.CYCLIC LR13 {{cr.pad}} LR0 ; INC LR13 1 ; BEQ LR0 CR0 mac_channel ;;
mac_done:
  {% endif %}
  ACTIVATE.QUANTIZE generic {{ds}} {{qo}} {{cr.out0}} LR7 ; INC LR7 1 ;;
  INC LR10 9 ;; INC LR11 1 ;; BLT.S LR11 LR4 output_block ;;
  SET LR8 LR12 ;;
  {% if not dw %}SET LR10 CR0 ;;{% endif %}
  BLT.S LR7 LR3 output_channel ;;
HALT ;;
