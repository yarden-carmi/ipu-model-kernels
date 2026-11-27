{# row_norm (layernorm). in0: tokens (d1) on the 128 lanes, channels along rows: row (d0,c,ch) =
   (d0*channels + c)*nch + ch, lane = token. out0 written the same way (own layout, see summary).
   Per group (d0, ch) = one lane-row of tokens; sweeps of the `channels` rows:
   A sum (1 w/row) -> mean via 2-piece crow, stored as round(mean)+residual -> centered e = x-mh-ml
   (3 w/row, stored) -> sum e^2 (1 w/row) -> r = rsqrt(var+eps) -> z = e*r (1 w/row) -> affine
   y = z*gamma[c] + beta[c]*ind (2 w/row). Each MULT word loads the next row one ahead.
   tmp rows: e/z 0..channels-1 (z shifted +1), sx=channels, mh=+1, ml=+2, sxe=+3, r=+4. #}
{% set C = channels %}
{% set cend = channels - 1 %}
{% set nch = (in0_d1 + 127) // 128 %}
{% set K = (channels + 127) // 128 %}
{% set qg = cr.qf_gamma ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set dsf = cr.dsf ~ '.L' %}

{# Reconstruct the strided logical view into token-lane rows. #}
{% macro setval(reg, value) %}
 SET {{ reg }} CR0 ;;
 {% if value // 128 > 4 %}
 {% if value // 128 >= 16 %} INC {{ reg }} 128 ;; {% endif %}
 {% for bit in range(3, -1, -1) %}
 ADD {{ reg }} {{ reg }} {{ reg }} ;;
 {% if ((value // 128) // (2 ** bit)) % 2 %} INC {{ reg }} 128 ;; {% endif %}
 {% endfor %}
 {% else %}
 {% for _ in range(value // 128) %} INC {{ reg }} 128 ;; {% endfor %}
 {% endif %}
 {% if value % 128 %} INC {{ reg }} {{ value % 128 }} ;; {% endif %}
{% endmacro %}
{% macro addval(reg, value) %}
 {% for _ in range(value // 128) %} INC {{ reg }} 128 ;; {% endfor %}
 {% if value % 128 %} INC {{ reg }} {{ value % 128 }} ;; {% endif %}
{% endmacro %}
{% macro gather(a, chunk) %}
 {% set start = a + 4 * 128 * chunk %}
 {% set b = (start // channels) % in0_d1 %}
 {% set c = start % channels %}
 {% set batch = start // (channels * in0_d1) %}
 {% set ident = a ~ '_' ~ chunk %}
 {{ setval('LR6', (batch * channels + c) * nch) }}
 {{ setval('LR7', c) }}
 {{ setval('LR8', b) }}
 {{ setval('LR9', (a * channels) * nch + chunk) }}
 SET LR13 CR0 ;;
gather_channel_{{ ident }}:
 SET LR2 LR6 ; SET LR3 LR7 ; SET LR4 LR8 ;;
 SET LR5 CR0 ; MULT.VE LR0 CR0 0 LR0 {{ dsf }} {{ qi }} ; ACC.ADD.FIRST ;;
gather_lane_{{ ident }}:
 SET LR1 LR4 ; SET LR15 LR5 ;;
 INC LR15 {{ nch }} ;;
 {% if nch > 1 %}
 BLT.S LR1 LR14 gather_first_{{ ident }} ;;
 DEC LR1 128 ; INC LR2 1 ;;
gather_first_{{ ident }}:
 {% endif %}
 LD.MULT R0 LR2 {{ cr.in0 }} ;;
 {% if nch > 1 %}
 BLT.S LR4 LR14 gather_restore_{{ ident }} ;;
 DEC LR2 1 ;;
gather_restore_{{ ident }}:
 {% endif %}
 LD.MULT.CYCLIC LR15 {{ cr.ind }} LR0 ;;
 MULT.RC.VE LR0 LR1 0 LR0 {{ dsf }} {{ qi }} ; ACC.ADD ; INC LR2 {{ 4 * nch }} ; INC LR3 4 ; INC LR5 1 ;;
 BLT.S LR3 LR12 gather_no_carry_{{ ident }} ;;
 SUB LR3 LR3 LR12 ; SUB LR2 LR2 LR10 ; INC LR4 1 ;;
 BLT.S LR4 LR11 gather_no_carry_{{ ident }} ;;
 SUB LR4 LR4 LR11 ; ADD LR2 LR2 LR10 ;;
gather_no_carry_{{ ident }}:
 BLT.S LR5 LR14 gather_lane_{{ ident }} ;;
 ACTIVATE.QUANTIZE identity {{ dsf }} {{ qi }} {{ cr.staged }} LR9 ;;
 LD.MULT R0 LR9 {{ cr.staged }} ; ADD LR15 LR9 {{ cr.rows0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ dsf }} {{ qi }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ dsf }} {{ qi }} {{ cr.staged }} LR15 ;;
 INC LR9 {{ nch }} ; INC LR13 1 ;;
 {% set step = 4 * in0_d1 %}
 {{ addval('LR6', (step % channels) * nch) }}
 {{ addval('LR7', step % channels) }}
 {{ addval('LR8', step // channels) }}
 BLT.S LR7 LR12 gather_base_no_carry_{{ ident }} ;;
 SUB LR7 LR7 LR12 ; SUB LR6 LR6 LR10 ; INC LR8 1 ;;
gather_base_no_carry_{{ ident }}:
 BLT.S LR8 LR11 gather_base_ready_{{ ident }} ;;
 SUB LR8 LR8 LR11 ; ADD LR6 LR6 LR10 ;;
gather_base_ready_{{ ident }}:
 BLT.S LR13 LR12 gather_channel_{{ ident }} ;;
{% endmacro %}

 SET LR0 CR0 ;;
 {{ setval('LR10', channels * nch) }}
 {{ setval('LR11', in0_d1) }}
 {{ setval('LR12', channels) }}
 {{ setval('LR14', [in0_d1, 128] | min) }}
 {% for a in range(in0_d0) %}
 {% for chunk in range(nch) %}
 {{ gather(a, chunk) }}
 {% endfor %}
 {% endfor %}

{# pass A word: sum row into R_ACC, load next one ahead #}
{% macro a_word() %}
 LD.MULT.CYCLIC LR14 {{ cr.staged }} LR0 ; MULT.RC.VE LR0 CR1 0 LR0 {{ dsf }} {{ qi }} ; ACC.ADD ;;
 INC LR14 {{ nch }} ;;
 LD.MULT.CYCLIC LR4 {{ cr.staged }} LR0 ; MULT.RC.VE LR0 CR1 0 LR0 {{ dsf }} {{ qi }} ; ACC.ADD ;;
 INC LR4 {{ nch }} ; INC LR6 1 ;;
 BLT.S LR6 LR13 a_loop ;;
{% endmacro %}
{# pass e: R_ACC = x - mh - ml, store e to tmp[pe] #}
{% macro e_body(last) %}
 MULT.RC.VE LR0 CR1 0 LR0 {{ dsf }} {{ qi }} ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR14 {{ cr.staged }} LR0 ; INC LR5 1 ; INC LR6 1 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ dsf }} {{ qi }} ; ACC.ADD ; INC LR14 {{ nch }} ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ dsf }} {{ qg }} ; ACC.SUB ;;
 MULT.RC.VE LR2 CR1 0 LR0 {{ dsf }} {{ qg }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ dsf }} {{ qg }} {{ cr.tmp }} LR5 ;;
 LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ dsf }} {{ qg }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ dsf }} {{ qg }} {{ cr.tmp }} LR15 ;;
 INC LR15 1 ;;
 {% if not last %} LD.MULT.CYCLIC LR4 {{ cr.staged }} LR0 ;; {% endif %}
  {% if not last %} INC LR4 {{ nch }} ; BLT.S LR6 LR13 e_loop ;; {% endif %}
{% endmacro %}
{# pass var: R_ACC = sum e^2, stored to tmp[sxe] each trip #}
{% macro v_word() %}
 LD.MULT R0 LR11 {{ cr.tmp }} ;;
 LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ; MULT.RC.VS LR0 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD ;;
 LD.MULT.CYCLIC LR14 {{ cr.tmp }} LR3 ;;
 MULT.RC.VV LR3 R0 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD ;;
 MULT.RC.VV LR3 R0 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD ;;
 MULT.RC.VS LR3 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD ;;
 INC LR5 1 ; INC LR6 1 ; INC LR11 1 ;;
 INC LR14 1 ;;
 BLT.S LR6 LR13 v_loop ;;
{% endmacro %}
{# pass D: z = e*r stored to tmp[pe]+1 (in place, shifted one row) #}
{% macro d_word() %}
 MULT.RC.VV LR0 R0 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ; MULT.RC.VV LR0 R1 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD ;;
 LD.MULT.CYCLIC LR14 {{ cr.tmp }} LR3 ;;
 MULT.RC.VV LR3 R0 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD ;;
 MULT.RC.VV LR3 R1 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ dsf }} {{ qg }} {{ cr.tmp }} LR6 ;;
 LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR2 ;;
 MULT.RC.VE LR2 CR1 0 LR0 {{ dsf }} {{ qg }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ dsf }} {{ qg }} {{ cr.tmp }} LR14 ;;
 INC LR5 1 ; INC LR6 1 ; INC LR14 1 ;;
 BLT.S LR6 LR13 d_loop ;;
{% endmacro %}
{# pass E affine word #}
{% macro e2_word(label) %}
 LD.MULT.CYCLIC LR14 {{ cr.tmp }} LR2 ; MULT.RC.VE LR0 LR10 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD ;;
 MULT.RC.VE LR2 LR10 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD ; LD.MULT.CYCLIC LR15 {{ cr.crow }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ dsf }} {{ qg }} ; ACC.SUB ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ dsf }} {{ qo }} {{ cr.out0 }} LR4 ;;
 INC LR4 {{ nch }} ; INC LR10 1 ; INC LR14 1 ; BLT.S LR6 LR13 {{ label }} ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 INC LR1 128 ;;
 ADD LR2 LR1 LR1 ;;
 ADD LR3 LR2 LR1 ;;
 SET LR7 CR0 ; SET LR8 CR0 ; SET LR12 CR0 ;;
{% for _ in range(channels // 128) %} INC LR12 128 ;;{% endfor %}{% if channels % 128 %} INC LR12 {{ channels % 128 }} ;;{% endif %}SET LR15 LR12 ;;
 INC LR15 3 ;;
group_loop:
 SET LR8 CR0 ;;
ch_loop:
 SET LR4 LR7 ; SET LR15 LR12 ;;
 INC LR15 3 ;;
 ADD LR4 LR4 LR8 ; SET LR5 CR0 ;;
 MULT.VE LR0 CR0 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD.FIRST ; SET LR6 CR0 ;;
 LD.MULT.CYCLIC LR4 {{ cr.staged }} LR0 ; SET LR13 {{ cr.channels }} ;;
 INC LR4 {{ nch }} ;;
 ADD LR14 LR7 {{ cr.rows0 }} ;;
 ADD LR14 LR14 LR8 ;;
 SET LR15 LR12 ;;
 INC LR15 5 ;;
 DEC LR13 1 ;;
a_loop:
 {{ a_word() }}
 LD.MULT.CYCLIC LR14 {{ cr.staged }} LR0 ; MULT.RC.VE LR0 CR1 0 LR0 {{ dsf }} {{ qi }} ; ACC.ADD ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ dsf }} {{ qi }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ dsf }} {{ qg }} {{ cr.tmp }} LR12 ; LD.MULT R0 LR0 {{ cr.crow }} ;;
 LD.MULT.CYCLIC LR12 {{ cr.tmp }} LR0 ; SET LR13 LR12 ; SET LR6 CR1 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ dsf }} {{ qg }} ; ACC.SUB ; SET LR11 LR12 ;;
 ADD LR11 LR11 LR12 ;;
 INC LR11 6 ;;
 ACTIVATE.QUANTIZE identity {{ dsf }} {{ qg }} {{ cr.tmp }} LR11 ;;
 LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR3 ;;
 LD.MULT R1 LR6 {{ cr.crow }} ; MULT.RC.VV LR0 R0 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD.FIRST ; INC LR13 1 ;;
 MULT.RC.VV LR0 R1 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD ;;
 MULT.RC.VV LR3 R0 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD ;;
 MULT.RC.VV LR3 R1 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity {{ dsf }} {{ qg }} {{ cr.tmp }} LR13 ; SET LR14 LR12 ;;
 LD.MULT.CYCLIC LR13 {{ cr.tmp }} LR1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ dsf }} {{ qg }} ; ACC.SUB ; INC LR14 2 ;;
 ACTIVATE.QUANTIZE identity {{ dsf }} {{ qg }} {{ cr.tmp }} LR14 ; SET LR13 {{ cr.channels }} ; SET LR6 CR0 ;;
 LD.MULT.CYCLIC LR14 {{ cr.tmp }} LR2 ;;
 SET LR4 LR7 ; DEC LR5 1 ;;
 ADD LR4 LR4 LR8 ; SET LR6 CR0 ;;
 ADD LR14 LR7 {{ cr.rows0 }} ;;
 ADD LR14 LR14 LR8 ;;
 DEC LR13 1 ; LD.MULT.CYCLIC LR4 {{ cr.staged }} LR0 ;;
 INC LR4 {{ nch }} ;;
e_loop:
 {{ e_body(false) }}
 {{ e_body(true) }}
 SET LR15 LR12 ;;
 INC LR15 3 ;;
 MULT.VE LR0 CR0 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD.FIRST ; SET LR5 CR0 ; SET LR6 CR0 ; SET LR13 LR12 ;;
 SET LR11 CR0 ; SET LR14 LR12 ;;
 INC LR14 5 ;;
 LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ;;
 INC LR5 1 ;;
v_loop:
 {{ v_word() }}
 ACTIVATE.QUANTIZE identity {{ dsf }} {{ qg }} {{ cr.tmp }} LR15 ;;
 LD.MULT.CYCLIC LR15 {{ cr.tmp }} LR0 ; SET LR14 LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ dsf }} {{ qg }} ; ACC.SUB ; SET LR11 LR12 ;;
 ADD LR11 LR11 LR12 ;;
 INC LR11 6 ;;
 ACTIVATE.QUANTIZE identity {{ dsf }} {{ qg }} {{ cr.tmp }} LR11 ;;
 LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR3 ;;
 LD.MULT R0 LR0 {{ cr.crow }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD.FIRST ; INC LR14 2 ;;
 MULT.RC.VV LR0 R1 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD ;;
 MULT.RC.VV LR3 R0 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD ;;
 MULT.RC.VV LR3 R1 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD ; LD.MULT.CYCLIC LR14 {{ cr.crow }} LR0 ; INC LR15 1 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD ; DEC LR15 1 ;;
 ACTIVATE.QUANTIZE identity {{ dsf }} {{ qg }} {{ cr.tmp }} LR15 ;;
 LD.MULT.CYCLIC LR15 {{ cr.tmp }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ dsf }} {{ qg }} ; ACC.SUB ;;
 ACTIVATE.QUANTIZE identity {{ dsf }} {{ qg }} {{ cr.tmp }} LR11 ;;
 LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR2 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD.FIRST ; LD.MULT R1 LR15 {{ cr.tmp }} ;;
 MULT.RC.VE LR2 CR1 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD ; SET LR14 LR11 ;;
 INC LR15 1 ;;
 ACTIVATE.QUANTIZE rsqrt {{ dsf }} {{ qg }} {{ cr.tmp }} LR15 ;;
 LD.MULT R0 LR15 {{ cr.tmp }} ;;
 LD.MULT.CYCLIC LR15 {{ cr.tmp }} LR0 ;;
 DEC LR15 1 ;;
 MULT.RC.VS LR0 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ dsf }} {{ qg }} {{ cr.tmp }} LR15 ;;
 LD.MULT.CYCLIC LR15 {{ cr.tmp }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ dsf }} {{ qg }} ; ACC.SUB ;;
 SET LR11 LR12 ;;
 ADD LR11 LR11 LR12 ;;
 INC LR11 5 ;;
 ACTIVATE.QUANTIZE identity {{ dsf }} {{ qg }} {{ cr.tmp }} LR11 ;;
 LD.MULT.CYCLIC LR8 {{ cr.ind }} LR3 ;;
 MULT.RC.VE LR3 CR1 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD.FIRST ;;
 MULT.RC.VV LR0 R1 0 LR0 {{ dsf }} {{ qg }} ; ACC.SUB ; LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR2 ;;
 MULT.RC.VV LR2 R1 0 LR0 {{ dsf }} {{ qg }} ; ACC.SUB ; LD.MULT R1 LR14 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R1 0 LR0 {{ dsf }} {{ qg }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ dsf }} {{ qg }} {{ cr.tmp }} LR15 ;;
 LD.MULT.CYCLIC LR15 {{ cr.tmp }} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ dsf }} {{ qg }} {{ cr.tmp }} LR15 ;;
 LD.MULT.CYCLIC LR15 {{ cr.tmp }} LR0 ; SET LR11 CR0 ;;
 INC LR11 3 ;;
 LD.MULT R1 LR11 {{ cr.crow }} ;;
 MULT.RC.VV LR0 R1 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ dsf }} {{ qg }} {{ cr.tmp }} LR15 ;;
 LD.MULT R1 LR15 {{ cr.tmp }} ; SET LR5 CR0 ; SET LR6 CR1 ;;
 SET LR14 LR12 ;;
 INC LR14 5 ;;
 LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ; SET LR13 LR12 ;;
 INC LR5 1 ;;
 INC LR13 1 ;;
