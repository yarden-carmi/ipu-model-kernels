{% set full = cr.full ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro imm(reg, n) %}
 SET {{reg}} CR0 ;;
 {% for bit in range(16, -1, -1) if n >= 2**bit %}
 {% if n >= 2**(bit+1) %} ADD {{reg}} {{reg}} {{reg}} ;; {% endif %}
 {% if (n // 2**bit) % 2 %} INC {{reg}} 1 ;; {% endif %}
 {% endfor %}
{% endmacro %}
{% macro clear() %}
 MULT.RC.VE LR12 CR0 0 LR12 {{full}} {{cr.qf_aux}}.L ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro store(act, ds, qf, base, row) %}
 ACTIVATE.QUANTIZE {{act}} {{ds}} {{qf}} {{base}} {{row}} ;;
{% endmacro %}

{% if packed %}
{# Tile heads carry the previous spatial row's final sample; the first
   tile head is overwritten by the class token after accumulation. #}
{% macro large(reg, n) %}
 SET {{reg}} CR0 ;;
 {% for bit in range(30, -1, -1) if n >= 2**bit %}
 {% if n >= 2**(bit+1) %} ADD {{reg}} {{reg}} {{reg}} ;; {% endif %}
 {% if (n // 2**bit) % 2 %} INC {{reg}} 1 ;; {% endif %}
 {% endfor %}
{% endmacro %}
{% macro pair() %}
 LD.MULT.CYCLIC LR6 {{cr.in0}} LR9 ; SET LR7 LR6 ;;
 INC LR7 1 ; LD.MULT.CYCLIC LR7 {{cr.in0}} LR10 ;;
{% endmacro %}
{{large('LR0', gather_src_lo)}}
{{large('LR1', gather_src_hi)}}
{{large('LR2', 0x04030201)}}
{{large('LR3', 0x08070605)}}
SET LR8 CR0 ; SET LR9 CR0 ; SET LR12 CR0 ;;
{{imm('LR10', 128)}}
{{imm('LR15', cin)}}
packed_channel:
{{imm('LR14', kh)}}
packed_y:
SET LR4 CR0 ;;
{{imm('LR13', kw - 1)}}
packed_x:
{{imm('LR11', patches // 128)}}
{{large('LR6', (patches // wo - 1) * ystep)}}
ADD LR6 LR6 LR12 ; SET LR5 LR12 ;;
packed_tile:
{{pair()}}
SET LR7 LR4 ;;
INC LR7 {{15 * stride}} ; MULT.RC.VE LR7 CR1 0 LR9 {{cr.tail}}.L {{qi}} ; ACC.ADD.FIRST ;;
{# LR5 tracks the next spatial row, LR6 tracks the most recently loaded row. #}
SET LR6 LR5 ; SET LR7 LR4 ;;
INC LR7 {{8 * stride}} ;;
{% macro packed_row(last) %}
 LD.MULT.CYCLIC LR6 {{cr.in0}} LR9 ; SET LR5 LR6 ;;
 INC LR5 1 ; LD.MULT.CYCLIC LR5 {{cr.in0}} LR10 ;;
 MULT.RC.VE LR4 CR1 0 LR9 {{full}} {{qi}} ; ACC.RESHAPE LRD0 LRD2 0 ;;
 {% if last %}
 ADDBI LRD2 7 ; DEC LR7 {{stride}} ; MULT.RC.VE LR7 CR1 0 LR9 {{full}} {{qi}} ; ACC.RESHAPE LRD0 LRD2 1 ;;
 ADDBI LRD2 -119 ; SET LR5 LR6 ; DEC LR11 1 ; {{store('identity', full, qi, cr.gathered, 'LR8')}}
 INC LR8 1 ; INC LR5 {{ystep}} ; BLT.S CR0 LR11 packed_tile ;;
 {% else %}
 ADDBI LRD2 8 ; MULT.RC.VE LR7 CR1 0 LR9 {{full}} {{qi}} ; ACC.RESHAPE LRD0 LRD2 0 ;;
 ADDBI LRD2 8 ; INC LR6 {{ystep}} ;;
 {% endif %}
{% endmacro %}
{% for y in range(7) %} {{packed_row(false)}} {% endfor %}
{{packed_row(true)}}
INC LR4 1 ; DEC LR13 1 ; BLT.S CR0 LR13 packed_x ;;
INC LR12 {{chunks}} ; DEC LR14 1 ;;
BLT.S CR0 LR14 packed_y ;;
{{large('LR6', channel_gap)}}
ADD LR12 LR12 LR6 ; DEC LR15 1 ;;
BLT.S CR0 LR15 packed_channel ;;
{% else %}
{# Build one vector of patch samples per filter tap and token tile. #}
{{imm('LR12', 0)}}
{{imm('LR5', 128)}}
LD.MULT.CYCLIC LR12 {{cr.aux}} LR12 ;;
INC LR12 1 ;;
LD.MULT.CYCLIC LR12 {{cr.aux}} LR5 ;;
DEC LR12 1 ;;
SET LR1 CR0 ; SET LR9 CR0 ;;
{{imm('LR11', cin)}}
channel:
{{imm('LR0', kh)}}
ky:
SET LR2 CR0 ;;
kx:
SET LR8 LR1 ; SET LR7 LR1 ; SET LR3 LR2 ;;
SET LR4 LR13 ; SET LR6 {{cr.patches}} ;;
{{imm('LR10', 127-prefix)}}
{{clear()}}
gather:
 LD.MULT R0 LR7 {{cr.in0}} ;;
 MULT.RC.VE LR10 LR3 0 LR12 {{full}} {{qi}} ; ACC.ADD ;;
 DEC LR10 1 ; DEC LR6 1 ; DEC LR4 1 ;;
 BLT.S LR10 CR0 flush ;;
 BEQ LR6 CR0 flush_partial ;;
advance:
 BEQ LR4 CR0 next_y ;;
 INC LR3 {{stride}} ;;
 BLT.S LR3 LR5 gather ;;
 DEC LR3 128 ; INC LR7 1 ;;
 BEQ LR12 CR0 gather ;;
next_y:
 ADD LR8 LR8 LR14 ; SET LR3 LR2 ; SET LR4 LR13 ;;
 SET LR7 LR8 ;;
 BEQ LR12 CR0 gather ;;
flush:
 {{store('identity', full, qi, cr.gathered, 'LR9')}}
 INC LR9 1 ;;
 BEQ LR6 CR0 next_tap ;;
 INC LR10 128 ;;
 {{clear()}}
 BEQ LR12 CR0 advance ;;
flush_partial:
 {{store('identity', full, qi, cr.gathered, 'LR9')}}
 INC LR9 1 ;;
next_tap:
 INC LR2 1 ;;
 SET LR3 LR2 ;;
 DEC LR3 {{kw}} ;;
 BLT.S LR3 CR0 kx ;;
 INC LR1 {{chunks}} ; DEC LR0 1 ;;
 BLT.S CR0 LR0 ky ;;
 ADD LR1 LR1 LR15 ; DEC LR11 1 ;;
 BLT.S CR0 LR11 channel ;;
{% endif %}

{# Accumulate complete token tiles for each output channel. #}
SET LR12 CR0 ;;
{{imm('LR13', patches // 128 if packed else conv_tiles)}}
{{imm('LR14', patches // 128 if packed else tiles)}}
{{imm('LR15', cout)}}
{{imm('LR10', panels)}}
{{imm('LR9', 128)}}
SET LR0 CR0 ; SET LR1 CR0 ;;
{% if packed %}
SET LR11 CR0 ;;
{{large('LR9', (patches // wo - 1) * ystep + 1)}}
{{large('LR8', channel_gap)}}
{% endif %}
output_channel:
 SET LR2 CR0 ;;
tile:
 LD.MULT R0 LR0 {{cr.seed}} ;;
 MULT.VE LR12 CR1 0 LR12 {{full}} {{cr.qf_seed}}.L ; ACC.ADD.FIRST ; BGE.S LR2 LR13 store ;;
 SET LR3 LR1 ; SET LR4 LR2 ; SET LR6 LR10 ;;
{% if packed %}
{% macro mac(branch='') %}
 INC LR5 1 ; ADD LR4 LR4 LR13 ; LD.MULT.CYCLIC LR4 {{cr.gathered}} LR12 ;
 MULT.RC.VE LR12 LR5 0 LR12 {{full}} {{cr.qf_weights}}.L ; ACC.ADD {{branch}} ;;
{% endmacro %}
{% macro run_panel(name, count) %}
 LD.MULT R0 LR3 {{cr.weights}} ; SET LR5 CR0 ; SET LR7 CR0 ;;
 DEC LR5 1 ; LD.MULT.CYCLIC LR4 {{cr.gathered}} LR12 ; {% if count >= 16 %} INC LR7 {{count // 16 * 16 - 2}} ; {% endif %} ;;
 {% if count >= 16 %}
 {{name}}_mac:
 {% for m in range(16) %} {{mac('; BLT.S LR5 LR7 ' ~ name ~ '_mac' if m == 15 else '')}} {% endfor %}
 {% endif %}
 {% for m in range(count % 16) %} {{mac()}} {% endfor %}
{% endmacro %}
{% if taps >= 128 %}
 {% if taps % 128 %} DEC LR6 1 ;; {% endif %}
 packed_panel:
 {{run_panel('full', 128)}}
 INC LR3 1 ; DEC LR6 1 ;;
 BLT.S CR0 LR6 packed_panel ;;
{% endif %}
{% if taps % 128 %} {{run_panel('partial', taps % 128)}} {% endif %}
store:
 BNE LR2 CR0 packed_store ;;
 SET LR6 CR0 ; SET LR7 CR0 ; LD.MULT R0 LR0 {{cr.seed}} ;;
 MULT.VE LR12 CR1 0 LR12 {{full}} {{cr.qf_seed}}.L ; ACC.RESHAPE LRD6 LRD6 7 ;;
packed_store:
 {{store(act_out0|default('identity'), full, cr.qf_out0 ~ '.L', cr.out0, 'LR0')}}
 INC LR0 1 ; INC LR2 1 ;;
 BLT.S LR2 LR14 tile ;;
 {# Reduce the final patch directly, without requantizing its samples. #}
 LD.MULT R0 LR0 {{cr.seed}} ; SET LR4 LR9 ; SET LR5 CR0 ; SET LR6 CR0 ;;
 INC LR5 {{cin if cin <= 255 else 255}} ; INC LR6 {{15 * stride - 128}} ;
 MULT.VE LR12 CR1 0 LR12 {{cr.tail}}.L {{cr.qf_seed}}.L ; ACC.ADD.FIRST ;;
 {% if cin > 255 %}
 {{imm('LR5', cin)}}
 {% endif %}
 tail_channel:
 {{imm('LR3', kh - 1)}}
 tail_ky:
 LD.MULT R0 LR11 {{cr.aux}} ;;
 LD.MULT.CYCLIC LR4 {{cr.in0}} LR12 ; INC LR11 1 ;;
 MULT.RC.VV LR6 R0 0 LR12 {{full}} {{cr.qf_aux}}.L ; AGG.SUM LR12 {{full}} ; INC LR4 {{chunks}} ; DEC LR3 1 ; BLT.S CR0 LR3 tail_ky ;;
 ADD LR4 LR4 LR8 ; DEC LR5 1 ;;
 BLT.S CR0 LR5 tail_channel ;;
 {{store(act_out0|default('identity'), cr.tail ~ '.L', cr.qf_out0 ~ '.L', cr.out0, 'LR0')}}
 INC LR0 1 ; ADD LR1 LR1 LR10 ; DEC LR15 1 ;;
 BLT.S CR0 LR15 output_channel ;;
{% else %}
panel:
 LD.MULT R0 LR3 {{cr.weights}} ; SET LR5 CR0 ; SET LR7 LR9 ;;
 {% if taps % 128 %}
 SET LR8 LR6 ;;
 DEC LR8 1 ;;
 BLT.S CR0 LR8 mac ;;
 DEC LR7 {{128 - taps % 128}} ;;
 {% endif %}
mac:
 LD.MULT.CYCLIC LR4 {{cr.gathered}} LR12 ;;
 MULT.RC.VE LR12 LR5 0 LR12 {{full}} {{cr.qf_weights}}.L ; ACC.ADD ;;
 INC LR5 1 ; ADD LR4 LR4 LR13 ;;
 BLT.S LR5 LR7 mac ;;
 INC LR3 1 ; DEC LR6 1 ;;
 BLT.S CR0 LR6 panel ;;
store:
 INC LR2 1 ;;
 BEQ LR2 LR14 tail_store ;;
 {{store(act_out0|default('identity'), full, cr.qf_out0 ~ '.L', cr.out0, 'LR0')}}
 INC LR0 1 ;;
 BEQ LR12 CR0 tile ;;
tail_store:
 {{store(act_out0|default('identity'), cr.tail ~ '.L', cr.qf_out0 ~ '.L', cr.out0, 'LR0')}}
 INC LR0 1 ; ADD LR1 LR1 LR10 ; DEC LR15 1 ;;
 BLT.S CR0 LR15 output_channel ;;
{% endif %}
HALT ;;
