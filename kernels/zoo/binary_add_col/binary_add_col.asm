{#- binary_add_col.asm -- y = a (op) b, broadcast = col, one parameterised
    program for every (op, numel, inner) of the kernel's domain.

    Layout (kernel.toml's [abi]; every operand is a ROW number, one row = 128
    lanes): a and y are [inner, numel / inner] -- an entity (a row of a) is
    one memory row, its numel / inner features in lanes 0..rowlen-1, lanes
    past that zero -- the layout every activation on the chip uses when an
    entity holds at most 128 features, so y is the next kernel's input. b
    holds `inner` values, one per row of a, packed ceil(inner / 128) rows.

    Dataflow, per row r: y[r] = a[r] (op) b[r], so the row needs TWO products
    (the only way into R_ACC is MULT_RES): word A multiplies the a row
    resident in R_CYCLIC slot 128 by the CR constant 1.0 and initialises the
    accumulator with it, word B broadcasts b[r] (MULT.RC.VE of the resident
    ones row in slot 0, the scalar element r % 128 of Ra = R0 selected by LR3)
    and accumulates it (ADD for add, SUB for sub, MAX for max) and stores the
    row. `mul` is ONE product -- the a row itself times b[r] -- so its whole
    row is one word. Word A carries the load of the row the next word A
    multiplies (MULT reads R_CYCLIC at cycle start, LOAD reads LRs after the
    same word's writes), so nothing waits on a load. b's row lives in R0 and
    is reloaded every 128 rows of a: the rows of a are grouped in runs of 128
    (the lanes of one b row), each run opened by a prologue word that loads
    the run's b row, and the scalar index LR3 doubles as the run's lane
    counter (it starts at -1 and counts the lanes 0..127 of the b row).

    Timing contract: the Control stage (LR writes, branch) reads LRs at cycle
    start; LOAD/MULT/ACC/AAQ read them after the same word's LR writes. Hence
    the counters: LR1 is the a row pointer, INC'd in the word whose LOAD uses
    the new value; LR2 (the row being stored) is ADDed from LR1 - 1 in word B
    or from LR1 in the one-word `mul` body, both read at cycle start; the run
    loops branch on LR3 (BNE against LR10, the run's trip bound) and the run
    loop on LR4 (BLT.S against CRgf, the number of full runs). The last row
    of the whole call is emitted straight-line -- nothing ever loads row
    `inner` -- and every row of a holds exactly `inner` lanes of DS, so there
    is no short DS anywhere: every row names rowlen live lanes.

    LR: LR0 0 (R_CYCLIC element index / mask shift); LR1 the a row pointer;
    LR2 the y row being stored; LR3 b's element index in R0, minus one (the
    run's lane counter); LR4 the run counter; LR7 the a rows' R_CYCLIC slot
    (128); LR8 the b row pointer (starts -1); LR10 the run loop's bound. The
    program sets every LR it reads and loads its own mask row, so it runs
    after another kernel as well as from reset.
-#}
{% set rowlen = numel // inner %}
{% set gf = ((inner + 127) // 128) - 1 %}
{% set tail = inner - 128 * gf %}
{% set dsx = cr.ds ~ ".L" %}
{% set qfl = cr.qf ~ ".L" %}
{% set A1 = {"add": "ACC.ADD.FIRST", "sub": "ACC.ADD.FIRST", "max": "ACC.MAX.FIRST"}[op] %}
{% set A2 = {"add": "ACC.ADD", "sub": "ACC.SUB", "max": "ACC.MAX"}[op] %}
{% macro prologue() -%}
    SUB LR3 LR0 CR1 ; INC LR4 1 ; INC LR8 1 ;
    LD.MULT R0 LR8 {{ cr.b }} ;;
{%- endmacro %}
{% macro body_a() -%}
    INC LR3 1 ; INC LR1 1 ;
    LD.MULT.CYCLIC LR1 {{ cr.a }} LR7 ;
    MULT.RC.VE LR7 CR1 0 LR0 {{ dsx }} {{ qfl }} ;
    {{ A1 }} ;;
    SUB LR2 LR1 CR1 ;
    MULT.RC.VE LR0 LR3 0 LR0 {{ dsx }} {{ qfl }} ;
    {{ A2 }} ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.y }} LR2 ;
{%- endmacro %}
{% macro body_mul() -%}
    ADD LR2 LR1 CR0 ; INC LR1 1 ; INC LR3 1 ;
    LD.MULT.CYCLIC LR1 {{ cr.a }} LR7 ;
    MULT.RC.VE LR7 LR3 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.y }} LR2 ;
{%- endmacro %}
{% macro last_row() -%}
{% if op == "mul" %}
    ADD LR2 LR1 CR0 ; INC LR3 1 ;
    MULT.RC.VE LR7 LR3 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.y }} LR2 ;;
{% else %}
    MULT.RC.VE LR7 CR1 0 LR0 {{ dsx }} {{ qfl }} ;     {#- the last row's a product -#}
    {{ A1 }} ;;
    ADD LR2 LR1 CR0 ; INC LR3 1 ;
    MULT.RC.VE LR0 LR3 0 LR0 {{ dsx }} {{ qfl }} ;
    {{ A2 }} ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.y }} LR2 ;;
{% endif %}
{%- endmacro %}

    SET LR0 CR0 ; SET LR7 {{ cr.slot128 }} ;;             {#- 0; a's cyclic slot -#}
    SET LR1 CR0 ; SUB LR8 LR0 CR1 ;;                      {#- the a row pointer; the b row pointer -1 -#}
    SET LR4 CR0 ; SET LR10 {{ cr.f127 if op != "mul" else cr.f126 }} ;;  {#- the run counter; the full run's bound (mul: BNE reads the old LR3) -#}
    LD.MASK LR0 {{ cr.maskr }} ;;                         {#- every lane of every multiply active -#}
{% if op != "mul" %}
    LD.MULT.CYCLIC LR0 {{ cr.ones }} LR0 ;;               {#- the ones row -> R_CYCLIC slot 0 -#}
{% endif %}
    LD.MULT.CYCLIC LR1 {{ cr.a }} LR7 ;;                  {#- prime: a[0] -> R_CYCLIC slot 128 -#}
{% if gf >= 1 %}
outer_loop:
{{ prologue() }}
full_loop:
{% if op == "mul" %}
{{ body_mul() }}                                          {#- one word per row -#}
    BNE LR3 LR10 full_loop ;;
{% else %}
{{ body_a() }}                                            {#- two words per row -#}
    BNE LR3 LR10 full_loop ;;
{% endif %}
    BLT.S LR4 {{ cr.gf }} outer_loop ;;                   {#- another full run of 128 rows -#}
    SET LR10 {{ cr.tm2 if op != "mul" else cr.tm3 }} ;;   {#- the short run's bound -#}
{% else %}
    SET LR10 {{ cr.tm2 if op != "mul" else cr.tm3 }} ;;
{% endif %}
{{ prologue() }}                                          {#- the last run's b row -#}
{% if tail >= 2 %}
tail_loop:
{% if op == "mul" %}
{{ body_mul() }}
    BNE LR3 LR10 tail_loop ;;
{% else %}
{{ body_a() }}
    BNE LR3 LR10 tail_loop ;;
{% endif %}
{% endif %}
{{ last_row() }}
end:
    HALT ;;
