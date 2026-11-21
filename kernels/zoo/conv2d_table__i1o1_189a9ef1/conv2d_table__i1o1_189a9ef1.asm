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
{# one phase: the nvec weight vectors and the bias vector of one frame, one word each #}
{% macro phase(first, last) %}
{% for j in range(nvec + 1) %}
{% set t = j // cin %}
{% set c = j % cin %}
{% set bias = (j == nvec) %}
 MULT.RC.VE {{ 'LR0' if j == 0 else 'LR3' }} {{ 'CR1' if bias else 'LR' ~ c }} 0 LR0 {{ cr.dsc }}.L {{ cr.qf_weights }}.L ; {{ 'ACC.ADD.FIRST' if (first and j == 0) else 'ACC.ADD' }}
{%- if j == 0 %} ; SET LR3 CR0{% else %} ; INC LR3 {{ cout }}{% endif %}
{%- if not bias and c == 0 and t < taps - 1 %} ; INC LR4 {{ 1 if (t + 1) % kw != 0 else wp - kw + 1 }}{% endif %}
{%- if not bias and c == cin - 1 and t < taps - 1 %} ; LD.MULT R0 LR4 {{ cr.pad }}{% endif %}
{%- if j == nvec - 1 and not last %} ; LD.MULT R0 LR4 {{ cr.pad }} ; SET LR4 LR12{% endif %}
{%- if j in (4, 10, 16, 24) %} ; INC.MODP2 LR13 LR1 3 ; INC.MODP2 LR14 LR9 9 ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR14{% endif %}
{%- if last and j == 1 %} ; INC LR6 1{% endif %}
{%- if last and j == 2 %} ; INC LR5 {{ stride }}{% endif %}
{%- if last and bias %} ; ACTIVATE.QUANTIZE generic {{ cr.dsc }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ; SET LR4 LR5 ; BLT.S LR6 LR10 pix{% endif %} ;;
{% endfor %}
{% endmacro %}
 SET LR0 CR0 ; SET LR1 CR1 ; SET LR2 CR1 ;;
 INC LR2 1 ;;
 SET LR13 CR0 ;;
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ;;
 INC LR13 1 ;;
{% endfor %}
 SET LR13 CR0 ; SET LR14 CR0 ;;
{% for i in range(4) %}
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR14 ;;
 INC LR13 1 ; INC LR14 128 ;;
{% endfor %}
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
 SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
 SET LR6 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
 SET LR9 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
 DEC LR8 1 ; INC LR9 128 ; SET LR13 CR0 ;;
 INC LR13 2 ; SET LR14 LR9 ;;
 INC LR14 128 ;;
{{ step('LR10', wo) }}
{{ step('LR11', ho) }}
oy:
 SET LR6 CR0 ;;
pix:
 LD.MULT R0 LR4 {{ cr.pad }} ; SET LR12 LR5 ; INC LR8 1 ;;
{{ phase(True, False) }}
{{ phase(False, True) }}
 INC LR7 1 ;;
{{ step('LR5', stride * wp - wo * stride) }}
 SET LR4 LR5 ; BLT.S LR7 LR11 oy ;;
 HALT ;;
