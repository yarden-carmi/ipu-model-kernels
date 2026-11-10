{#- row_norm.asm -- per-row normalisation over `channels`, one parameterised
    program for every (kind, rows, channels).

        layernorm  y[r, j] = (x[r, j] - mean_r) * A_r * gamma[j] + beta[j]
        rmsnorm    y[r, j] =  x[r, j]           * A_r * gamma[j]
        A_r        = rsqrt(max(mean_j x[r,j]^2 - mean_j^2 x[r,j], eps))   (ln)
        A_r        = rsqrt(max(mean_j x[r,j]^2, eps))                     (rms)

    Layout (kernel.toml's [abi]; every operand is a ROW number, one row = 128
    lanes): entity r owns ceil(channels / 128) = chunks consecutive rows, row
    r * chunks + c holding channels 128c .. 128c + 127, lanes past `channels`
    zero -- the layout every activation on the chip uses, so y is the next
    kernel's x. gamma and beta are `chunks` rows each, kept as prepared; `sca`
    is the group's four bookkeeping rows (means, squares, A, D); `p` is the
    kernel's one matrix of scratch; invn, epsr and maskr are constant rows.

    Work is per group of up to 128 rows: the R_ACC lanes are the bookkeeping,
    one lane per row of the group, which is what bounds a group at 128 rows.
    Passes (the header of kernel.toml walks them): the two reductions (the means,
    then the squares) at one word per (row, chunk) each, the group's two scalar
    rows straight-line, then p = A_r * x + D_r and y = p * gamma + beta at two
    words per (row, chunk) -- one multiply-accumulate pair is all a word holds,
    and y's three products (A_r, x, gamma) cannot meet in one of them.

    Timing contract: the Control stage (LR writes and the branch) reads LRs at
    cycle start, the LOAD/MULT/ACC/AAQ stages read them after the same word's LR
    writes (forwarded), and MULT reads R0/R1/R_CYCLIC as the word began. So a row
    loop keeps its counters one behind (LR2 starts at -1 and the word that
    multiplies row i is the word that INCs it: its MULT, AGG and AAQ see i, its
    branch i - 1) and prefetches the next row with the pointer it just advanced.
    A one-word body therefore branches against rows_rem - 2 (LR3) and a
    two-word body, whose INC sits in its first word, against rows_rem - 1 (LR7).
    Two LR sub-slots never write one register in one word (fault F-3), which is
    why a counter is seeded and decremented in two words.

    An NX8 row is a block format: one scale for the row, taken from its largest
    ACTIVE element, and one or two exponent bits. So every lane a store writes
    must be within a few factors of every other one, or the small lanes quantize
    to zero. That is what bounds a group at 128 rows *and* decides how the
    program is rendered: `rows` is known when the program is assembled, so the
    full groups (always exactly 128 rows) are emitted once as a dynamic loop and
    the short last group, if there is one, is emitted a second time with its own
    DS half, ds(rows % 128), for the row of A. A group's bookkeeping lanes past
    its last row would otherwise hold rsqrt(eps) = 316 against a real A of ~1.7,
    and the row's scale would come from them and flush every real A to zero.

    LR: LR0 0; LR1 the row being read (its cycle-start value is the row the word
    multiplies, its forwarded value the row the word loads); LR2 the
    group-relative row index; LR3 the one-word bound (rows_rem - 2); LR4 the p
    or y row being stored; LR5 the D_r element of Ra (128 + the row index); LR6
    the group's first row; LR7 the two-word bound (rows_rem - 1); LR8 the rows
    left in this render; LR9 128 * chunks (the group stride); LR10 128 (beta's
    element offset in Ra, and the group cap); LR11..LR14 the constants 1..4,
    which are also the chunk offsets and the `sca` row numbers (means LR0,
    squares LR11, A LR12, D LR13); LR15 spare. The program sets every LR it
    reads, zeroes R_ACC before each reduction and loads its own mask row, so it
    runs after another kernel as well as from reset.
-#}
{% set chunks = (channels + 127) // 128 %}
{% set ln = kind == "layernorm" %}
{% set tail = channels - 128 * (chunks - 1) %}
{% set groups_full = rows // 128 %}
{% set rows_tail = rows % 128 %}
{% set dall = cr.ds ~ ".L" %}
{% set dlast = cr.ds ~ (".H" if tail != 128 else ".L") %}
{% set qfl = cr.qf ~ ".L" %}
{% set coff = ["LR0", "LR11", "LR12", "LR13"] %}
{% set cstr = ["LR0", "LR11", "LR12", "LR13", "LR14"] %}
{% macro dsof(c) -%}{{ dlast if c == chunks - 1 else dall }}{%- endmacro -%}
{% macro zero() -%}
    LD.MULT R0 LR0 {{ cr.invn }} ;;                       {#- a finite row to multiply by 0.0 -#}
    MULT.VE LR0 CR0 0 LR0 {{ dall }} {{ qfl }} ;
    ACC.ADD.FIRST ;;                                      {#- R_ACC := 0 in every lane (a group's unused rows) -#}
{%- endmacro -%}
{% macro index() -%}
    SET LR2 CR0 ;;
    DEC LR2 1 ;;                                          {#- the row index, one behind: -1 -#}
{%- endmacro -%}
{% macro redloop(label, c, sq) -%}
    ADD LR1 LR6 {{ coff[c] }} ;;                          {#- the group's row 0 of chunk {{ c }} -#}
    LD.MULT.CYCLIC LR1 {{ cr.x }} LR0 ;;                  {#- prime R_CYCLIC[0..127] with x[0, {{ c }}] -#}
{{ index() }}
{{ label }}{{ c }}:
{% if sq %}
    MULT.RC.VS LR0 0 LR0 {{ dall }} {{ qfl }} ;           {#- x^2, and R0/R1 are not read -#}
{% else %}
    MULT.RC.VV LR0 R0 0 LR0 {{ dall }} {{ qfl }} ;        {#- x * (1/channels): the mean reduces directly -#}
{% endif %}
    AGG.SUM LR2 {{ dall }} ;                              {#- into the row's bookkeeping lane -#}
    ADD LR1 LR1 {{ cstr[chunks] }} ; INC LR2 1 ;
    LD.MULT.CYCLIC LR1 {{ cr.x }} LR0 ;                   {#- the row the NEXT word reduces -#}
    BLT.S LR2 LR3 {{ label }}{{ c }} ;;
{%- endmacro -%}
{% macro group(pfx, ds_a) -%}
    SET LR7 LR8 ;;                                        {#- rows_rem = the rows left, capped at 128 -#}
    BLT.S LR7 LR10 {{ pfx }}sized ;;
    SET LR7 LR10 ;;
{{ pfx }}sized:
    ADD LR3 LR7 CR0 ; SUB LR7 LR7 CR1 ;;                  {#- the two-word bound rows_rem - 1 -#}
    SUB LR3 LR3 CR1 ;;
    SUB LR3 LR3 CR1 ;;                                    {#- the one-word bound rows_rem - 2 -#}
{% for c in range(chunks) %}
{% if c == 0 %}
{{ zero() }}
{% endif %}
{{ redloop(pfx ~ "sum", c, false) }}
{% endfor %}
    ACTIVATE.QUANTIZE identity {{ dall }} {{ qfl }} {{ cr.sca }} LR0 ;;   {#- sca[0] = the group's means -#}
{% for c in range(chunks) %}
{% if c == 0 %}
{{ zero() }}
{% endif %}
{{ redloop(pfx ~ "sq", c, true) }}
{% endfor %}
    ACTIVATE.QUANTIZE identity {{ dall }} {{ qfl }} {{ cr.sca }} LR11 ;;  {#- sca[1] = the group's squares -#}

{#- -------- pass 2: the group's A (the hardware rsqrt) and D -------------- -#}
    LD.MULT R0 LR0 {{ cr.invn }} ;;                       {#- R0 = 1/channels in every lane -#}
    LD.MULT.CYCLIC LR11 {{ cr.sca }} LR0 ;;               {#- the squares -#}
    MULT.RC.VV LR0 R0 0 LR0 {{ dall }} {{ qfl }} ;
    ACC.ADD.FIRST ;;                                      {#- R_ACC = the mean of squares -#}
{% if ln %}
    LD.MULT.CYCLIC LR0 {{ cr.sca }} LR0 ;;                {#- the means, as the row holds them -#}
    MULT.RC.VS LR0 0 LR0 {{ dall }} {{ qfl }} ;
    ACC.SUB ;;                                            {#- R_ACC = the variance (m2 - mean^2) -#}
{% endif %}
    LD.MULT R0 LR0 {{ cr.epsr }} ;;                       {#- R0 = eps in every lane -#}
    MULT.EE LR0 CR1 0 LR0 {{ dall }} {{ qfl }} ;
    ACC.MAX ;                                             {#- floor it, so the rsqrt never sees a negative -#}
    ACTIVATE.QUANTIZE rsqrt {{ ds_a }} {{ qfl }} {{ cr.sca }} LR12 ;;   {#- sca[2] = A = 1/sigma -#}
{% if ln %}
    LD.MULT.CYCLIC LR0 {{ cr.sca }} LR0 ;;                {#- the means -#}
    LD.MULT R0 LR12 {{ cr.sca }} ;;                       {#- R0 = the group's A row -#}
    MULT.RC.VV LR0 R0 0 LR0 {{ dall }} {{ qfl }} ;
    ACC.SUB.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dall }} {{ qfl }} {{ cr.sca }} LR13 ;;  {#- sca[3] = D = -(mean * A) -#}
{% endif %}

{#- -------- pass 3: p = A_r * x + D_r ====================================== -#}
{% for c in range(chunks) %}
    ADD LR1 LR6 {{ coff[c] }} ;;
    LD.MULT R0 LR12 {{ cr.sca }} ;;                       {#- R0 = the A row, resident for the pass -#}
{% if ln %}
    LD.MULT R1 LR13 {{ cr.sca }} ;;                       {#- R1 = the D row -#}
    LD.MULT.CYCLIC LR1 {{ cr.x }} LR0 ;;                  {#- prime with x[0, {{ c }}] -#}
{{ index() }}
    SET LR5 LR10 ;;
    DEC LR5 1 ;;                                          {#- D_r's Ra element, one behind -#}
{{ pfx }}p{{ c }}:
    MULT.RC.VE LR0 LR2 0 LR0 {{ dall }} {{ qfl }} ;       {#- A_r * x[r, {{ c }}] -#}
    ACC.ADD.FIRST ;
    ADD LR4 LR1 CR0 ; INC LR2 1 ; ADD LR5 LR5 CR1 ;;
    MULT.EE LR5 CR1 0 LR0 {{ dall }} {{ qfl }} ;          {#- + D_r, broadcast -#}
    ACC.ADD ;
    ACTIVATE.QUANTIZE identity {{ dsof(c) }} {{ qfl }} {{ cr.p }} LR4 ;
    ADD LR1 LR1 {{ cstr[chunks] }} ;
    LD.MULT.CYCLIC LR1 {{ cr.x }} LR0 ;                   {#- the row the next word multiplies -#}
    BLT.S LR2 LR7 {{ pfx }}p{{ c }} ;;
{% else %}
    LD.MULT.CYCLIC LR1 {{ cr.x }} LR0 ;;                  {#- prime with x[0, {{ c }}] -#}
{{ index() }}
{{ pfx }}p{{ c }}:
    MULT.RC.VE LR0 LR2 0 LR0 {{ dall }} {{ qfl }} ;       {#- A_r * x[r, {{ c }}] -#}
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dsof(c) }} {{ qfl }} {{ cr.p }} LR4 ;
    ADD LR4 LR1 CR0 ; ADD LR1 LR1 {{ cstr[chunks] }} ; INC LR2 1 ;
    LD.MULT.CYCLIC LR1 {{ cr.x }} LR0 ;
    BLT.S LR2 LR3 {{ pfx }}p{{ c }} ;;
{% endif %}
{% endfor %}

{#- -------- pass 4: y = p * gamma + beta =================================== -#}
{% for c in range(chunks) %}
    ADD LR1 LR6 {{ coff[c] }} ;;
    LD.MULT R0 {{ coff[c] }} {{ cr.gamma }} ;;            {#- R0 = chunk {{ c }}'s gamma, resident -#}
{% if ln %}
    LD.MULT R1 {{ coff[c] }} {{ cr.beta }} ;;             {#- R1 = chunk {{ c }}'s beta -#}
    LD.MULT.CYCLIC LR1 {{ cr.p }} LR0 ;;                  {#- prime with p[0, {{ c }}] -#}
{{ index() }}
{{ pfx }}y{{ c }}:
    MULT.RC.VV LR0 R0 0 LR0 {{ dall }} {{ qfl }} ;        {#- p * gamma -#}
    ACC.ADD.FIRST ;
    ADD LR4 LR1 CR0 ; ADD LR1 LR1 {{ cstr[chunks] }} ; INC LR2 1 ;;
    MULT.VE LR10 CR1 0 LR0 {{ dall }} {{ qfl }} ;         {#- + beta, read out of R1 -#}
    ACC.ADD ;
    ACTIVATE.QUANTIZE identity {{ dsof(c) }} {{ qfl }} {{ cr.y }} LR4 ;
    LD.MULT.CYCLIC LR1 {{ cr.p }} LR0 ;
    BLT.S LR2 LR7 {{ pfx }}y{{ c }} ;;
{% else %}
    LD.MULT.CYCLIC LR1 {{ cr.p }} LR0 ;;
{{ index() }}
{{ pfx }}y{{ c }}:
    MULT.RC.VV LR0 R0 0 LR0 {{ dall }} {{ qfl }} ;        {#- p * gamma -#}
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dsof(c) }} {{ qfl }} {{ cr.y }} LR4 ;
    ADD LR4 LR1 CR0 ; ADD LR1 LR1 {{ cstr[chunks] }} ; INC LR2 1 ;
    LD.MULT.CYCLIC LR1 {{ cr.p }} LR0 ;
    BLT.S LR2 LR3 {{ pfx }}y{{ c }} ;;
{% endif %}
{% endfor %}
{%- endmacro -%}

    SET LR0 CR0 ;;                                        {#- the hard zero every loop reads -#}
    SET LR11 CR1 ;;                                       {#- 1 -#}
    SET LR12 CR1 ;;
    ADD LR12 LR12 LR12 ;;                                 {#- 2 -#}
    SET LR13 CR1 ;;
    ADD LR13 LR13 LR13 ;;
    ADD LR13 LR13 CR1 ;;                                  {#- 3 -#}
    SET LR14 CR1 ;;
    ADD LR14 LR14 LR14 ;;
    ADD LR14 LR14 LR14 ;;                                 {#- 4 -#}
    SET LR10 CR1 ;;
    ADD LR10 LR10 LR10 ;;
    ADD LR10 LR10 LR10 ;;
    ADD LR10 LR10 LR10 ;;
    ADD LR10 LR10 LR10 ;;
    ADD LR10 LR10 LR10 ;;
    ADD LR10 LR10 LR10 ;;
    ADD LR10 LR10 LR10 ;;                                 {#- 128: beta's element offset in Ra, the group cap -#}
    SET LR9 LR10 ;;
{% for _ in range(chunks - 1) %}
    ADD LR9 LR9 LR10 ;;                                   {#- 128 * {{ chunks }}: the group stride -#}
{% endfor %}
    LD.MASK LR0 {{ cr.maskr }} ;;                         {#- every lane of every multiply active -#}

{% if groups_full %}
    SET LR8 {{ cr.gb }}.L ; SET LR6 CR0 ;;                {#- the full groups: 128 rows each -#}
group_loop:
{{ group("f", dall) }}
    SUB LR8 LR8 LR7 ;;                                    {#- the rows left: minus rows_rem (= LR7 + 1) -#}
    DEC LR8 1 ;;
    ADD LR6 LR6 LR9 ;;                                    {#- the next group of rows -#}
    BNE LR8 CR0 group_loop ;;
{% endif %}
{% if rows_tail %}
    SET LR8 {{ cr.gb }}.H ; SET LR6 {{ cr.gt }}.L ;;      {#- the short last group, its own A-row DS -#}
{{ group("t", cr.gt ~ ".H") }}
{% endif %}
end:
    HALT ;;
