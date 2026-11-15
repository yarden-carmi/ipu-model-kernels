{#- conv2d (NCHW; input channels on lanes, output width on lanes), fp8_e3m4, one program for every size.
    Pass 1: copy the input into a zero-filled padded scratch `pad`, one row per (padded y, padded x, 128-channel block).
    Pass 2: per output channel co, output row oy, output column ox (ox = accumulator slot, LR3):
      AGG.SUM over the lanes (input channels) of MULT.RC.VV(weight row, pixel row) for every tap and channel block,
      then one bias step (weight row x 1.0, MULT.RC.VE). The sums land in R_ACC slot ox. After all ox, one
      ACTIVATE.QUANTIZE stores the row (co, oy) with lanes ox < wo (ds(wo); other lanes are zero).
    Weight rows (weights, folded): row co*Sall + s, s = (ky*kw+kx)*nbi + ib for taps, s = Sall-1 for bias (lane 0).
    Timing: loads land in the next word; MULT reads R_CYCLIC/R0 at word start. Two words per step:
      w1: MULT + AGG, load of the next weight row;
      w2: load of the next pixel row, weight pointer increment.
    INC immediates are 0..255: larger increments are split into INC words (inc macro).
    Register map: LR0 zero, LR2 input counter (pass 1), LR3 ox (AGG slot), LR4 pad row base, LR5 pixel pointer,
    LR6 ox offset (pass 2) / x (pass 1), LR7 oy row base / y, LR8 weight row pointer, LR9 co weight base,
    LR10 co, LR11 oy, LR12 out row.                                                              -#}
{%- macro inc(reg, n) -%}
{%- for k in range(0, n, 255) %}
    INC {{ reg }} {{ [255, n - k] | min }} ;;
{%- endfor -%}
{%- endmacro -%}
{%- set nbi = (cin + 127) // 128 -%}
{%- set T = kh * kw * nbi -%}
{%- set SA = T + 1 -%}
{%- set S = T + (1 if bias else 0) -%}
{%- set wp = w + 2 * padding -%}
{%- set wpr = wp * nbi -%}
{%- set base0 = (padding * wp + padding) * nbi -%}
{%- set offs = [] -%}
{%- for ky in range(kh) -%}{%- for kx in range(kw) -%}{%- for ib in range(nbi) -%}
{%- set _ = offs.append(ky * wpr + kx * nbi + ib) -%}
{%- endfor -%}{%- endfor -%}{%- endfor -%}
{% if cin == 3 and padding == 0 and not bias %}
{% set blocks = (kh * kw * cin + 127) // 128 %}
{% set ho = (h-kh)//stride+1 %}
{% set wo = (w-kw)//stride+1 %}
    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR7 CR0 ;;
    SET LR10 CR0 ;;
    SET LR15 CR0 ;;
    INC LR15 128 ; SET LR6 CR0 ;;
    INC LR6 3 ; SET LR8 CR0 ;;
    INC LR8 {{ kw }} ;;
pack_y:
    ADD LR4 LR7 CR0 ; SET LR11 CR0 ;;
pack_x:
    ADD LR5 LR4 CR0 ; SET LR13 CR0 ; SET LR3 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
pack_tap:
    SET LR9 CR0 ;;
pack_kx:
    LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR2 CR0 ;;
pack_chan:
    MULT.EE LR2 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR3 {{ cr.ds1 }}.L ;;
    INC LR2 1 ; INC LR3 1 ;;
    BLT.S LR3 LR15 pack_no_store ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.pad }} LR1 ;;
    INC LR1 1 ;;
    SET LR3 CR0 ; MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
pack_no_store:
    BLT.S LR2 LR6 pack_chan ;;
    INC LR5 1 ; INC LR9 1 ;;
    BLT.S LR9 LR8 pack_kx ;;
    {{ inc('LR5', w-kw) }}
    INC LR13 1 ;;
    BLT.S LR13 LR14 pack_tap ;;
    {% if (kh*kw*cin)%128 %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.pad }} LR1 ;;
    INC LR1 1 ;;
    {% endif %}
    {{ inc('LR4', stride) }}
    INC LR11 1 ;;
    BLT.S LR11 {{ cr.wo }} pack_x ;;
    {{ inc('LR7', stride*w) }}
    INC LR10 1 ;;
    BLT.S LR10 {{ cr.ho }} pack_y ;;
    SET LR9 CR0 ; SET LR10 CR0 ;;
dot_co:
    SET LR7 CR0 ; SET LR11 CR0 ;;
dot_x:
    SET LR3 CR0 ; ADD LR5 LR7 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
dot_y:
    ADD LR8 LR9 CR0 ;;
{% for b in range(blocks) %}
    LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ;;
    LD.MULT R0 LR5 {{ cr.pad }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR3 CR15.L ; INC LR5 1 ; INC LR8 1 ;;
{% endfor %}
    {{ inc('LR5', (wo-1)*blocks) }}
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.ho }} dot_y ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsout0 }}.L {{ cr.qf }}.L {{ cr.out0 }} LR12 ;;
    INC LR12 1 ;;
    {{ inc('LR7', blocks) }}
    INC LR11 1 ;;
    BLT.S LR11 {{ cr.wo }} dot_x ;;
    {{ inc('LR9', blocks) }}
    INC LR10 1 ;;
    BLT.S LR10 {{ cr.cout }} dot_co ;;
    HALT ;;
{% else %}
    SET LR0 CR0 ;;
    SET LR2 CR0 ;;
    SET LR4 CR0 ;;
{{- inc('LR4', base0) }}
    SET LR7 CR0 ;;
