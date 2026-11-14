{#- conv2d_hardswish_e2m5: conv2d (NCHW, channels on lanes) then hardswish via the AaQ generic LUT, e2m5.

    Stage 1 (pad): every input row (one pixel, one 128-channel block) is copied
    into a zero-filled padded scratch `pad` (row = (y+p)*wp + (x+p), block innermost).
    Stage 2 (conv): per output pixel and output block b (lanes = output channel):
      acc = bias row b  (slot 1 of R_CYCLIC, MULT.RC.VE by 1.0, ACC.ADD.FIRST)
      for each tap (ky,kx): LD.MULT R0 = pad row of the tap (block b for depthwise)
        dense:     for ic: R_CYCLIC slot 0 = folded weight row (tap,ic,b);
                   MULT.RC.VE scalar R0[ic] (src LR9 = ic), ACC.ADD
        depthwise: R_CYCLIC slot 0 = weight row (tap,b); MULT.RC.VV with R0, ACC.ADD
    Stage 3 (store): ACTIVATE.QUANTIZE generic (hardswish LUT) with DS dsout0 for
    block 0 and dsout1 for block 1, row = out0 + LR12 (q*nbo + b).
    Taps and channel blocks are unrolled from the parameters (kh, kw, cin/groups,
    nbo); spatial loops are counters against CRs (h, w, ho, wo).
    Timing rule: an LR write is visible to every slot of the same word, so no word
    both increments a register and reads it; increments go in their own words.
    Register map: LR0 zero, LR1 128 (bias slot), LR2 rb (pixel row), LR3 rby,
    LR4 tap-row ptr, LR5 tap ptr, LR8 weight row, LR9 ic (src), LR10 ox, LR11 oy/y,
    LR12 out row, LR14 wpr, LR15 block b.                                       -#}
{%- set nbi = (cin + 127) // 128 -%}
{%- set nbo = (cout + 127) // 128 -%}
{%- set cing = cin // groups -%}
{%- set dw = groups != 1 -%}
{%- set xs = stride * nbi -%}
    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    INC LR1 128 ;;
    SET LR12 CR0 ;;
    SET LR14 {{ cr.wpr }} ;;
    LD.LUT 0 {{ cr.lut }} LR0 ;;
    LD.LUT 1 {{ cr.lut }} LR0 ;;
    LD.LUT 2 {{ cr.lut }} LR0 ;;
    LD.LUT 3 {{ cr.lut }} LR0 ;;
    LD.LUT 4 {{ cr.lut }} LR0 ;;
    SET LR2 CR0 ;;
    SET LR3 CR0 ;;
{%- for i in range(padding) %}
    ADD LR3 LR3 LR14 ;;
{%- endfor %}
{%- if padding * nbi > 0 %}
    INC LR3 {{ padding * nbi }} ;;
{%- endif %}
    SET LR11 CR0 ;;
cy_loop:
    ADD LR4 LR3 CR0 ;;
    SET LR6 CR0 ;;
cx_loop:
{%- for b in range(nbi) %}
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.dsout0 }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; INC LR2 1 ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsout0 }}.L {{ cr.qf }}.L {{ cr.pad }} LR4 ;;
    INC LR4 1 ;;
{%- endfor %}
    INC LR6 1 ;;
    BLT.S LR6 {{ cr.w }} cx_loop ;;
    ADD LR3 LR3 LR14 ;;
    INC LR11 1 ;;
    BLT.S LR11 {{ cr.h }} cy_loop ;;

    SET LR3 CR0 ;;
    SET LR11 CR0 ;;
oy_loop:
    ADD LR2 LR3 CR0 ;;
    SET LR10 CR0 ;;
ox_loop:
    SET LR15 CR0 ;;
{%- for b in range(nbo) %}
{%- if b > 0 %}
    INC LR15 1 ;;
{%- endif %}
    LD.MULT.CYCLIC LR15 {{ cr.bias_vec }} LR1 ;;
    ADD LR8 LR15 CR0 ;;
{%- if dw %}
    ADD LR4 LR2 LR15 ;;
{%- else %}
    ADD LR4 LR2 CR0 ;;
{%- endif %}
    MULT.RC.VE LR1 CR1 0 LR0 {{ cr.dsout0 }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{%- for ky in range(kh) %}
{%- if ky > 0 %}
    ADD LR4 LR4 LR14 ;;
{%- endif %}
    ADD LR5 LR4 CR0 ;;
{%- for kx in range(kw) %}
    LD.MULT R0 LR5 {{ cr.pad }} ; SET LR9 CR0 ;;
    INC LR5 {{ nbi }} ;;
{%- for ic in range(cing) %}
    LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ;;
{%- if dw %}
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.dsout0 }}.L {{ cr.qf }}.L ; ACC.ADD ;;
{%- else %}
    MULT.RC.VE LR0 LR9 0 LR0 {{ cr.dsout0 }}.L {{ cr.qf }}.L ; ACC.ADD ;;
{%- endif %}
    INC LR8 {{ nbo }} ; INC LR9 1 ;;
{%- endfor %}
{%- endfor %}
{%- endfor %}
    ACTIVATE.QUANTIZE generic {{ cr.dsout0 if b == 0 else cr.dsout1 }}.L {{ cr.qf }}.L {{ cr.out0 }} LR12 ;;
    INC LR12 1 ;;
{%- endfor %}
    INC LR2 {{ xs }} ;;
    INC LR10 1 ;;
    BLT.S LR10 {{ cr.wo }} ox_loop ;;
{%- for i in range(stride) %}
    ADD LR3 LR3 LR14 ;;
{%- endfor %}
    INC LR11 1 ;;
    BLT.S LR11 {{ cr.ho }} oy_loop ;;
    HALT ;;
