{#- binary_div_row.asm -- y = a / b elementwise, b broadcast as a ROW:
    y[i] = a[i] / b[i mod inner].

    Layout (kernel.toml's [abi]; every operand is a ROW number, one row = 128
    lanes): a and y are ceil(numel/128) rows each, row i holding elements
    128i .. 128i+127, lanes past numel zero. b is stored TILED by pack.py:
    ceil(inner/128) rows, row j lane l holding b[(128j + l) mod inner] -- the
    lane the semantics names, so a's row r combines with b's row
    (r mod b_rows) with no lane rotation; `inner` is a power of two, so
    inner | 128 * b_rows and the repetition is exact. This program renders
    inner <= 128 (one b row), so b's row is one of the R registers and never
    rotates.

    Dataflow. The only way into R_ACC is a multiply result and the only route
    from R_ACC back into a multiply is a store and a load (an NX8 row round
    trip), so 1/b is split once, before the row loop:

        r = AaQ reciprocal of b,   u = 2 - b*r,   e = r*u - r

    with r and e resident in R1 and R0 for the whole call and the row loop a
    y = a*r + a*e. The split is exact Newton for the *resident* r: with
    eps = b*r - 1 (whatever r's own quantization did), r + e = r*(2 - b*r)
    = (1/b)(1 - eps^2), so r's store costs nothing.
    |eps| <= b * (one step of r's row), e is at most a few percent of r, so
    e's own row is TIGHT: its scale is max|r*(1-b*r)|, ~b*r*eps < 0.06 of its
    lane's magnitude, and its store therefore costs ~2^-8 relative instead of
    the ~2^-5 a full-magnitude s = r*u row would. The subtraction needs an
    exact 2s row: a scratch row of 2.0 (a power of two, held exactly) in
    R_CYCLIC's second slot; r comes back out of the multiplier via
    MULT.VE of resident R1 by the CR constant 1.0, so no 1s row is loaded.

    The row loop is then two words per a row: word A multiplies the a row
    resident in R_CYCLIC's first slot by r and initialises the accumulator
    (ACC.ADD.FIRST), word B multiplies the same a row by e, adds it
    (ACC.ADD) and stores the row; word B also loads the NEXT a row (MULT
    reads R_CYCLIC at cycle start, LOAD writes after -- rule 2) and carries
    the branch. The last row of a call is short and is emitted straight-line
    with its own DS half; the row before it is emitted straight-line too,
    which keeps the one-row-ahead load inside the region (nothing ever loads
    row `rows`).

    LR: LR0 0 (R_CYCLIC slot 0); LR1 the a row pointer; LR2 the y row being
    stored (ADD from LR1 in the store's own word: the AAQ reads LRs after the
    word's LR writes, rule 1); LR4 the row loop's bound; LR7 128 (cyclic slot
    1, and R1's element offset in Ra for the MULT.VE); LR8 the b row pointer
    (0: one b row). The program sets every LR it reads and loads its own mask
    row, so it runs after another kernel as well as from reset.
-#}
{% set rows = (numel + 127) // 128 %}
{% set tail = numel - 128 * (rows - 1) %}
{% set hastrail = tail != 128 %}
{% set main = rows - (1 if hastrail else 0) %}
{% set dsf = cr.ds ~ ".L" %}
{% set dsl = cr.ds ~ (".H" if hastrail else ".L") %}
{% set qfl = cr.qf ~ ".L" %}
{#- The two-word body: word A multiplies the a row in cyclic slot 0 by the
    resident r (R1) and initialises R_ACC; word B multiplies the same a row
    by the resident e (R0), accumulates and stores the row, loads the next a
    row and branches. ADD keeps LR2 equal to the row the word multiplies
    (LR1 before its INC), so the store names this row. The branch reads LR1
    after the INC, so the bound is the last index that still loops. -#}
{% macro rowword(dsx, load_a, branch) -%}
    MULT.RC.VV LR0 R1 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD.FIRST ;;
    ADD LR2 LR1 CR0 ; INC LR1 1{% if load_a %} ;
    LD.MULT.CYCLIC LR1 {{ cr.a }} LR0{% endif %} ;
    MULT.RC.VV LR0 R0 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.y }} LR2{% if branch %} ;
    BLT.S LR1 LR4 row_loop{% endif %} ;;
{%- endmacro %}

    SET LR0 CR0 ; SET LR7 {{ cr.slot1 }} ;;                {#- 0; cyclic slot 1 -#}
    SET LR1 CR0 ; SET LR2 CR0 ;;                           {#- the a pointer; the store row -#}
    SET LR8 CR0 ;;                                         {#- the b row pointer: one b row -#}
    LD.MASK LR0 {{ cr.maskr }} ;;                          {#- every lane of every multiply active -#}
    LD.MULT.CYCLIC LR0 {{ cr.twos }} LR7 ;;                {#- cyclic[128..255] <- the 2s row -#}
{% if rows >= 2 %}
    SET LR4 {{ cr.bound }} ;;                              {#- the last index that still loops -#}
{% endif %}
    LD.MULT R0 LR8 {{ cr.b }} ;;                           {#- R0 <- the b row -#}
    MULT.VE LR0 CR1 0 LR0 {{ dsf }} {{ qfl }} ;            {#- the b row, broadcast -#}
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE reciprocal {{ dsf }} {{ qfl }} {{ cr.rcp }} LR8 ;;  {#- rcp <- 1/b -#}
    LD.MULT R1 LR8 {{ cr.rcp }} ;;                         {#- R1 <- r -#}
    LD.MULT.CYCLIC LR8 {{ cr.b }} LR0 ;;                   {#- cyclic slot 0 <- the b row -#}
    MULT.RC.VE LR7 CR1 0 LR0 {{ dsf }} {{ qfl }} ;         {#- the 2s row -#}
    ACC.ADD.FIRST ;;                                       {#- R_ACC <- 2 -#}
    MULT.RC.VV LR0 R1 0 LR0 {{ dsf }} {{ qfl }} ;          {#- b*r -#}
    ACC.SUB ;
    ACTIVATE.QUANTIZE identity {{ dsf }} {{ qfl }} {{ cr.u }} LR0 ;;      {#- u <- 2 - b*r -#}
    LD.MULT.CYCLIC LR0 {{ cr.u }} LR0 ;;                   {#- cyclic slot 0 <- u -#}
    MULT.RC.VV LR0 R1 0 LR0 {{ dsf }} {{ qfl }} ;          {#- r*u -#}
    ACC.ADD.FIRST ;;                                       {#- R_ACC <- r*u -#}
    MULT.VE LR7 CR1 0 LR0 {{ dsf }} {{ qfl }} ;            {#- r (R1) by the constant 1 -#}
    ACC.SUB ;
    ACTIVATE.QUANTIZE identity {{ dsf }} {{ qfl }} {{ cr.e }} LR8 ;;      {#- e <- r*u - r -#}
    LD.MULT R0 LR8 {{ cr.e }} ;;                           {#- R0 <- e -#}
    LD.MULT.CYCLIC LR1 {{ cr.a }} LR0 ;;                   {#- prime: a[0] -> cyclic[0..127] -#}
{% if main >= 2 %}
row_loop:
{{ rowword(dsf, true, true) }}                             {#- the full rows -#}
{% endif %}
{% if main >= 1 %}
{{ rowword(dsf, hastrail, false) }}                        {#- the last full row (it loads the short one) -#}
{% endif %}
{% if hastrail %}
{{ rowword(dsl, false, false) }}                           {#- the short last row, its own DS -#}
{% endif %}
end:
    HALT ;;