py_top:
    ADD LR5 LR4 CR0 ;;
    SET LR6 CR0 ;;
px_top:
{%- for ib in range(nbi) %}
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; INC LR2 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.pad }} LR5 ;;
    INC LR5 1 ;;
{%- endfor %}
    INC LR6 1 ;;
    BLT.S LR6 {{ cr.w }} px_top ;;
{{- inc('LR4', wpr) }}
    INC LR7 1 ;;
    BLT.S LR7 {{ cr.h }} py_top ;;

{% set oh = (h + 2 * padding - kh) // stride + 1 %}
{% if not bias and nbi == 1 and oh >= 2 and oh <= 16 and (oh % 2 == 0 or kw % 2 == 0) %}
    SET LR9 CR0 ;;
    SET LR10 CR0 ;;
fast_co:
    SET LR7 CR0 ; SET LR11 CR0 ;;
fast_x:
    ADD LR4 LR7 CR0 ; ADD LR8 LR9 CR0 ;;
    SET LR13 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ;;
    LD.MULT R0 LR4 {{ cr.pad }} ;;
fast_ky:
{% for kx in range(kw) %}
{% set parity = kx % 2 if oh % 2 else 0 %}
    ADD LR5 LR4 LR15 ; SUB LR3 LR0 CR1 ; LD.MULT R{{ 1 - parity }} LR5 {{ cr.pad }} ; INC LR8 1 ;;
{% for oy in range(oh) %}
{% if oy < oh - 2 %}
    MULT.RC.VV LR0 R{{ (oy + parity) % 2 }} 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR3 {{ cr.ds_tail }}.L ; LD.MULT R{{ (oy + parity) % 2 }} LR5 {{ cr.pad }} ; ADD LR5 LR5 LR15 ; INC LR3 1 ;;
{% elif oy == oh - 2 %}
    MULT.RC.VV LR0 R{{ (oy + parity) % 2 }} 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR3 {{ cr.ds_tail }}.L ; LD.MULT R{{ (oh + parity) % 2 }} LR4 {{ cr.pad }} ; INC LR4 {{ 1 if kx + 1 < kw else wpr - kw + 1 }} ; INC LR3 1 ;;
{% else %}
    MULT.RC.VV LR0 R{{ (oy + parity) % 2 }} 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR3 {{ cr.ds_tail }}.L ; LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ; INC LR3 1 ;;
{% endif %}
{% endfor %}
{% endfor %}
    INC LR13 1 ;;
    BLT.S LR13 LR14 fast_ky ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsout0 }}.L {{ cr.qf }}.L {{ cr.out0 }} LR12 ;;
    INC LR12 1 ; INC LR11 1 ;;
{{- inc('LR7', stride) }}
    BLT.S LR11 {{ cr.wo }} fast_x ;;
{{- inc('LR9', SA) }}
    INC LR10 1 ;;
    BLT.S LR10 {{ cr.cout }} fast_co ;;
    HALT ;;
{% else %}
    SET LR9 CR0 ;;
    SET LR10 CR0 ;;
co_top:
    SET LR7 CR0 ;;
    SET LR11 CR0 ;;
oy_top:
    SET LR6 CR0 ;;
    SET LR3 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
ox_top:
    ADD LR5 LR7 LR6 ; ADD LR8 LR9 CR0 ;;
    SET LR13 CR0 ;;
ky_top:
{%- for s in range(kw * nbi) %}
    LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ;;
    LD.MULT R0 LR5 {{ cr.pad }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR3 {{ cr.ds_tail if s % nbi == nbi - 1 else 'CR15' }}.L ; INC LR8 1 ; INC LR5 1 ;;
{%- endfor %}
{{- inc('LR5', wpr - kw * nbi) }}
    INC LR13 1 ;;
    BLT.S LR13 LR14 ky_top ;;
{% if bias %}
    LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ;;
    NOP ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR3 {{ cr.ds1 }}.L ;;
{% endif %}
    INC LR3 1 ;;
{{- inc('LR6', stride * wpr) }}
    BLT.S LR3 {{ cr.ho }} ox_top ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsout0 }}.L {{ cr.qf }}.L {{ cr.out0 }} LR12 ;;
    INC LR12 1 ;;
{{- inc('LR7', stride * nbi) }}
    INC LR11 1 ;;
    BLT.S LR11 {{ cr.wo }} oy_top ;;
{{- inc('LR9', SA) }}
    INC LR10 1 ;;
    BLT.S LR10 {{ cr.cout }} co_top ;;
    HALT ;;
{% endif %}
{% endif %}
