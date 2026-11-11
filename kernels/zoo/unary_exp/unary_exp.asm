{#- unary_exp.asm -- y = exp(x) elementwise over numel elements in 128-lane rows,
    ONE parameterised program for every numel: the rows are a dynamic loop whose
    bound is a CR, so a whole call is one launch and the host tiles nothing but
    numel. x and y are the plain activation layout (row r holds lanes 128r ..
    128r+127, lanes past numel zero), so this kernel reads the rows the previous
    kernel wrote and writes the rows the next one reads, with no repack between.

    Hardware-clean NX8: formats = ["dynamic"], every store is an ACTIVATE.QUANTIZE
    and no emulator-only instruction appears.

    The AaQ's exp2 rejects a positive argument, so exp(x) is never exp2 of x
    directly: the argument is shifted down by the range's upper bound, and the
    shift is paid back with exact dyadic MULT constants,

        exp(x) = exp2(x log2 e - 8 log2 e) * exp(8)
               = exp2((x - 8) log2 e) * exp(8)

    whose argument is <= 0 in every lane for x <= 8 (the declared range; x = 8
    gives exactly 0). log2 e enters as the sum of two dyadic MULT constants (an
    NX8 MULT constant holds 7 significant bits; one alone would move the
    exponent argument), and the constant -8 log2 e enters as two MULT.EE of the
    ones row's element 0 -- the row is the program's own exp2(0) store, the
    host prepares no constant -- because a MULT product is R_CYCLIC or Ra times
    a constant, and a term that must not scale with x has to come from Ra.

      p1  e = exp2((x - 8) log2 e)   4 words/row: x*c1 (ACC.ADD.FIRST), x*c2,
                                     1*o1, then 1*o2 with the exp2 store in the
                                     same word; x's next row loads there too.
      p2  y = e * exp(8)             3 words/row: e*d1 (ACC.ADD.FIRST), then
                                     e*d2 with ACC.ADD and the identity store;
                                     e's next row loads in that word.

    7 words per row, 6 of them multiplying. exp(8) = 2976 + 4.9375 (rel error
    7e-6, far inside one NX8 step of the output row); log2 e = 1.4375 +
    0.00518798828125 and 8 log2 e its negation times 8, so the argument is
    exactly (x - 8) * (c1 + c2) and the only errors are the 7e-6 truncation of
    log2 e (a relative error of 8e-5 on y at worst) and the two 8-bit row round
    trips (e and the output store).

    The last row of a call is usually short (numel - 128*(rows-1) lanes). Every
    store names exactly those lanes with the DS half, so the row's scale comes
    from its live lanes and the lanes past numel are written 0. The loop
    therefore runs the full rows only; the last full row is emitted straight-line
    (it carries the one-row-ahead prefetch of the short row) and the short row
    is emitted straight-line with its own DS, which also keeps every prefetch
    inside the regions -- nothing ever loads row `rows`.

    Timing contract (docs/content/explanation/timing-model.md): LOAD reads the
    LRs *after* the same word's LR writes, so a walk is INC'd in its own load
    word and names the next row; MULT reads R0/R_CYCLIC as the word began, so
    every load is at least one word ahead of the multiply that consumes it;
    ACTIVATE.QUANTIZE reads the R_ACC the ACC stage last wrote (its own word's,
    or the previous word's when the word has no ACC slot); the LR sub-slots and
    the branch read cycle-start values, so the branch reads the counter before
    its DEC and the bound is trips - 1. No word writes one LR twice and no word
    holds two loads. LR0 is zeroed before anything reads it, R_MASK is loaded
    from its own all-ones row, every accumulation is seeded with a .FIRST form,
    and each pass's prologue primes every register its MULTs read, so the
    program runs after another kernel as well as from reset.

    LR: LR0 0 (the cyclic index and the mask shift); LR2 the trip counter; LR6
    the source row walk; LR7 the store row walk. R0 holds the ones row for the
    MULT.EE constants of p1.
-#}
{% set qfl = cr.qf ~ ".L" %}
{% set rows = (numel + 127) // 128 %}
{% set tail = numel - 128 * (rows - 1) %}
{% set hastrail = tail != 128 %}
{% set main = rows - (1 if hastrail else 0) %}
{% set dsf = cr.ds ~ ".L" %}
{% set dsl = cr.ds ~ (".H" if hastrail else ".L") %}
{#- ---- p1: e = exp2((x - 8) log2 e), the exp2 store rides the last multiply -- -#}
{% macro P1(label, dsx, loads, branch) -%}
{% if branch %}{{ label }}:
{% endif %}
    INC LR7 1 ;
    MULT.RC.VE LR0 {{ cr.c1 }} 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 {{ cr.c2 }} 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD ;;
    MULT.EE LR0 {{ cr.o1 }} 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD ;;
    MULT.EE LR0 {{ cr.o2 }} 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD ;
    ACTIVATE.QUANTIZE exp2 {{ dsx }} {{ qfl }} {{ cr.e }} LR7{% if loads %} ;
    INC LR6 1 ;
    LD.MULT.CYCLIC LR6 {{ cr.x }} LR0{% endif %}{% if branch %} ;
    DEC LR2 1 ;
    BLT.S CR0 LR2 {{ label }} ;;{% else %} ;;{% endif %}
{%- endmacro %}
{#- ---- p2: y = e * exp(8), the identity store rides the last multiply -------- -#}
{% macro P2(label, dsx, loads, branch) -%}
{% if branch %}{{ label }}:
{% endif %}
    INC LR7 1 ;
    MULT.RC.VE LR0 {{ cr.d1 }} 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 {{ cr.d2 }} 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.y }} LR7{% if loads %} ;
    INC LR6 1 ;
    LD.MULT.CYCLIC LR6 {{ cr.e }} LR0{% endif %}{% if branch %} ;
    DEC LR2 1 ;
    BLT.S CR0 LR2 {{ label }} ;;{% else %} ;;{% endif %}
{%- endmacro %}
{#- The ones row: 0 * x exp2-stored, one trip, before anything reads Ra. ------- -#}
    SET LR0 CR0 ; LD.MASK LR0 {{ cr.maskr }} ;;   {#- 0: cyclic index, mask shift -#}
    SET LR6 CR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.x }} LR0 ;;          {#- x row 0 -> slot 0 -#}
    MULT.RC.VE LR0 CR0 0 LR0 {{ dsf }} {{ qfl }} ; {#- 0 * x: every lane 0 -#}
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE exp2 {{ dsf }} {{ qfl }} {{ cr.one }} LR6 ;;
    LD.MULT R0 LR0 {{ cr.one }} ;;                {#- the ones row -> R0 -#}
{#- ==================== p1: e = exp2((x - 8) log2 e) =========================== -#}
    SET LR2 {{ cr.bound }} ; SET LR6 CR0 ; SUB LR7 LR0 CR1 ;;
    LD.MULT.CYCLIC LR0 {{ cr.x }} LR0 ;;          {#- prime: x[0] -> slot 0 -#}
{% if main >= 2 %}
{{ P1("p1", dsf, true, true) }}
{% endif %}
{% if main >= 1 %}
{{ P1("p1", dsf, hastrail, false) }}
{% endif %}
{% if hastrail %}
{{ P1("p1t", dsl, false, false) }}
{% endif %}
{#- ======================== p2: y = e * exp(8) ================================= -#}
    SET LR2 {{ cr.bound }} ; SET LR6 CR0 ; SUB LR7 LR0 CR1 ;;
    LD.MULT.CYCLIC LR0 {{ cr.e }} LR0 ;;          {#- prime: e[0] -> slot 0 -#}
{% if main >= 2 %}
{{ P2("p2", dsf, true, true) }}
{% endif %}
{% if main >= 1 %}
{{ P2("p2", dsf, hastrail, false) }}
{% endif %}
{% if hastrail %}
{{ P2("p2t", dsl, false, false) }}
{% endif %}
end:
    HALT ;;
