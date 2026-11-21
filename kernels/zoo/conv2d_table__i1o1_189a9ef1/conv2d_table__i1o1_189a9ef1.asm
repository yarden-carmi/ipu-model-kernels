{#- conv2d_table: 3x3 conv, pad 1, channels on the lanes, BN folded into the weights (hi + lo frames), SiLU/hardswish
    through the table. groups == 1: the 3->16 stem (all weight vectors resident in R_CYCLIC); otherwise a depthwise
    conv (weights streamed through two R_CYCLIC slots). Both read a zero padded scratch copy of the input. -#}
{% macro step(r,n) %}{% for k in range(0,n|abs,255) %}
 {{'INC' if n>=0 else 'DEC'}} {{r}} {{[255,(n|abs)-k]|min}} ;;
{% endfor %}{% endmacro %}
{% set wp = w + 2 * padding %}
{% set wo = (w + 2 * padding - kw) // stride + 1 %}
{% set ho = (h + 2 * padding - kh) // stride + 1 %}
{% set taps = kh * kw %}
{% set nvec = taps * cin %}
{% macro zbody() %}
 MULT.RC.VE LR0 CR0 0 LR0 {{ cr.dsi }}.L {{ cr.qf_weights }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.dsi }}.L {{ cr.qf_weights }}.L {{ cr.pad }} LR9 ; INC LR9 1 ;;
{% endmacro %}
{% macro zloop(lbl, n) %}
 SET LR13 CR0 ; SET LR14 CR0 ;;
{{ step('LR14', n) }}
{{ lbl }}:
{{ zbody() }}
 INC LR13 1 ;;
 BLT.S LR13 LR14 {{ lbl }} ;;
{% endmacro %}
{% macro cbody() %}
 MULT.VE LR0 CR1 0 LR0 {{ cr.dsi }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.dsi }}.L {{ cr.qf_weights }}.L {{ cr.pad }} LR9 ; INC LR9 1 ;;
{% endmacro %}
{# copy the input into the zero padded scratch (uses LR3, LR9 .. LR15) #}
{% macro buildpad() %}
 SET LR9 CR0 ; SET LR10 CR0 ; SET LR12 CR0 ;;
 DEC LR9 1 ; DEC LR10 1 ; SET LR15 CR0 ;;
 SET LR3 CR0 ;;
{{ step('LR15', h) }}
{{ step('LR3', w - 1) }}
{{ zloop('ztop', padding * wp + padding) }}
yloop:
 LD.MULT R0 LR10 {{ cr.in0 }} ; INC LR10 1 ; SET LR11 CR1 ;;
xloop:
 LD.MULT R0 LR10 {{ cr.in0 }} ; INC LR10 1 ; INC LR11 1 ; BLT.S LR11 LR3 xloop ;
{{ cbody() }}
{{ cbody() }}
{% for i in range(2 * padding) %}
{{ zbody() }}
{% endfor %}
 INC LR12 1 ;;
 BLT.S LR12 LR15 yloop ;;
{{ zloop('zbot', padding * wp - padding) }}
{% endmacro %}
 SET LR13 CR0 ;;
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ;;
 INC LR13 1 ;;
{% endfor %}
{# depthwise: weight rows 0 and 1 into the two R_CYCLIC slots (LR0 = 0, LR1 = 128) #}
 SET LR0 CR0 ; SET LR13 CR0 ; SET LR1 CR0 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR1 128 ; INC LR13 1 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ;;
{{ buildpad() }}
{# the convolution: LR4 pad row read, LR5 window origin, LR6 pixel, LR7 output row, LR8 output row index, LR13 next weight row #}
 SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
 SET LR7 CR0 ; SET LR8 CR0 ; SET LR10 CR0 ;;
 DEC LR8 1 ; SET LR11 CR0 ; SET LR13 CR1 ;;
{{ step('LR10', wo) }}
{{ step('LR11', ho) }}
pix:
 LD.MULT R0 LR4 {{ cr.pad }} ; SET LR4 LR5 ;;
{% for t in range(taps) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ cr.dsc }}.L {{ cr.qf_weights }}.L ; {{ 'ACC.ADD.FIRST' if t == 0 else 'ACC.ADD' }} ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1{% if t == 0 %} ; INC LR6 1{% endif %} ;;
 MULT.RC.VV LR1 R0 0 LR0 {{ cr.dsc }}.L {{ cr.qf_weights }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1{% if t == 0 %} ; INC LR5 {{ stride }}{% endif %}{% if t < taps - 1 and (t + 1) % kw == 0 %} ; INC LR4 {{ wp - kw }}{% endif %} ;;
{% if t < taps - 1 %}
 LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ;;
{% endif %}
{% endfor %}
 MULT.RC.VE LR0 CR1 0 LR0 {{ cr.dsc }}.L {{ cr.qf_weights }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; SET LR13 CR0 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ cr.dsc }}.L {{ cr.qf_weights }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ; ACTIVATE.QUANTIZE generic {{ cr.dsc }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ; INC LR8 1 ; BLT.S LR6 LR10 pix ;;
 INC LR7 1 ; SET LR6 CR0 ;;
{{ step('LR5', stride * wp - wo * stride) }}
 BLT.S LR7 LR11 pix ;;
 HALT ;;

