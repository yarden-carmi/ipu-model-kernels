{#- unary_gelu.asm -- y = gelu(x) elementwise over numel elements in 128-lane
    rows, ONE parameterised program for every numel: the rows are a dynamic loop
    whose bound is a CR, so a whole call is one launch (3072 rows for the
    393216-element call) and the host tiles nothing but numel.

    x and y are the plain activation layout (row r holds lanes 128r .. 128r+127,
    lanes past numel zero), so this kernel reads the rows the previous kernel
    wrote and writes the rows the next one reads, with no repack between them.
    gelu(0) = 0, so a zero-padded input row keeps a zero-padded output row.

    Hardware-clean NX8: formats = ["dynamic"], every store is an
    ACTIVATE.QUANTIZE (identity, exp2 or reciprocal) and no emulator-only
    instruction appears. The AaQ activates the forwarded R_ACC into memory, so a
    value that has to become a multiplicand leaves and comes back as an NX8 row;
    the passes below are exactly those round trips.

    gelu is x * sigmoid(z), z = c (x + 0.044715 x^3), c = 2 sqrt(2/pi) -- the
    tanh form, whose deviation from the erf form is at most ~3.4e-4 absolute
    (kind estimation). The sigmoid goes through -|z| (exp2 of a positive input
    is an AaQ error) and the two signed branches are joined with one ACC.MAX:

      s = x^2        one MULT.RC.VS of the x row (ACC.ADD.FIRST).
      m = lc + ld s  the exp2 argument per unit |x|: lc = -log2(e) c and
                     ld = -log2(e) c 0.044715, each the sum of two dyadic MULT
                     constants (an NX8 MULT constant holds 7 significant bits;
                     one alone would move every exp2 argument). The ld terms are
                     two MULT.RC.VE of the s row, the lc terms two MULT.EE of the
                     ones row's element 0 -- the row is the program's own exp2(0)
                     store, the host prepares no constant.
      t = |x|        ACC.SUB.FIRST of x*1.0, then ACC.MAX: max(-x, x).
      e = exp2(t m)  the product is one MULT.RC.VV of t against m held in Ra,
                     and the SAME word's ACTIVATE.QUANTIZE exp2 stores it: the
                     argument is <= 0 in every lane (m < 0, t >= 0).
      q = 1/(1+e)    e*1.0, then the ones row broadcast by MULT.EE, AaQ
                     reciprocal, stored into t's rows -- t is spent.
      w = e q        one MULT.RC.VV of e's row against q's row in Ra, identity
                     store into e's rows -- e is spent too.
      y = max(x q,
              x w)   for x >= 0 the larger product is x q (q >= 1/2 >= w); for
                     x < 0 both products are negative and the smaller magnitude,
                     x w = x e/(1+e) = x sigmoid(z), wins. No compare and no
                     sign test exists in the program.

    Two row registers serve all four intermediates: the s rows hold x^2, then m,
    then e, then w; the t rows hold |x|, then q. A call takes 4*rows + 2 XMEM
    rows, hence the numel maximum of 524160 (4095 rows).

    Timing contract (docs/content/explanation/timing-model.md): LOAD reads the
    LRs *after* the same word's LR writes, so a walk is INC'd in its own load
    word and names the next row; MULT reads R0/R1/R_CYCLIC as the word began, so
    every load is at least one word ahead of the multiply that consumes it;
    ACTIVATE.QUANTIZE reads the R_ACC the ACC stage last wrote (its own word's,
    or the previous word's when the word has no ACC slot, as in y's third word);
    the LR sub-slots and the branch read cycle-start values, so the branch reads
    the counter before its DEC and the bound is trips - 1. No word writes one LR
    twice and no word holds two loads. LR0 is zeroed before anything reads it,
    R_MASK is loaded from its own all-ones row, every accumulation is seeded
    with a .FIRST form, and each pass's prologue primes every register its MULTs
    read, so the program runs after another kernel as well as from reset.

    The last row of a call is usually short (numel - 128*(rows-1) lanes). Every
    store of every pass names exactly those lanes with the DS half CR15.H, so
    the row's scale comes from its live lanes and the lanes past numel are
    written 0. The loop therefore runs the full rows only; the last full row is
    emitted straight-line (it carries the one-row-ahead prefetch of the short
    row) and the short row is emitted straight-line with its own DS, which also
    keeps every prefetch inside the regions -- nothing ever loads row `rows`.
-#}
{% set qfl = cr.qf ~ ".L" %}
{% set rows = (numel + 127) // 128 %}
{% set tail = numel - 128 * (rows - 1) %}
{% set hastrail = tail != 128 %}
{% set main = rows - (1 if hastrail else 0) %}
{% set dsf = cr.ds ~ ".L" %}
{% set dsl = cr.ds ~ (".H" if hastrail else ".L") %}
{#- ---- pa: s = x^2, one word per row: the load and the store share it ------- -#}
{% macro PA(label, dsx, loads, branch) -%}
{% if branch %}{{ label }}:
{% endif %}
    {% if loads %}INC LR6 1 ;{% endif %} INC LR7 1 ;{% if branch %} DEC LR2 1 ;{% endif %}
    {% if loads %}LD.MULT.CYCLIC LR6 {{ cr.x }} LR0 ;{% endif %}
    MULT.RC.VS LR0 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.s }} LR7{% if branch %} ;
    BLT.S CR0 LR2 {{ label }} ;;{% else %} ;;{% endif %}
{%- endmacro %}
{#- ---- pb: m = lc + ld s, four multiplies and one store ---------------------- -#}
{% macro PB(label, dsx, loads, branch) -%}
{% if branch %}{{ label }}:
{% endif %}
    {% if loads %}INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.s }} LR0 ;{% endif %} INC LR7 1 ;
    MULT.RC.VE LR0 {{ cr.ld1 }} 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 {{ cr.ld2 }} 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD ;;
    MULT.EE LR0 {{ cr.lc1 }} 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD ;;
    MULT.EE LR0 {{ cr.lc2 }} 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.s }} LR7{% if branch %} ;
    DEC LR2 1 ;
    BLT.S CR0 LR2 {{ label }} ;;{% else %} ;;{% endif %}
{%- endmacro %}
{#- ---- pc: t = |x|, ACC.MAX of x*1.0 and its negation ------------------------ -#}
{% macro PC(label, dsx, loads, branch) -%}
{% if branch %}{{ label }}:
{% endif %}
    INC LR7 1 ;
    MULT.RC.VE LR0 CR1 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.SUB.FIRST ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.MAX ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.t }} LR7{% if loads %} ;
    INC LR6 1 ;
    LD.MULT.CYCLIC LR6 {{ cr.x }} LR0{% endif %}{% if branch %} ;
    DEC LR2 1 ;
    BLT.S CR0 LR2 {{ label }} ;;{% else %} ;;{% endif %}
{%- endmacro %}
{#- ---- pd: e = exp2(t m), the product and its exp2 store in one word --------- -#}
{% macro PD(label, dsx, loads, branch) -%}
{% if branch %}{{ label }}:
{% endif %}
    INC LR7 1 ;{% if loads %} INC LR8 1 ;
    LD.MULT R0 LR8 {{ cr.s }} ;{% endif %}
    MULT.RC.VV LR0 R0 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE exp2 {{ dsx }} {{ qfl }} {{ cr.s }} LR7{% if loads %} ;;
    INC LR6 1 ;
    LD.MULT.CYCLIC LR6 {{ cr.t }} LR0{% if branch %} ;
    DEC LR2 1 ;
    BLT.S CR0 LR2 {{ label }} ;;{% else %} ;;{% endif %}
{% else %} ;;{% endif %}
{%- endmacro %}
{#- ---- pe: q = 1/(1+e), the ones row's +1, stored into t's rows -------------- -#}
{% macro PE(label, dsx, loads, branch) -%}
{% if branch %}{{ label }}:
{% endif %}
    INC LR7 1 ;
    MULT.RC.VE LR0 CR1 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD.FIRST ;;
    MULT.EE LR0 CR1 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD ;
    ACTIVATE.QUANTIZE reciprocal {{ dsx }} {{ qfl }} {{ cr.t }} LR7{% if loads %} ;
    INC LR6 1 ;
    LD.MULT.CYCLIC LR6 {{ cr.s }} LR0{% endif %}{% if branch %} ;
    DEC LR2 1 ;
    BLT.S CR0 LR2 {{ label }} ;;{% else %} ;;{% endif %}
{%- endmacro %}
{#- ---- pf: w = e q, the product of the two stored rows, into e's rows -------- -#}
{% macro PF(label, dsx, loads, branch) -%}
{% if branch %}{{ label }}:
{% endif %}
    {% if loads %}INC LR8 1 ;
    LD.MULT R0 LR8 {{ cr.t }} ;{% endif %} INC LR7 1 ;
    MULT.RC.VV LR0 R0 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.s }} LR7{% if loads %} ;;
    INC LR6 1 ;
    LD.MULT.CYCLIC LR6 {{ cr.s }} LR0{% if branch %} ;
    DEC LR2 1 ;
    BLT.S CR0 LR2 {{ label }} ;;{% else %} ;;{% endif %}
{% else %} ;;{% endif %}
{%- endmacro %}
{#- ---- pg: y = max(x q, x w): three loads, two products, one store ----------- -#}
{% macro PG(label, dsx, loads, branch) -%}
{% if branch %}{{ label }}:
{% endif %}
    {% if loads %}INC LR8 1 ;
    LD.MULT R0 LR8 {{ cr.t }} ;{% endif %}
    MULT.RC.VV LR0 R0 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.MAX.FIRST ;;
    {% if loads %}INC LR9 1 ;
    LD.MULT R1 LR9 {{ cr.s }} ;{% endif %}
    MULT.RC.VV LR0 R1 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.MAX ;;
    INC LR7 1 ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.y }} LR7{% if loads %} ;
    INC LR6 1 ;
    LD.MULT.CYCLIC LR6 {{ cr.x }} LR0{% endif %}{% if branch %} ;
    DEC LR2 1 ;
    BLT.S CR0 LR2 {{ label }} ;;{% else %} ;;{% endif %}
{%- endmacro %}
{% set P = {"pa": PA, "pb": PB, "pc": PC, "pd": PD, "pe": PE, "pf": PF, "pg": PG} %}
{#- Every pass: its bound, its walks reset, its registers primed, then the row
    loop, the last full row straight-line and the short row straight-line. Each
    entry is (prologue loads/sets, whether the pass walks LR8/LR9). -#}
{% set prologues = {
  "pa": ["LD.MULT.CYCLIC LR0 " ~ cr.x ~ " LR0"],
  "pb": ["LD.MULT.CYCLIC LR0 " ~ cr.s ~ " LR0", "LD.MULT R0 LR0 " ~ cr.one],
  "pc": ["LD.MULT.CYCLIC LR0 " ~ cr.x ~ " LR0"],
  "pd": ["LD.MULT.CYCLIC LR0 " ~ cr.t ~ " LR0", "LD.MULT R0 LR0 " ~ cr.s],
  "pe": ["LD.MULT.CYCLIC LR0 " ~ cr.s ~ " LR0", "LD.MULT R0 LR0 " ~ cr.one],
  "pf": ["LD.MULT.CYCLIC LR0 " ~ cr.s ~ " LR0", "LD.MULT R0 LR0 " ~ cr.t],
  "pg": ["LD.MULT.CYCLIC LR0 " ~ cr.x ~ " LR0", "LD.MULT R0 LR0 " ~ cr.t, "LD.MULT R1 LR0 " ~ cr.s],
} %}

    SET LR0 CR0 ; LD.MASK LR0 {{ cr.maskr }} ;;               {#- 0: slot 0, the mask shift, row 0 -#}
    SET LR2 CR0 ; SET LR6 CR0 ;;                              {#- one trip: the `one` row is one row -#}
    LD.MULT.CYCLIC LR0 {{ cr.x }} LR0 ;;                      {#- a row of known sign into slot 0 -#}
one:
    MULT.RC.VE LR0 CR0 0 LR0 {{ dsf }} {{ qfl }} ;           {#- 0 * x: every lane 0, so exp2 gives 1.0 -#}
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE exp2 {{ dsf }} {{ qfl }} {{ cr.one }} LR6 ;
    DEC LR2 1 ;
    BLT.S CR0 LR2 one ;;
{% for name in ["pa", "pb", "pc", "pd", "pe", "pf", "pg"] %}
{#- ================================ {{ name }} ================================= -#}
    SET LR2 {{ cr.bound }} ; SET LR6 CR0 ;;{% if name in ["pd", "pf", "pg"] %} SET LR8 CR0 ;{% endif %}{% if name == "pg" %} SET LR9 CR0 ;{% endif %} SUB LR7 LR0 CR1 ;;
    {{ prologues[name][0] }} ;;
    {% for prime in prologues[name][1:] %}
    {{ prime }} ;;
    {% endfor %}
{% if main >= 2 %}
{{ P[name](name, dsf, true, true) }}
{% endif %}
{% if main >= 1 %}
{{ P[name](name, dsf, hastrail, false) }}
{% endif %}
{% if hastrail %}
{{ P[name](name ~ "t", dsl, false, false) }}
{% endif %}
{% endfor %}
end:
    HALT ;;
