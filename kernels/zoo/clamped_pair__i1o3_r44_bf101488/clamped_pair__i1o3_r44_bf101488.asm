{# Interpolate with channels in the lanes, then gather each channel's width
   rows from the per-batch scratch into the consumer's width-lane layout. #}
{% set n = in0_d3 if axis == -1 else in0_d2 %}
{% set si = 1 if axis == -1 else in0_d3 %}
{% set so = 1 if axis == -1 else out0_d3 %}
{% set ri = in0_d3 if axis == -1 else 1 %}
{% set ro = out0_d3 if axis == -1 else 1 %}
{% set ds = cr.active ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set activation = act_out0 | default('identity') %}

{# Expand each rational weight into base-four digits, represented as
   sums of two powers of two in the input format. #}
{% macro digit(tag) %}
    LD.MULT R0 LR12 {{ cr.work }} ; ADD LR14 LR14 LR14 ;;
    INC LR12 1 ; LD.MULT R1 LR12 {{ cr.work }} ;;
    BLT.S LR14 {{ cr.den }} low_{{ tag }} ;;
    SUB LR14 LR14 {{ cr.den }} ;;
    ADD LR14 LR14 LR14 ;;
    BLT.S LR14 {{ cr.den }} two_{{ tag }} ;;
    SUB LR14 LR14 {{ cr.den }} ;;
    MULT.VE LR1 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; BEQ CR0 CR0 save_{{ tag }} ;;
two_{{ tag }}:
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; BEQ CR0 CR0 save_{{ tag }} ;;
low_{{ tag }}:
    ADD LR14 LR14 LR14 ;;
    BLT.S LR14 {{ cr.den }} zero_{{ tag }} ;;
    SUB LR14 LR14 {{ cr.den }} ;;
    MULT.VE LR1 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; BEQ CR0 CR0 save_{{ tag }} ;;
zero_{{ tag }}:
    MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
save_{{ tag }}:
    ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.work }} LR13 ;;
    INC LR13 1 ; INC LR12 1 ;;
{% endmacro %}

{% macro digits(prefix) %}
    SET LR12 CR0 ;;
    INC LR12 17 ;;
{% for k in range(8) %}
{{ digit(prefix ~ k) }}
{% endfor %}
{% endmacro %}

{% macro power() %}
    INC LR13 1 ; MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ qi }} {{ cr.work }} LR13 ;;
{% endmacro %}

{% macro dot_digit(k) %}
{% if k < 15 %}
    INC LR13 1 ; LD.MULT R0 LR13 {{ cr.work }} ; MULT.RC.VE {{ 'LR0' if k < 8 else 'LR1' }} LR0 0 LR0 {{ ds }} {{ qi }} ; {{ 'ACC.ADD.FIRST' if k == 0 else 'ACC.ADD' }} ;;
{% else %}
    MULT.RC.VE LR1 LR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.tmp }} LR11 ;;
{% endif %}
{% endmacro %}

{% macro advance_inner(label) %}
    INC LR9 {{ ri }} ; INC LR11 {{ ro }} ; INC LR12 1 ;;
    BLT.S LR12 {{ cr.inner }} {{ label }} ;;
{% endmacro %}

    INC LR1 128 ; INC LR13 16 ; MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ qi }} {{ cr.work }} LR13 ;;
    LD.MULT R0 LR13 {{ cr.work }} ;;
{% for k in range(16) %}
{{ power() }}
{% endfor %}

batch:
    SET LR4 LR2 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR7 CR0 ; SET LR8 CR0 ;;
{% if n > out %}
    INC LR6 {{ n - out }} ;;
{% elif n < out %}
    DEC LR6 {{ out - n }} ;;
{% endif %}
normalize:
    BLT.S LR6 {{ cr.den }} coordinate ;;
    SUB LR6 LR6 {{ cr.den }} ; INC LR5 1 ; INC LR4 {{ si }} ; BEQ CR0 CR0 normalize ;;
coordinate:
    SET LR9 LR4 ; SET LR11 LR8 ; SET LR12 CR0 ;;
    BGE.S LR5 {{ cr.last }} copy ;;
    BLT.S LR6 CR1 copy ;;

    SET LR13 CR0 ; SET LR14 {{ cr.den }} ;;
    SUB LR14 LR14 LR6 ;;
{{ digits('a') }}
    SET LR14 LR6 ;;
{{ digits('b') }}
    SET LR10 LR9 ; SET LR12 CR0 ;;
    INC LR10 {{ si }} ;;
weighted:
    LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR0 ;;
    LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR1 ; SET LR13 CR0 ;;
    LD.MULT R0 LR13 {{ cr.work }} ; INC LR10 {{ ri }} ;;
{% for k in range(16) %}
{{ dot_digit(k) }}
{% endfor %}
{{ advance_inner('weighted') }}
    BEQ CR0 CR0 next ;;
copy:
    LD.MULT R0 LR9 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.tmp }} LR11 ;;
{{ advance_inner('copy') }}
next:
    ADD LR6 LR6 {{ cr.step }} ; INC LR7 2 ; INC LR8 {{ so }} ;;
    BLT.S LR7 {{ cr.den }} normalize ;;

    SET LR6 CR0 ; SET LR7 CR0 ;;
    INC LR7 {{ out0_d1 }} ;;
channel:
    SET LR8 CR0 ; SET LR9 CR0 ;;
    INC LR9 {{ out0_d2 }} ;;
transpose_row:
{% if out0_d3 > 128 %}
    SET LR5 CR0 ;;
    INC LR5 {{ (out0_d3 - 1) // 128 }} ;;
{% endif %}
{# Leave the last element of each chunk to an epilogue, avoiding a load
   past the scratch buffer on the last row. #}
{% macro tile(tag, width, store_ds) %}
{{ tag }}_chunk:
    SET LR10 CR0 ; SET LR11 CR0 ; SET LR4 CR0 ; LD.MULT R0 LR8 {{ cr.tmp }} ;;
{% if width > 1 %}
    INC LR4 {{ width - 1 }} ;;
{{ tag }}_lane:
    INC LR8 1 ; LD.MULT R0 LR8 {{ cr.tmp }} ; MULT.EE LR6 CR1 0 LR0 {{ cr.full }}.L {{ qo }} ; ACC.RESHAPE LRD12 LRD10 7 ;;
    ADDBI LRD10 1 ; DEC LR4 1 ;;
    BLT.S CR0 LR4 {{ tag }}_lane ;;
{% endif %}
    MULT.EE LR6 CR1 0 LR0 {{ cr.full }}.L {{ qo }} ; ACC.RESHAPE LRD12 LRD10 7 ; INC LR8 1 ;;
    ACTIVATE.QUANTIZE {{ activation }} {{ store_ds }}.L {{ qo }} {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
{% endmacro %}
    SET LR12 CR0 ; SET LR13 CR0 ;;
{% if out0_d3 > 128 %}
{{ tile('full', 128, cr.full) }}
    DEC LR5 1 ;;
    BLT.S CR0 LR5 full_chunk ;;
{% endif %}
{{ tile('tail', (out0_d3 - 1) % 128 + 1, cr.tail) }}
    DEC LR9 1 ;;
    BLT.S CR0 LR9 transpose_row ;;
    INC LR6 1 ;;
    BLT.S LR6 LR7 channel ;;
    INC LR15 1 ; SET LR14 CR0 ;;
    INC LR14 {{ in0_d0 }} ;;
    BGE.S LR15 LR14 exit ;;
    ADD LR2 LR2 {{ cr.in_batch }} ; BEQ CR0 CR0 batch ;;
exit:
    HALT ;;
