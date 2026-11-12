{#- binary_div_col.asm -- y = a / b, broadcast = col: y[r][j] = a[r][j] / b[r].

    Layout (kernel.toml's [abi]; every operand is a ROW number, one row = 128
    lanes): a and y are [inner, numel / inner] -- an entity (a row of a) is
    one memory row, its numel / inner features in lanes 0..rowlen-1, lanes
    past that zero -- the layout every activation on the chip uses. b holds
    `inner` values, one per row of a, packed ceil(inner / 128) rows.

    Dataflow. A division is a multiply by an exact reciprocal; the only way
    into R_ACC is MULT_RES and the only route from R_ACC back into a multiply
    is a store and a load, so 1/b is split ONCE PER B ROW, before that run's
    rows of a -- exactly binary_div_row's prologue, applied to the run's b
    row (loaded into R0):

        r = AaQ reciprocal of b,   u = 2 - b*r,   e = r*u - r

    with r resident in R1 and e in R0 for the run, and then each row of a is
    y = a*r + a*e, TWO words per row -- word A multiplies the a row resident
    in R_CYCLIC slot 128 by the scalar r (element LR5 = LR3 + 128 of R1,
    selected by the lane counter LR3); word B multiplies the SAME row by the
    scalar e (element LR3 of R0), accumulates (ACC.ADD), stores it and loads
    the NEXT a row into slot 128 (the load retires after word B's MULT has
    read the slot, and word A of the next row multiplies it), so nothing
    waits.
    The split is exact Newton for the RESIDENT r: with eps = b*r - 1,
    r + e = (1/b)(1 - eps^2), so r's own store costs nothing, and e's row is
    tight: e's scale is max|r*(1-b*r)|, ~b*(one step of r's row) -- a few
    percent of a lane's magnitude -- so e's store costs ~2^-8 instead of the
    ~2^-5 a full-magnitude s = r*u row would. The subtraction for u needs an
    exact 2s row, resident in R_CYCLIC slot 256; r comes back out of the
    multiplier via MULT.VE of resident R1 by the CR constant 1.0, and the b
    row into the multiplier via slot 0.

    The rows of a are grouped in RUNS of 128 (the lanes of one b row): each
    run opens with the prologue (12 words) and the run loop branches on LR3
    (the run's lane counter, starting -1) against the bound, the run loop on
    LR4 against CRgf (the number of full runs). The last row of the whole
    call is emitted straight-line -- nothing ever loads row `inner` -- and
    the last run's prologue names only `tail` live lanes (its DS half), so
    b's padding lanes never reach the reciprocal.

    Timing contract: Control (LR writes, branch) reads LRs at cycle start;
    LOAD/MULT/ACC/AAQ read them after the same word's LR writes. So the
    counters: LR1 is the a row pointer, INC'd in the word whose LOAD uses
    the new value; LR2 (the row being stored) is SUB'd from LR1 in word B,
    read at cycle start; LR3/LR5 (the scalar lane and its +128 image) INC in
    word A and are read forwarded by the same word's MULT; the run loops
    branch on LR3 against the bound LR10 and the run loop on LR4 (BLT.S
    against CRgf). Every LR the program sets is set by it and the mask row
    is its own, so it runs after another kernel as well as from reset.
-#}
{% set rowlen = numel // inner %}
{% set gf = ((inner + 127) // 128) - 1 %}
{% set tail = inner - 128 * gf %}
{% set dsr = cr.dsr ~ ".L" %}
{% set dsf = cr.dsf ~ ".L" %}
{% set dst = cr.dsf ~ ".H" %}
{% set qfl = cr.qf ~ ".L" %}
{% macro prologue(h) -%}
    SUB LR3 LR0 CR1 ;;                                    {#- the lane counter -1 -#}
    SUB LR5 LR3 CR1 ; INC LR4 1 ;;                        {#- the R1 scalar index, one behind -#}
    INC LR5 129 ; INC LR8 1 ;;                            {#- LR5 <- 127: after the body's INC it is LR3 + 128 -#}
    LD.MULT R0 LR8 {{ cr.b }} ;;                          {#- the b row (its own word: MULT reads R0 at cycle start) -#}
    MULT.VE LR0 CR1 0 LR0 {{ h }} {{ qfl }} ;             {#- the b row, broadcast -#}
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE reciprocal {{ h }} {{ qfl }} {{ cr.rcp }} LR6 ;; {#- rcp <- 1/b -#}
    LD.MULT R1 LR6 {{ cr.rcp }} ;;
    LD.MULT R1 LR6 {{ cr.rcp }} ;;
    LD.MULT.CYCLIC LR8 {{ cr.b }} LR0 ;;
    MULT.RC.VE LR9 CR1 0 LR0 {{ h }} {{ qfl }} ;          {#- the 2s row -#}
    ACC.ADD.FIRST ;;                                      {#- R_ACC <- 2 -#}
    MULT.RC.VV LR0 R1 0 LR0 {{ h }} {{ qfl }} ;           {#- b*r -#}
    ACC.SUB ;
    ACTIVATE.QUANTIZE identity {{ h }} {{ qfl }} {{ cr.u }} LR6 ;; {#- u <- 2 - b*r -#}
    LD.MULT.CYCLIC LR6 {{ cr.u }} LR0 ;;                  {#- cyclic slot 0 <- u -#}
    MULT.RC.VV LR0 R1 0 LR0 {{ h }} {{ qfl }} ;           {#- r*u -#}
    ACC.ADD.FIRST ;;                                      {#- R_ACC <- r*u -#}
    MULT.VE LR7 CR1 0 LR0 {{ h }} {{ qfl }} ;             {#- r (R1) by the constant 1 -#}
    ACC.SUB ;
    ACTIVATE.QUANTIZE identity {{ h }} {{ qfl }} {{ cr.e }} LR6 ;; {#- e <- r*u - r -#}
    LD.MULT R0 LR6 {{ cr.e }} ;;
{%- endmacro %}
{#- The two-word row body: word A multiplies the resident a row by the run's
    r (R1, element LR5 = LR3 + 128) and initialises R_ACC; word B multiplies
    the SAME row by e (R0, element LR3), accumulates, stores row LR1 (read at
    cycle start, before its own INC) and loads the NEXT a row into slot 128:
    the load retires after this word's MULT has read the slot, and the next
    word A multiplies it. The loop branch reads LR3 at cycle start. -#}
{% macro body_a(loop) -%}
    INC LR3 1 ; INC LR5 1 ;
    MULT.RC.VE LR7 LR5 0 LR0 {{ dsr }} {{ qfl }} ;
    ACC.ADD.FIRST ;;
    INC LR1 1 ;
    LD.MULT.CYCLIC LR1 {{ cr.a }} LR7 ;
    ADD LR2 LR1 CR0 ;
    MULT.RC.VE LR7 LR3 0 LR0 {{ dsr }} {{ qfl }} ;
    ACC.ADD ;
    ACTIVATE.QUANTIZE identity {{ dsr }} {{ qfl }} {{ cr.y }} LR2 ;
    BNE LR3 LR10 {{ loop }} ;;
{%- endmacro %}
{% macro last_row() -%}
    INC LR3 1 ; INC LR5 1 ;
    MULT.RC.VE LR7 LR5 0 LR0 {{ dsr }} {{ qfl }} ;
    ACC.ADD.FIRST ;;
    ADD LR2 LR1 CR0 ;
    MULT.RC.VE LR7 LR3 0 LR0 {{ dsr }} {{ qfl }} ;
    ACC.ADD ;
    ACTIVATE.QUANTIZE identity {{ dsr }} {{ qfl }} {{ cr.y }} LR2 ;;
{%- endmacro %}
    SET LR0 CR0 ; SET LR6 CR0 ;;                          {#- 0; scratch store offset -#}
    SET LR7 CR0 ; SET LR9 CR0 ;;                          {#- slot bases -#}
    INC LR7 128 ; INC LR9 128 ;;                          {#- the a rows' slot; the 2s row's slot -#}
    INC LR9 128 ; SUB LR8 LR0 CR1 ;;                      {#- ... slot 256 in two INCs; the b row pointer -1 -#}
    SET LR1 CR0 ; SET LR4 CR0 ; SET LR10 {{ cr.f127 }} ;; {#- the a row pointer; the run counter; the bound -#}
    LD.MASK LR0 {{ cr.maskr }} ;;                         {#- every lane of every multiply active -#}
    LD.MULT.CYCLIC LR0 {{ cr.twos }} LR9 ;;               {#- slot 256 <- the 2s row -#}
    LD.MULT.CYCLIC LR1 {{ cr.a }} LR7 ;;                  {#- prime: a[0] -> slot 128 -#}
{% if gf >= 1 %}
outer_loop:
{{ prologue(dsf) }}
full_loop:
{{ body_a("full_loop") }}
{% if gf >= 2 %}
    BLT.S LR4 {{ cr.gf }} outer_loop ;;                   {#- another full run of 128 rows -#}
{% endif %}
    SET LR10 {{ cr.tm2 }} ;;                              {#- the short run's bound -#}
{% else %}
    SET LR10 {{ cr.tm2 }} ;;
{% endif %}
{{ prologue(dst) }}                                       {#- the last run's r and e -#}
{% if tail >= 2 %}
tail_loop:
{{ body_a("tail_loop") }}
{% endif %}
{{ last_row() }}
end:
    HALT ;;
