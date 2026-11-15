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

    SET LR9 CR0 ;;
    SET LR10 CR0 ;;
co_top:
    SET LR7 CR0 ;;
    SET LR11 CR0 ;;
oy_top:
    SET LR6 CR0 ;;
    SET LR3 CR0 ;;
ox_top:
    ADD LR5 LR7 LR6 ; ADD LR8 LR9 CR0 ;;
    LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ;;
    LD.MULT R0 LR5 {{ cr.pad }} ; INC LR8 1 ;;
{%- for s in range(S) %}
{%- if s + 1 < T %}
{{- inc('LR5', offs[s + 1] - offs[s]) }}
{%- endif %}
{%- if s < T %}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM{% if s == 0 %}.FIRST{% endif %} LR3 {{ cr.ds_tail if s % nbi == nbi - 1 else 'CR15' }}.L{% if s + 1 < S %} ; LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0{% endif %} ;;
{%- else %}
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM{% if s == 0 %}.FIRST{% endif %} LR3 {{ cr.ds1 }}.L ;;
{%- endif %}
{%- if s + 1 < T %}
    LD.MULT R0 LR5 {{ cr.pad }} ; INC LR8 1 ;;
{%- elif s + 1 == T %}
    INC LR8 1 ;;
{%- endif %}
{%- endfor %}
    INC LR3 1 ; INC LR6 {{ stride * nbi }} ;;
    BLT.S LR3 {{ cr.wo }} ox_top ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsout0 }}.L {{ cr.qf }}.L {{ cr.out0 }} LR12 ;;
    INC LR12 1 ;;
{{- inc('LR7', stride * wpr) }}
    INC LR11 1 ;;
    BLT.S LR11 {{ cr.ho }} oy_top ;;
    INC LR9 {{ SA }} ;;
    INC LR10 1 ;;
    BLT.S LR10 {{ cr.cout }} co_top ;;
    HALT ;;
