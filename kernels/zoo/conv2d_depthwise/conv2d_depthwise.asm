{#- conv2d_depthwise.asm -- y = conv2d(x, W) + b for a DEPTHWISE window
    (groups == cin == cout), one parameterised program for every
    (h, w, cin, cout, kh, kw, stride, padding, groups, bias).

    Layouts (kernel.toml's [abi]; every operand is a ROW number, one row = 128
    lanes). x and y are the layout every activation on the chip uses: pixel p
    (row-major (y, x) order) holds its channels in rows p*chunks + c. W is a
    constant prepared offline, kh*kw rows per channel chunk: row t*chunks + c is
    tap t = ky*kw + kx's weight for that chunk's 128 channels (pack.py's
    tap_major), so one word multiplies an input pixel row by that tap's weight
    row lane-wise -- which is what a depthwise conv is. bias is one row per
    chunk. The mask row and the zeros row are the only scratch.

    Dataflow per output pixel and channel chunk: kh*kw taps. A tap is one
    MULT.RC.VV of the tap's input row (an R_CYCLIC slot, loaded by the word
    before) by the tap's weight row (R0, loaded by the word before), ACC.ADD'd
    into the pixel's 128 accumulators. A word has ONE load slot, so a tap costs
    its two loads -- two words -- and the word that loads tap t's input row
    multiplies tap t-1, so no word waits on a load; the word after the last
    load multiplies, accumulates and stores the row (MULT+ACC+ACTIVATE.QUANTIZE
    ride one word: MULT_RES forwards to ACC and R_ACC forwards to the AaQ).
    With a bias the pixel's first word opens the accumulator from the chunk's
    bias row, resident in R1 for the whole pass (MULT.VE by the CR constant 1.0,
    ACC.ADD.FIRST); without one the pixel's first multiply does (ACC.ADD.FIRST).

    Addresses: the input row of tap (ky, kx) of output pixel (oy, ox) is
    ((oy*stride + ky - padding)*w + ox*stride + kx - padding)*chunks + c, so a
    tap owns one LR holding that row: the tap's second word advances it by
    stride*chunks (an immediate, and the word no longer uses it), and a row's
    end advances every tap by stride*chunks*(w - out_w) from a CR. The y row is
    one more per output pixel, so pixels are visited in raster order and it
    never needs a reset -- it advances in the word that stores with it.

    Out-of-image taps contribute nothing: they are not skipped (that would make
    each edge copy load a different number of rows and desync the weight and
    input pointers), they read the zeros row instead -- LD.MULT.CYCLIC with the
    zeros region as its base and LR0 (0) as its offset. The tap's LR still
    advances, so one LR per tap serves every copy of the body, every word of
    every copy has the same shape, and a clamped tap multiplies 0 by its weight
    and adds 0. Two details of that "adds 0" are worth naming: the row is
    pack.py's zero_row, sized to the variant's row (512 bytes of 0x00 in FP32,
    the IEEE code of 0.0 in every lane -- an NX8 row would need its clamp
    exponent with a zero mantissa instead, since an NX8 byte 0x00 is
    2**(scale-127)); and a clamped tap's multiply is MULT.RC.VE against the CR
    constant 1.0 rather than by its weight row, because 0 * (-w) is -0.0 and an
    output pixel whose taps all clamp would then store a row of negative zeros
    where the reference sums to +0.0. The weight row is still
    loaded: a word that stopped loading would be a different word, and the
    pointer chain is the same in every copy.
    padding <= stride (kernel.toml's guard) keeps every tap of every
    interior pixel of every middle output row inside the image, so only a row's
    first and last pixel and the image's first and last row can clamp, and which
    taps do is known when the program renders. Nothing is ever read outside a
    region.

    Loops: the interior pixel loop and the middle row loop are dynamic -- the
    call's size reaches them through CRs and LRs only, so 4096 output pixels is
    4096 iterations of the same words. Their counters count up from 0 and the
    branch reads the counter as the word began it, so a loop whose bound CR is
    B runs B+1 trips (the bound is one less than the trip count). The
    channel-chunk loop (ceil(cout/128) <= 4 copies) and the kh*kw taps are
    rendered around them, which frees the counters' LR sub-slots for the body
    and lets the last, short chunk store with its own DS half.

    LR: LR0 0; LR1 128 (the two R_CYCLIC slots' element offsets, and R1's
    element offset in Ra); LR2 the pixel loop's counter; LR3 the row loop's;
    LR4..LR12 the taps' input rows; LR13 the y row being stored; LR14 the weight
    row pointer; LR15 this chunk's number (its bias row, its tap-0 weight row).
    Every LR the program reads is set by it and R_MASK is loaded from its own
    row, so it runs after another kernel as well as from reset.
-#}
{% set chunks = (cin + 127) // 128 %}
{% set ctiles = (cout + 127) // 128 %}
{% set tail = cout - 128 * (ctiles - 1) %}
{% set out_h = (h + 2 * padding - kh) // stride + 1 %}
{% set out_w = (w + 2 * padding - kw) // stride + 1 %}
{% set taps = [] %}
{% for ky in range(kh) %}{% for kx in range(kw) %}{% set _ = taps.append((ky, kx)) %}{% endfor %}{% endfor %}
{% set nt = taps | length %}
{% set step = stride * chunks %}
{% set qfx = cr.qf ~ ".L" %}
{% macro alr(k) -%}LR{{ 4 + k }}{%- endmacro %}
{% macro slot(k) -%}{{ "LR0" if k % 2 == 0 else "LR1" }}{%- endmacro %}
{#- one output pixel: two words a tap (the load of this tap, the multiply of
    the previous one), then the word that multiplies, accumulates and stores.
    `setup` opens the pixel loop's counter, `lbl` makes it the loop's body -#}
{% macro pixel(cl_left, cl_right, vtop, vbot, dsx, setup, lbl) -%}
{% set oobs = [] %}
{% for k in range(nt) %}
{% set ky = taps[k][0] %}{% set kx = taps[k][1] %}
{% set _ = oobs.append((vtop and ky < padding)
             or (vbot and (out_h - 1) * stride + ky - padding >= h)
             or (cl_left and kx < padding)
             or (cl_right and (out_w - 1) * stride + kx - padding >= w)) %}
{% endfor %}
{#- the product of tap t: its row is in slot(t), its weights in R0 -- and an
    out-of-image tap's row is the zeros row, so the weights are not needed and
    the multiply is by the constant 1.0: 0 * (-w) is -0.0 and a whole row of
    negative zeros stores differently from the reference's +0.0 sum, while
    0 * 1.0 is +0.0 exactly. -#}
{% macro prod(t) -%}
{% if oobs[t] %}MULT.RC.VE {{ slot(t) }} CR1 0 LR0 {{ dsx }} {{ qfx }}
{% else %}MULT.RC.VV {{ slot(t) }} R0 0 LR0 {{ dsx }} {{ qfx }}{% endif %}
{%- endmacro %}
{% for k in range(nt) %}
{% if k == 0 %}
    LD.MULT.CYCLIC {{ "LR0" if oobs[k] else alr(k) }} {{ cr.zeros if oobs[k] else cr.x }} {{ slot(k) }}{% if bias %} ;
    MULT.VE LR1 CR1 0 LR0 {{ dsx }} {{ qfx }} ;
    ACC.ADD.FIRST{% endif %} ;
    SET LR14 LR15{% if setup %} ;
    SET LR2 CR0{% endif %} ;
    INC LR13 {{ ctiles }} ;;
{% else %}
    LD.MULT.CYCLIC {{ "LR0" if oobs[k] else alr(k) }} {{ cr.zeros if oobs[k] else cr.x }} {{ slot(k) }} ;
    {{ prod(k - 1) }} ;
    {{ "ACC.ADD.FIRST" if (k == 1 and not bias) else "ACC.ADD" }} ;
    INC LR14 {{ chunks }} ;;
{% endif %}
    LD.MULT R0 LR14 {{ cr.wt }} ;
    INC {{ alr(k) }} {{ step }} ;;
{% endfor %}
    {{ prod(nt - 1) }} ;
    {{ "ACC.ADD.FIRST" if (nt == 1 and not bias) else "ACC.ADD" }} ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfx }} {{ cr.y }} LR13{% if lbl %} ;
    INC LR2 1 ;
    BLT.S LR2 {{ cr.nint1 }} {{ lbl }}{% endif %} ;;
{%- endmacro %}
{#- one output row: the first pixel, the interior pixels as a loop, the last
    pixel (a one-pixel row is one copy clamped on both sides) -#}
{% macro rowbody(vtop, vbot, dsx, tag) -%}
{% if out_w >= 2 %}
{{ pixel(true, false, vtop, vbot, dsx, out_w > 2, "") }}
{% if out_w > 2 %}
ip{{ tag }}:
{{ pixel(false, false, vtop, vbot, dsx, false, "ip" ~ tag) }}
{% endif %}
{{ pixel(false, true, vtop, vbot, dsx, false, "") }}
{% else %}
{{ pixel(true, true, vtop, vbot, dsx, false, "") }}
{% endif %}
{%- endmacro %}
{#- the row's end: every tap's row moves on to the next output row; with a
    target it is also the row loop's back edge (the counter counts up from 0
    and the branch reads it before this word's INC) -#}
{% macro rowend(target) -%}
{% set g = [] %}{% for t in range(nt) %}{% set _ = g.append("ADD " ~ alr(t) ~ " " ~ alr(t) ~ " " ~ cr.rowfix) %}{% endfor %}
{% for i in range(0, g | length, 3) %}
    {{ g[i:i + 3] | join(" ; ") }} ;;
{% endfor %}
{% if target %}
    INC LR3 1 ;
    BLT.S LR3 {{ cr.rowcount }} {{ target }} ;;
{% endif %}
{%- endmacro %}
{#- the taps' rows for this chunk: LR15 (the chunk number) plus the tap's
    constant part, built in groups so no register is written twice a word -#}
{% macro initaddrs() -%}
{% set g1 = [] %}{% set g2 = [] %}{% set g3 = [] %}{% set g4 = [] %}{% set g5 = [] %}
{% for t in range(nt) %}
{% set ky = taps[t][0] %}{% set kx = taps[t][1] %}
{% set _ = g1.append("SET " ~ alr(t) ~ " LR15") %}
{% set _ = g2.append("ADD " ~ alr(t) ~ " " ~ alr(t) ~ " " ~ cr.negbase) %}
{% if ky >= 1 %}{% set _ = g3.append("ADD " ~ alr(t) ~ " " ~ alr(t) ~ " " ~ cr.wchunk) %}{% endif %}
{% if ky >= 2 %}{% set _ = g4.append("ADD " ~ alr(t) ~ " " ~ alr(t) ~ " " ~ cr.wchunk) %}{% endif %}
{% if kx == 1 %}{% set _ = g5.append("INC " ~ alr(t) ~ " " ~ chunks) %}
{% elif kx == 2 %}{% set _ = g5.append("INC " ~ alr(t) ~ " " ~ (2 * chunks)) %}{% endif %}
{% endfor %}
{% for g in [g1, g2, g3, g4, g5] %}{% for i in range(0, g | length, 3) %}
    {{ g[i:i + 3] | join(" ; ") }} ;;
{% endfor %}{% endfor %}
{%- endmacro %}

    SET LR0 CR0 ;;                                      {#- 0, the even R_CYCLIC slot, the zeros row -#}
    SET LR1 CR0 ;;                                      {#- 128: the odd slot and R1's element -#}
    INC LR1 128 ;;                                      {#- ... offset in Ra (one write per word) -#}
    LD.MASK LR0 {{ cr.maskr }} ;;                       {#- every lane of every multiply active -#}
{% for cc in range(chunks) %}
{% set dsx = cr.ds ~ (".H" if (cc == ctiles - 1 and tail != 128) else ".L") %}
{% if cc == 0 %}
    SET LR15 CR0 ;;                                     {#- this chunk's number -#}
{% else %}
    INC LR15 1 ;;                                       {#- ... the next chunk's -#}
{% endif %}
    SET LR13 LR15 ;                                     {#- the y row it stores -#}
    SET LR3 CR0 ;;
    DEC LR13 {{ chunks }} ;;                             {#- ... one behind: tap 0's word advances it -#}
{{ initaddrs() }}
{% if bias %}
    LD.MULT R1 LR15 {{ cr.b }} ;;                       {#- this chunk's bias row, resident -#}
{% endif %}
{#- ---------------------- the image's first output row ---------------------#}
{{ rowbody(true, out_h == 1, dsx, "t" ~ cc) }}
{% if out_h == 2 %}
{{ rowend("") }}
{% endif %}
{% if out_h > 2 %}
{{ rowend("") }}
{#- --------------------- the image's middle output rows --------------------#}
mid{{ cc }}:
{{ rowbody(false, false, dsx, "m" ~ cc) }}
{{ rowend("mid" ~ cc) }}
{% endif %}
{#- ---------------------- the image's last output row ----------------------#}
{% if out_h > 1 %}
{{ rowbody(false, true, dsx, "b" ~ cc) }}
{% endif %}
{% endfor %}
end:
    HALT ;;
