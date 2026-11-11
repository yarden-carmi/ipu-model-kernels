{#- row_norm_rmsnorm.asm -- RMSNorm over `channels`, one parameterised
    program for every (rows, channels).

        y[r, j] = x[r, j] * A_r * gamma[j]
        A_r     = rsqrt(max(mean_j x[r,j]^2, eps))

    The rmsnorm half of the row_norm family (the layernorm program is
    ../row_norm_layernorm): no mean, no variance and no beta, so the
    normalisation is the group's squares reduction, one straight-line rsqrt
    word, and one multiply per (row, chunk) in each of the p and y passes --
    three words per (row, chunk) in all.

    Layout (kernel.toml's [abi]; every operand is a ROW number, one row = 128
    lanes): entity r owns ceil(channels / 128) = chunks consecutive rows, row
    r * chunks + c holding channels 128c .. 128c + 127, lanes past `channels`
    zero -- the layout every activation on the chip uses, so y is the next
    kernel's x. gamma is `chunks` rows, kept as prepared; `sca` is the group's
    two bookkeeping rows (the squares, then A); `p` is the kernel's one matrix
    of scratch; invn, epsr and maskr are constant rows.

    Work is per group of up to 128 rows: the R_ACC lanes are the bookkeeping,
    one lane per row of the group, which is what bounds a group at 128 rows.
    Passes: the squares reduction at one word per (row, chunk)
    (MULT.RC.VS + AGG.SUM into the row's lane, the next row's load riding in
    the same word), A = rsqrt(max(squares * 1/channels, eps)) straight-line
    with the hardware rsqrt of ACTIVATE.QUANTIZE floored by ACC.MAX, then
    p = A_r * x (A_r read out of the group's A row as an element-selected
    scalar) and y = p * gamma, each one word per (row, chunk).

    Timing contract: the Control stage (LR writes and the branch) reads LRs at
    cycle start, the LOAD/MULT/ACC/AAQ stages read them after the same word's
    LR writes (forwarded), and MULT reads R0/R1/R_CYCLIC as the word began. So
    a row loop keeps its counter one behind (LR2 starts at -1 and the word that
    multiplies row i is the word that INCs it: its MULT, AGG and AAQ see i, its
    branch i - 1) and prefetches the next row with the pointer it just
    advanced. Two LR sub-slots never write one register in one word (fault
    F-3), which is why a counter is seeded and stepped in separate slots or
    words.

    An NX8 row is a block format: one scale for the row, taken from its largest
    ACTIVE element. So every lane a store writes must be within a few factors
    of every other one. That bounds a group at 128 rows *and* decides the
    render: `rows` is known when the program is assembled, so the full groups
    (always exactly 128 rows) are emitted once as a dynamic loop and the short
    last group, if there is one, is emitted a second time with its own DS half
    (ds(rows % 128), CR12) for the row of A -- a group's bookkeeping lanes past
    its last row would otherwise hold rsqrt(eps) = 316 against real A of ~2 and
    flush every real A of the row to zero. The group's first row is built at
    run time (LR6 += the group stride, once per group) instead of being read
    from a CR half: rows up to 32768 with several chunks would not fit the
    16 bits a CR half takes.

    Wide channels: `channels` past 512 is five chunks or more, and the 1..4
    constants (LR11..LR14) can no longer double as the per-row chunk stride.
    Then LR14 holds the stride itself (the chunk count, seeded by repeated ADD
    of LR11 in the prologue) and LR15 walks the chunk offsets: set to 0 before
    each pass's chunk loop, incremented once per chunk. Up to four chunks the
    constants 1..4 play both roles, as before, and LR15 stays untouched.

    LR: LR0 0; LR1 the row being read (its cycle-start value is the row the
    word multiplies, its forwarded value the row the word loads); LR2 the
    group-relative row index; LR3 the loop bound (rows_rem - 2); LR4 the p or
    y row being stored; LR6 the group's first row; LR7 the group's rows_rem;
    LR8 the groups left in the full-group loop; LR9 128 * chunks (the group
    stride); LR10 128 (the group cap); LR11..LR13 the constants 1..3, which
    are also the `sca` row numbers (squares LR11, A LR12); LR14 the constant
    4, or (past four chunks) the chunk stride; LR15 (past four chunks) the
    chunk-offset walker. The program sets every LR it reads, zeroes R_ACC
    before each reduction and loads its own mask row, so it runs after another
    kernel as well as from reset.
-#}
{% set chunks = (channels + 127) // 128 %}
{% set tail = channels - 128 * (chunks - 1) %}
{% set rows_tail = rows % 128 %}
{% set groups_full = rows // 128 %}
{% set dall = cr.ds ~ ".L" %}
{% set dlast = cr.ds ~ (".H" if tail != 128 else ".L") %}
{% set qfl = cr.qf ~ ".L" %}
{% set tails = cr.tails ~ ".L" %}
{% set wide = chunks > 4 %}
{% set coff = ["LR0", "LR11", "LR12", "LR13"] %}
{% set cstr = ["LR0", "LR11", "LR12", "LR13", "LR14"] %}
{% set stride = "LR14" if wide else cstr[chunks] %}
{% macro chunkoff(c) -%}{{ "LR15" if wide else coff[c] }}{%- endmacro %}
{% macro dsof(c) -%}{{ dlast if c == chunks - 1 else dall }}{%- endmacro %}
{% macro zero() -%}
    LD.MULT R0 LR0 {{ cr.invn }} ;;                       {#- a finite row to multiply by 0.0 -#}
    MULT.VE LR0 CR0 0 LR0 {{ dall }} {{ qfl }} ;
    ACC.ADD.FIRST ;;                                      {#- R_ACC := 0 in every lane (a group's unused rows) -#}
{%- endmacro %}
{% macro index() -%}
    SET LR2 CR0 ;;
    DEC LR2 1 ;;                                          {#- the row index, one behind: -1 -#}
{%- endmacro %}
{% macro redloop(label, c) -%}
    ADD LR1 LR6 {{ chunkoff(c) }} ;;                      {#- the group's row 0 of chunk {{ c }} -#}
    LD.MULT.CYCLIC LR1 {{ cr.x }} LR0 ;;                  {#- prime R_CYCLIC[0..127] with x[0, {{ c }}] -#}
{{ index() }}
{{ label }}{{ c }}:
    MULT.RC.VS LR0 0 LR0 {{ dall }} {{ qfl }} ;           {#- x^2; R0/R1 are not read -#}
    AGG.SUM LR2 {{ dall }} ;                              {#- into the row's bookkeeping lane -#}
    ADD LR1 LR1 {{ stride }} ; INC LR2 1 ;
    LD.MULT.CYCLIC LR1 {{ cr.x }} LR0 ;                   {#- the row the NEXT word reduces -#}
    BLT.S LR2 LR3 {{ label }}{{ c }} ;;
{%- endmacro %}
{% macro group(pfx, ds_a, rem) -%}
{{ rem }}                                               {#- the group's rows_rem -#}
    ADD LR3 LR7 CR0 ;;
    SUB LR3 LR3 CR1 ;;
    SUB LR3 LR3 CR1 ;;                                    {#- the one-word bound rows_rem - 2 -#}
{% if wide %}    SET LR15 CR0 ;;{% endif %}                             {#- the chunk-offset walker -#}
{% for c in range(chunks) %}
{% if c == 0 %}
{{ zero() }}
{% endif %}
{{ redloop(pfx ~ "sq", c) }}
{% if wide %}    INC LR15 1 ;;{% endif %}
{% endfor %}
    ACTIVATE.QUANTIZE identity {{ dall }} {{ qfl }} {{ cr.sca }} LR11 ;;  {#- sca[0] = the group's squares -#}

{#- -------- A = rsqrt(max(the mean of squares, eps)) ----------------------- -#}
    LD.MULT R0 LR0 {{ cr.invn }} ;;                       {#- R0 = 1/channels in every lane -#}
    LD.MULT.CYCLIC LR11 {{ cr.sca }} LR0 ;;               {#- the squares -#}
    MULT.RC.VV LR0 R0 0 LR0 {{ dall }} {{ qfl }} ;
    ACC.ADD.FIRST ;;                                      {#- R_ACC = the mean of squares -#}
    LD.MULT R0 LR0 {{ cr.epsr }} ;;                       {#- R0 = eps in every lane -#}
    MULT.EE LR0 CR1 0 LR0 {{ dall }} {{ qfl }} ;
    ACC.MAX ;                                             {#- floor it, so the rsqrt never sees a negative -#}
    ACTIVATE.QUANTIZE rsqrt {{ ds_a }} {{ qfl }} {{ cr.sca }} LR12 ;;   {#- sca[1] = A -#}

{#- -------- p = A_r * x ----------------------------------------------------- -#}
{% if wide %}    SET LR15 CR0 ;;{% endif %}
{% for c in range(chunks) %}
    ADD LR1 LR6 {{ chunkoff(c) }} ;;
    LD.MULT R0 LR12 {{ cr.sca }} ;;                       {#- R0 = the A row, resident for the pass -#}
    LD.MULT.CYCLIC LR1 {{ cr.x }} LR0 ;;                  {#- prime with x[0, {{ c }}] -#}
{{ index() }}
{{ pfx }}p{{ c }}:
    MULT.RC.VE LR0 LR2 0 LR0 {{ dall }} {{ qfl }} ;       {#- A_r * x[r, {{ c }}] -#}
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dsof(c) }} {{ qfl }} {{ cr.p }} LR4 ;
    ADD LR4 LR1 CR0 ; ADD LR1 LR1 {{ stride }} ; INC LR2 1 ;
    LD.MULT.CYCLIC LR1 {{ cr.x }} LR0 ;                   {#- the row the next word multiplies -#}
    BLT.S LR2 LR3 {{ pfx }}p{{ c }} ;;
{% if wide %}    INC LR15 1 ;;{% endif %}
{% endfor %}

{#- -------- y = p * gamma --------------------------------------------------- -#}
{% if wide %}    SET LR15 CR0 ;;{% endif %}
{% for c in range(chunks) %}
    ADD LR1 LR6 {{ chunkoff(c) }} ;;
    LD.MULT R0 {{ chunkoff(c) }} {{ cr.gamma }} ;;        {#- R0 = chunk {{ c }}'s gamma, resident -#}
    LD.MULT.CYCLIC LR1 {{ cr.p }} LR0 ;;                  {#- prime with p[0, {{ c }}] -#}
{{ index() }}
{{ pfx }}y{{ c }}:
    MULT.RC.VV LR0 R0 0 LR0 {{ dall }} {{ qfl }} ;        {#- p * gamma -#}
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dsof(c) }} {{ qfl }} {{ cr.y }} LR4 ;
    ADD LR4 LR1 CR0 ; ADD LR1 LR1 {{ stride }} ; INC LR2 1 ;
    LD.MULT.CYCLIC LR1 {{ cr.p }} LR0 ;                   {#- the row the next word multiplies -#}
    BLT.S LR2 LR3 {{ pfx }}y{{ c }} ;;
{% if wide %}    INC LR15 1 ;;{% endif %}
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
{% set fours = 4 if not wide else chunks %}
{% for _ in range(fours - 1) %}
    ADD LR14 LR14 LR11 ;;                                 {#- {{ fours }}: 4, or the chunk stride when wide -#}
{% endfor %}
    SET LR10 CR1 ;;
    ADD LR10 LR10 LR10 ;;
    ADD LR10 LR10 LR10 ;;
    ADD LR10 LR10 LR10 ;;
    ADD LR10 LR10 LR10 ;;
    ADD LR10 LR10 LR10 ;;
    ADD LR10 LR10 LR10 ;;
    ADD LR10 LR10 LR10 ;;                                 {#- 128: the group cap -#}
    SET LR9 LR10 ;;
{% for _ in range(chunks - 1) %}
    ADD LR9 LR9 LR10 ;;                                   {#- 128 * {{ chunks }}: the group stride -#}
{% endfor %}
    LD.MASK LR0 {{ cr.maskr }} ;;                         {#- every lane of every multiply active -#}
    SET LR6 CR0 ;;                                        {#- the first group's first row -#}

{% if groups_full %}
    SET LR8 {{ cr.g0 }}.L ;;                              {#- the full groups: 128 rows each -#}
group_loop:
{{ group("f", dall, "SET LR7 LR10 ;;") }}
    DEC LR8 1 ;;                                          {#- the groups left -#}
    ADD LR6 LR6 LR9 ;;                                    {#- the next group of rows -#}
    BNE LR8 CR0 group_loop ;;
{% endif %}
{% if rows_tail %}
{{ group("t", tails, "SET LR7 " ~ cr.g0 ~ ".H ;;") }}    {#- the short last group, its own A-row DS -#}
{% endif %}
end:
    HALT ;;