d_loop:
 {{ d_word() }}
 LD.MULT R0 LR0 {{ cr.beta }} ; SET LR10 LR1 ; SET LR4 LR7 ;;
 LD.MULT R1 LR0 {{ cr.gamma }} ; SET LR13 LR1 ; ADD LR4 LR4 LR8 ;;
 LD.MULT.CYCLIC LR8 {{ cr.ind }} LR3 ; SET LR5 CR1 ; SET LR6 CR0 ; SET LR11 CR0 ;;
 SET LR14 LR12 ; SET LR15 CR0 ;;
 INC LR14 5 ; INC LR15 4 ;;
{% for p in range(K) %}
{% set T = channels - 128 * p %}{% if T > 128 %}{% set T = 128 %}{% endif %}
{% if p > 0 %}
 SET LR13 LR0 ;;
 INC LR13 {{ p }} ;;
 LD.MULT R0 LR13 {{ cr.beta }} ; SET LR10 LR1 ; SET LR11 CR0 ;;
 LD.MULT R1 LR13 {{ cr.gamma }} ; SET LR6 CR0 ;;
 {% if T == 128 %}SET LR13 LR1{% else %}SET LR13 CR0{% endif %} ;;
{% if T != 128 %} INC LR13 {{ T }} ;;{% endif %}
{% endif %}
E{{ p }}_w1:
 LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ; MULT.RC.VE LR3 LR11 0 LR0 {{ dsf }} {{ qg }} ; ACC.ADD.FIRST ;;
 INC LR5 1 ; INC LR11 1 ; INC LR6 1 ;;
 {{ e2_word('E' ~ p ~ '_w1') }}
{% endfor %}
 INC LR8 1 ;;
 {{ setval('LR14', nch) }}
 BLT.S LR8 LR14 ch_loop ;;
{% for _ in range(nch) %}ADD LR7 LR7 LR12 ;; {% endfor %}BLT.S LR7 {{ cr.rows0 }} group_loop ;;
 HALT ;;
