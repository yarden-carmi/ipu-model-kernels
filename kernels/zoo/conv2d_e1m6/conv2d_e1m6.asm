{#- conv2d, fp8_e1m6, input channels on lanes (cin <= 128), output width on lanes (wo <= 128); one program for every size.
    Pass 1: copy the input into a zero-filled padded scratch `pad`, one row per padded (y, x).
    Pass 2: per (co, oy): the row starts with the bias step (MULT.RC.VE of the weight row 0 (lane 0 = bias) x 1.0,
      AGG.SUM.FIRST over ds(1) into slot ox; x 0.0 when bias is off). Then for each tap (ky looped, kx unrolled):
      the tap's weight row goes to R_CYCLIC once, and for ox = 0..wo-1 one word does MULT.RC.VV(weight row, pixel
      row (oy*stride+ky, ox*stride+kx)) and AGG.SUM into slot ox over ds(cin): only the cin active lanes are
      channels. After all taps, ACTIVATE.QUANTIZE stores the row (co, oy) with ds(wo) (lanes >= wo are zero).
    Weight rows (folded): row co*Sall + 0 = bias (lane 0), row co*Sall + 1 + ky*kw + kx = weights[co, :, ky, kx].
    Pixel rows alternate between R0 (even ox) and R1 (odd ox): a MULT.RC.VV needs its R0/R1 loaded two words
    earlier (a load one word earlier is not seen by the RC multiply), so each load is issued two words ahead.
    The loop body is two words (one even and one odd ox); ox beyond wo are computed into slots past wo and dropped
    by the store's ds(wo).
    Timing: LD lands in the next word; MULT reads R0 / R_CYCLIC at word start; LD/MULT/ACC/AAQ read LR operands at
    word end (an INC in the same word is seen); COND and LR ops read at word start (BLT sees the old value).
    Slot counter LR3 = ox - 1 before a word, so AGG dest (read after the INC) is ox and the BLT of the odd word
    (reading the even one's count) stops at xend = 2*ceil(wo/2) - 2.
    Register map: LR0 zero, LR2 input ptr (pass 1), LR3 ox slot, LR4 pad dest (pass 1), LR5 pixel ptr,
    LR6 x (pass 1), LR7 oy row base (pad rows), LR8 weight row ptr, LR9 co weight base, LR10 co, LR11 oy / y,
    LR12 out row, LR13 ky, LR14 ky row base, LR15 tap pixel base.                                  -#}
{%- macro inc(reg, n) -%}
{%- for k in range(0, n, 255) %}
    INC {{ reg }} {{ [255, n - k] | min }} ;;
{%- endfor -%}
{%- endmacro -%}
{%- set p = padding -%}
{%- set wp = w + 2 * p -%}
{%- set taps = kh * kw -%}
{%- set sall = taps + 1 -%}
{%- set bscale = 'CR1' if bias else 'CR0' -%}
    SET LR0 CR0 ;;
    SET LR2 CR0 ;;
    SET LR4 CR0 ;;
{{- inc('LR4', p * wp + p) }}
    SET LR11 CR0 ;;
py_top:
    SET LR6 CR0 ;;
px_top:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.dsc }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; INC LR2 1 ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsc }}.L {{ cr.qf }}.L {{ cr.pad }} LR4 ;;
    INC LR4 1 ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.w }} px_top ;;
{{- inc('LR4', 2 * p) }}
    INC LR11 1 ;;
    BLT.S LR11 {{ cr.h }} py_top ;;

    SET LR9 CR0 ;;
    SET LR10 CR0 ;;
co_top:
    SET LR7 CR0 ; SET LR11 CR0 ;;
oy_top:
    ADD LR14 LR7 CR0 ; SET LR3 CR0 ;;
    SET LR13 CR0 ; SUB LR3 LR3 CR1 ;;
    ADD LR8 LR9 CR0 ; LD.MULT.CYCLIC LR9 {{ cr.weights }} LR0 ;;
    INC LR8 1 ;;
bias_top:
    MULT.RC.VE LR0 {{ bscale }} 0 LR0 {{ cr.ds1 }}.L {{ cr.qf }}.L ; AGG.SUM.FIRST LR3 {{ cr.ds1 }}.L ; INC LR3 1 ;;
    MULT.RC.VE LR0 {{ bscale }} 0 LR0 {{ cr.ds1 }}.L {{ cr.qf }}.L ; AGG.SUM.FIRST LR3 {{ cr.ds1 }}.L ; INC LR3 1 ;
    BLT.S LR3 {{ cr.xend }} bias_top ;;
ky_top:
    ADD LR15 LR14 CR0 ;;
{%- for kx in range(kw) %}
    LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ; ADD LR5 LR15 CR0 ; INC LR15 1 ;;
    LD.MULT R0 LR5 {{ cr.pad }} ; SET LR3 CR0 ; INC LR8 1 ;;
    LD.MULT R1 LR5 {{ cr.pad }} ; INC LR5 {{ stride }} ; SUB LR3 LR3 CR1 ;;
tap_{{ kx }}_top:
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.dsc }}.L {{ cr.qf }}.L ; AGG.SUM LR3 {{ cr.dsc }}.L ; LD.MULT R0 LR5 {{ cr.pad }} ; INC LR5 {{ stride }} ; INC LR3 1 ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ cr.dsc }}.L {{ cr.qf }}.L ; AGG.SUM LR3 {{ cr.dsc }}.L ; LD.MULT R1 LR5 {{ cr.pad }} ; INC LR5 {{ stride }} ; INC LR3 1 ;
    BLT.S LR3 {{ cr.xend }} tap_{{ kx }}_top ;;
{%- endfor %}
{{- inc('LR14', wp) }}
    INC LR13 1 ;;
    BLT.S LR13 {{ cr.kh }} ky_top ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsout }}.L {{ cr.qf }}.L {{ cr.out0 }} LR12 ;;
    INC LR12 1 ;;
{{- inc('LR7', stride * wp) }}
    INC LR11 1 ;;
    BLT.S LR11 {{ cr.ho }} oy_top ;;
{{- inc('LR9', sall) }}
    INC LR10 1 ;;
    BLT.S LR10 {{ cr.cout }} co_top ;;
    HALT ;;
