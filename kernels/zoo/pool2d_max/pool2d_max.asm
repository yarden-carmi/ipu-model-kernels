{#- pool2d_max.asm -- y = maxpool2d(x, k x k, stride, padding) for the row
    layout every activation on the chip uses.

    LAYOUT: x[h, w, channels], pixels in row-major (y, x) order, pixel p
    holding its channels in ceil(channels/128) consecutive rows -- row
    (py*w+px)*chunks + c holding channels 128c .. 128c+127, lanes past
    channels zero. y[out_h, out_w, channels] is exactly the same layout, so
    the kernel reads what the previous kernel wrote and leaves what the next
    one reads, with no repack.

    DATAFLOW: a max over a window is a chain of ACC.MAX, and the only way
    into R_ACC is a multiply result -- so every tap is multiplied by the CR
    constant 1.0 (MULT.RC.VE of R_CYCLIC slot 0) and accumulated. The FIRST
    valid tap of every chunk walk takes ACC.MAX.FIRST (a flag LR routes it
    there), which clean-initialises R_ACC, so no -inf seed row and no
    register a previous kernel left can matter; every later tap is ACC.MAX.
    The store is ACTIVATE.QUANTIZE, preceded in its word by an idempotent
    MULT+ACC.MAX of the last tap (AAQ reads the cycle's ACC result).

    PADDING: a tap outside the image contributes nothing to a max, so its
    iteration only walks the pointer -- the window rows and columns are
    checked against h and w (LR bounds) and the invalid ones fall straight
    through to the pointer advance. A skipped window ROW advances the
    pointer by a whole spatial row (CR13) instead of wkr, which is what
    keeps LR1 = (gy*w+gx)*chunks + c exactly. `padding <= k-1` (kernel.toml's
    guard, folded into y's shape) makes every output pixel have at least one
    valid tap, so ACC.MAX.FIRST always initialises from real data.

    LOOPS: one dynamic loop over the output pixels, the k x k tap grid
    inside it per chunk (chunks is unrolled, at most two). The program is
    one launch for the whole call, shape-independent: every bound is a
    register (LR13 h, LR14 w, LR15 k, CR11 out_w, CR12 out_h), never baked
    into the instruction stream.

    POINTERS: LR2 = stride*(oy*w+ox)*chunks, the window origin relative to
    the image corner; LR1 = LR2 - pre + c is the absolute tap row (pre =
    padding*(w+1)*chunks, what the corner is short by), walked by chunks
    (CR5) across a window row and wkr = (w-k+1)*chunks (CR6) across one --
    or by w*chunks (CR13) for a skipped row. LR9/LR10 are the window's
    top-left pixel (y0, x0 = oy*stride-padding, ...), LR6/LR7 the running
    gy/gx checked against the bounds, LR3 the output row (one behind its
    store), LR8 the initialised flag, LR11/LR12 the pixel and row counters.

    LR: LR0 0 (mask shift, R_CYCLIC slot 0, the zero compare); LR1..LR12 as
    above; LR13..LR15 the h/w/k bounds, written by the loader and never by
    the program. The program sets every LR it relies on (the bounds come
    from [abi]) and loads its own mask row, so it runs after another kernel
    as well as from reset.
-#}
{% set dst = cr.ds ~ (".H" if (chunks > 1 and channels % 128 != 0) else ".L") %}
{% set qfl = cr.qf ~ ".L" %}

    SET LR0 CR0 ;;
    LD.MASK LR0 {{ cr.maskr }} ;;                         {#- every lane active -#}
    SET LR2 CR0 ;;                                        {#- origin' = 0 -#}
    SET LR3 CR0 ;;
    SUB LR3 LR3 CR1 ;;                                    {#- output rows, one behind -#}
    SET LR9 CR0 ;;
    SUB LR9 LR9 {{ cr.pad }} ;;                           {#- y0 = -padding -#}
    SET LR10 CR0 ;;
    SUB LR10 LR10 {{ cr.pad }} ;;                         {#- x0 = -padding -#}
    SET LR11 CR0 ;
    SET LR12 CR0 ;;                                       {#- pixel and row counters -#}
{#- ==================== the whole call: one dynamic loop ==================== -#}
row_loop:                                       {#- the pixel loop's top too -#}
{%- for c in range(chunks) %}
{%- set dsl = (dst if (chunks > 1 and c == chunks - 1) else (cr.ds ~ ".L")) %}
    SET LR1 LR2 ;;                                        {#- tap pointer <- origin' -#}
    SUB LR1 LR1 {{ cr.pre }} ;;                           {#- ... less the corner gap -#}
{%- if c > 0 %}
    INC LR1 {{ c }} ;;                                    {#- chunk c's lane offset -#}
{%- endif %}
    SET LR8 CR0 ;                                         {#- R_ACC not initialised yet -#}
    SET LR4 CR0 ;;                                        {#- ky counter -#}
    SET LR6 LR9 ;                                         {#- gy = y0 -#}
    INC LR3 1 ;;                                          {#- this chunk's output row -#}
ky_loop{{ c }}:
    BLT.S LR6 LR0 ky_skip{{ c }} ;;                       {#- window row above the image -#}
    BGE.S LR6 LR13 ky_skip{{ c }} ;;                      {#- ... or below it -#}
    SET LR7 LR10 ;                                        {#- gx = x0 -#}
    SET LR5 CR0 ;;                                        {#- kx counter -#}
kx_loop{{ c }}:
    BLT.S LR7 LR0 kx_next{{ c }} ;;                       {#- window col left of the image -#}
    BGE.S LR7 LR14 kx_next{{ c }} ;;                      {#- ... or right of it -#}
    LD.MULT.CYCLIC LR1 {{ cr.x }} LR0 ;;                  {#- slot 0 <- the tap's row -#}
    BNE LR8 LR0 acc{{ c }} ;;                             {#- R_ACC initialised? -#}
    MULT.RC.VE LR0 CR1 0 LR0 {{ dsl }} {{ qfl }} ;
    ACC.MAX.FIRST ;
    INC LR8 1 ;;                                          {#- ... it is now -#}
acc{{ c }}:
    MULT.RC.VE LR0 CR1 0 LR0 {{ dsl }} {{ qfl }} ;
    ACC.MAX ;;
kx_next{{ c }}:
    INC LR7 1 ;                                           {#- next column -#}
    ADD LR1 LR1 {{ cr.chunks }} ;                         {#- pointer: next pixel's row -#}
    INC LR5 1 ;;
    BLT.S LR5 LR15 kx_loop{{ c }} ;;                      {#- kx < k -#}
    ADD LR1 LR1 {{ cr.wkr }} ;;                           {#- a full row: + (w-k+1)*chunks -#}
    BEQ LR15 LR15 ky_inc{{ c }} ;;
ky_skip{{ c }}:
    ADD LR1 LR1 {{ cr.wr }} ;;                            {#- a skipped row: + w*chunks -#}
ky_inc{{ c }}:
    INC LR6 1 ;                                           {#- gy -#}
    INC LR4 1 ;;
    BLT.S LR4 LR15 ky_loop{{ c }} ;;                      {#- ky < k -#}
    MULT.RC.VE LR0 CR1 0 LR0 {{ dsl }} {{ qfl }} ;        {#- idempotent re-max of the -#}
    ACC.MAX ;                                             {#- ... last tap, for the store -#}
    ACTIVATE.QUANTIZE identity {{ dsl }} {{ qfl }} {{ cr.y }} LR3 ;;
{%- endfor %}
    INC LR10 {{ stride }} ;                               {#- next pixel's x0 -#}
    ADD LR2 LR2 {{ cr.spr }} ;;                           {#- ... and origin -#}
    INC LR11 1 ;;
    BLT.S LR11 {{ cr.out_w }} row_loop ;;                 {#- more pixels in this row -#}
    SET LR10 CR0 ;;                                       {#- row done: x0 <- -padding -#}
    SUB LR10 LR10 {{ cr.pad }} ;;
    SET LR11 CR0 ;;
    INC LR9 {{ stride }} ;;                               {#- the next row's y0 -#}
    ADD LR2 LR2 {{ cr.rowstep }} ;;                       {#- origin: one output row on -#}
    INC LR12 1 ;;
    BLT.S LR12 {{ cr.out_h }} row_loop ;;                 {#- more output rows -#}
end:
    HALT ;;
