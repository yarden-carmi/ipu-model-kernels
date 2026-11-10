{#- unary_silu.asm -- y = fn(x) elementwise over numel elements in 128-lane rows,
    ONE parameterised program for every (fn, numel): the rows are a dynamic loop
    whose bound is a CR, so a whole call is one launch (2304 rows is 2304 iterations
    of the same words) and the host tiles nothing but numel.

    x and y are the plain activation layout (row r holds lanes 128r .. 128r+127,
    lanes past numel zero), so this kernel reads the rows the previous kernel wrote
    and writes the rows the next one reads, with no repack between them. Every fn
    here satisfies fn(0) = 0, so a zero-padded input row keeps a zero-padded output
    row.

    Hardware-clean NX8: formats = ["dynamic"], every store is an ACTIVATE.QUANTIZE
    (identity, exp2 or reciprocal) and no emulator-only instruction appears. The
    AaQ activates into memory, never back into R_ACC, so a value that has to become
    a multiplicand leaves and comes back as an NX8 row; the passes below are exactly
    those round trips, and each is the floor its dataflow allows (one LOAD and one
    MULT slot per word).

      silu / quick_gelu  y = x / (1 + exp(-x))
      gelu_tanh          y = x * sigmoid(1.5957691216057308 (x + 0.044715 x^3)),
                         the sigmoid's argument being of x's sign, so the same
                         two-branch form applies to |a| (gelu, the erf form, is
                         this to ~1e-3 absolute: declared unsupported rather than
                         silently substituted).

    e = exp2(-|z| log2 e) is the AaQ exp2 of a row whose argument is <= 0 in every
    lane (|z| >= 0 and both log2(e) terms are negative) -- exp2 of a positive input
    is an AaQ error, which is why every transcendental here goes through -|z| -- and
    q = 1/(1+e) is the AaQ reciprocal. log2(e) enters as the sum of two dyadic
    terms, one MULT.RC.VE each, because an NX8 MULT constant holds at most 7
    significant bits: one of them would move the exponent, and every output with it,
    by 4e-2 relative.

    The branch a positive and a negative lane need is built with ACC.MAX, so no
    compare and no sign test exists in the program. With z the sigmoid's argument
    (x, or a = 1.59576... (x + 0.044715 x^3), always of x's sign), e = exp(-|z|),
    q = 1/(1+e) and w = e q = e/(1+e):

        y = max(x q, x w)

    For x >= 0 the larger product is x q (q >= 1/2 >= w); for x < 0 both products
    are negative, the smaller magnitude wins, and there w = e/(1+e) is exactly
    sigmoid(z). w is the product of the two stored rows rather than 1 - q: a q row
    whose largest lane is 1.0 has a step of 2^-7, and e/(1+e) at |z| = 8 is 3e-4, so
    1 - q taken from an 8-bit q cancels every lane with |z| > 6 away, while the
    product is quantized with a scale of its own.

    Passes (t: |z| or |x|; e: exp(-|z|); q: 1/(1+e); w: e q -- one row of `rows` each):

      p1  t = |x|              2 words/row  ACC.SUB.FIRST of x*1.0, then ACC.MAX of
                                            the same product: max(-x, x) = |x|.
      p0  t = t (1 + k1 x^2)   3 words/row  [gelu_tanh only] MULT.RC.VV of t against
                                            the same row held in Ra (ACC.ADD.FIRST:
                                            a product enters R_ACC as an add), then
                                            the k1 term.
      p2  e = exp2(t*-log2e)   2 words/row  two MULT.RC.VE, one AaQ exp2 store.
      p3  q = 1/(1+e)          2 words/row  e*1.0, then the ones row broadcast by
                                            MULT.EE (Ra's R0[0] of `one`, whose 1.0
                                            the prologue stores itself with exp2(0) --
                                            the host prepares no constant), AaQ
                                            reciprocal.
      p4  w = e q              2 words/row  one MULT.RC.VV of e's row (slot 0) against
                                            q's row (Ra), ACC.ADD.FIRST and the store
                                            in the same word; the second word carries
                                            e's one-row-ahead load.
      p5  y = max(x q, x w)    3 words/row  three loads (x -> R_CYCLIC slot 0, q ->
                                            Ra's R0, w -> Ra's R1, one per word) and
                                            two MULT.RC.VV joined by ACC.MAX.FIRST
                                            and ACC.MAX, one identity store.

    relu, relu6 and neg need no intermediate: one word per row -- the AaQ has relu
    and relu6 itself, and neg is that word with ACC.SUB.FIRST as the negate and an
    identity store.

    The last row of a call is usually short (numel - 128*(rows-1) lanes). Every
    store of every pass names exactly those lanes with the DS half CR15.H, so the
    row's scale comes from its live lanes and the lanes past numel are written 0:
    with a DS of 128 a tail row holding one lane takes its scale from the zeros the
    pad lanes leave in the intermediate rows (a stored e of 1.0 beside an e of 5e-4)
    and the live lane quantizes away. The loop therefore runs the full rows only;
    the last full row is emitted straight-line (it carries the one-row-ahead
    prefetch of the short row) and the short row is emitted straight-line with its
    own DS, which is also what keeps every prefetch inside the regions -- nothing
    ever loads row `rows`.

    Timing contract (docs/content/explanation/timing-model.md), which sets the shape
    of every loop: LOAD reads the LRs *after* the same word's LR writes, so a walk is
    INC'd in its own load word and names the next row; MULT reads R0/R1/R_CYCLIC as
    the word began, so every load is at least one word ahead of the multiply that
    consumes it; ACC takes this word's MULT_RES and ACTIVATE.QUANTIZE this word's
    R_ACC, so multiply, accumulate and store share a word; the LR sub-slots and the
    branch read cycle-start values, so ADD LR7 LR6 CR0 beside INC LR6 1 gives the
    store this row's number while the load moves on; the branch reads the counter
    before its DEC, so the bound is trips - 1. No word writes one LR twice and no
    word holds two loads. LR0 is zeroed before anything reads it, R_MASK is loaded
    from its own all-ones row, every accumulation is seeded with a .FIRST form
    (ACC.ADD.FIRST is also how a product of two rows enters R_ACC, the accumulator
    having no multiply form), and each pass's prologue primes every
    register its MULTs read, so the program runs after another kernel as well as
    from reset.
-#}
{% set sig = fn in ["silu", "quick_gelu", "gelu_tanh"] %}
{% set cubic = fn == "gelu_tanh" %}
{% set qfl = cr.qf ~ ".L" %}
{% set rows = (numel + 127) // 128 %}
{% set tail = numel - 128 * (rows - 1) %}
{% set hastrail = tail != 128 %}
{% set main = rows - (1 if hastrail else 0) %}
{% set dsf = cr.ds ~ ".L" %}
{% set dsl = cr.ds ~ (".H" if hastrail else ".L") %}
{% set M1 = "MULT.RC.VE LR0 CR1 0 LR0 " %}
{#- ---------------- a pass of two words: two multiplies, one store ---------------- -#}
{% macro P2(label, dsx, m1, a1, m2, a2, act, dst, load, loads, branch) -%}
{% if branch %}{{ label }}:
{% endif %}
    {{ m1 }}{{ dsx }} {{ qfl }} ;
    {{ a1 }} ;
    INC LR7 1 ;;
    {{ m2 }}{{ dsx }} {{ qfl }} ;
    {{ a2 }} ;
    ACTIVATE.QUANTIZE {{ act }} {{ dsx }} {{ qfl }} {{ dst }} LR7{% if loads %} ;
    INC LR6 1 ;
    {{ load }} ;
    DEC LR2 1{% if branch %} ;
    BLT.S CR0 LR2 {{ label }} ;;{% else %} ;;{% endif %}{% else %} ;;{% endif %}
{%- endmacro %}
{#- ------------- a pass of three words: two multiplies, three loads -------------- -#}
{% macro P3(label, dsx, l1, m1, a1, l2, m2, a2, l3, act, dst, loads, branch) -%}
{% if branch %}{{ label }}:
{% endif %}
    {% if loads and l1 %}{{ l1 }} ;{% endif %}
    {{ m1 }}{{ dsx }} {{ qfl }} ;
    {{ a1 }} ;;
    {% if loads and l2 %}{{ l2 }} ;{% endif %}
    {{ m2 }}{{ dsx }} {{ qfl }} ;
    {{ a2 }} ;;
    {% if loads and l3 %}{{ l3 }} ;{% endif %}
    ACTIVATE.QUANTIZE {{ act }} {{ dsx }} {{ qfl }} {{ dst }} LR7 ;
    INC LR7 1{% if loads %} ; DEC LR2 1{% if branch %} ;
    BLT.S CR0 LR2 {{ label }} ;;{% else %} ;;{% endif %}{% else %} ;;{% endif %}
{%- endmacro %}
{#- ----------------- the single-pass fn: one word, one multiply ------------------ -#}
{% macro P1(label, dsx, a, act, loads, branch) -%}
{% if branch %}{{ label }}:
{% endif %}
    {% if loads %}INC LR6 1 ;{% endif %} ADD LR7 LR6 CR0 ;{% if branch %} DEC LR2 1 ;{% endif %}
    {% if loads %}LD.MULT.CYCLIC LR6 {{ cr.x }} LR0 ;{% endif %}
    {{ M1 }}{{ dsx }} {{ qfl }} ;
    {{ a }} ;
    ACTIVATE.QUANTIZE {{ act }} {{ dsx }} {{ qfl }} {{ cr.y }} LR7{% if branch %} ;
    BLT.S CR0 LR2 {{ label }} ;;{% else %} ;;{% endif %}
{%- endmacro %}
{#- --------------------- the two-word passes' shared prologue -------------------- -#}
{% macro PRE(src) -%}
    SET LR2 {{ cr.bound }} ; SET LR6 CR0 ; SUB LR7 LR0 CR1 ;;
    LD.MULT.CYCLIC LR0 {{ src }} LR0 ;;
{%- endmacro %}

{% if sig %}
{#- ====== prologue: the zero, the mask, and the ones row the +1 broadcasts ======== -#}
    SET LR0 CR0 ; LD.MASK LR0 {{ cr.maskr }} ;;             {#- 0: slot 0, the mask shift, Ra's element 0 -#}
    SET LR2 CR0 ; SET LR6 CR0 ;;                            {#- one trip: the `one` row is one row -#}
    LD.MULT.CYCLIC LR0 {{ cr.x }} LR0 ;;                    {#- a row of known sign into slot 0 -#}
one:
    MULT.RC.VE LR0 CR0 0 LR0 {{ dsf }} {{ qfl }} ;         {#- 0 * x: every lane 0, so exp2 gives 1.0 -#}
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE exp2 {{ dsf }} {{ qfl }} {{ cr.one }} LR6 ;
    DEC LR2 1 ;
    BLT.S CR0 LR2 one ;;
{#- ================================ p1: t = |x| ================================= -#}
{{ PRE(cr.x) }}
{% if main >= 2 %}
{{ P2("p1", dsf, M1, "ACC.SUB.FIRST", M1, "ACC.MAX", "identity", cr.t, "LD.MULT.CYCLIC LR6 " ~ cr.x ~ " LR0", true, true) }}
{% endif %}
{% if main >= 1 %}
{{ P2("p1", dsf, M1, "ACC.SUB.FIRST", M1, "ACC.MAX", "identity", cr.t, "LD.MULT.CYCLIC LR6 " ~ cr.x ~ " LR0", hastrail, false) }}
{% endif %}
{% if hastrail %}
{{ P2("p1t", dsl, M1, "ACC.SUB.FIRST", M1, "ACC.MAX", "identity", cr.t, "", false, false) }}
{% endif %}
{% if cubic %}
{#- ================= p0: t = t (1 + k1 x^2) = |a|, gelu_tanh only =============== -#}
    SET LR2 {{ cr.bound }} ; SET LR6 CR0 ; SUB LR7 LR0 CR1 ;;
    SET LR8 CR0 ;;                                          {#- t's walk into Ra -#}
    LD.MULT.CYCLIC LR0 {{ cr.t }} LR0 ;;                    {#- prime: t[0] -> slot 0 -#}
    LD.MULT R0 LR0 {{ cr.t }} ;;                            {#- and -> Ra, t's other factor -#}
{% set v1 = "MULT.RC.VV LR0 R0 0 LR0 " %}
{% set v2 = "MULT.RC.VE LR0 " ~ cr.k1 ~ " 0 LR0 " %}
{% if main >= 2 %}
{{ P3("p0", dsf, "INC LR8 1 ; LD.MULT R0 LR8 " ~ cr.t, v1, "ACC.ADD.FIRST", "INC LR6 1 ; LD.MULT.CYCLIC LR6 " ~ cr.t ~ " LR0", v2, "ACC.ADD", "", "identity", cr.t, true, true) }}
{% endif %}
{% if main >= 1 %}
{{ P3("p0", dsf, "INC LR8 1 ; LD.MULT R0 LR8 " ~ cr.t, v1, "ACC.ADD.FIRST", "INC LR6 1 ; LD.MULT.CYCLIC LR6 " ~ cr.t ~ " LR0", v2, "ACC.ADD", "", "identity", cr.t, hastrail, false) }}
{% endif %}
{% if hastrail %}
{{ P3("p0t", dsl, "", v1, "ACC.ADD.FIRST", "", v2, "ACC.ADD", "", "identity", cr.t, false, false) }}
{% endif %}
{% endif %}
{#- ================= p2: e = exp2(t * -log2 e), read from t, stored to e ========= -#}
{{ PRE(cr.t) }}
{% set e1 = "MULT.RC.VE LR0 " ~ cr.c1 ~ " 0 LR0 " %}
{% set e2 = "MULT.RC.VE LR0 " ~ cr.c2 ~ " 0 LR0 " %}
{% if main >= 2 %}
{{ P2("p2", dsf, e1, "ACC.ADD.FIRST", e2, "ACC.ADD", "exp2", cr.e, "LD.MULT.CYCLIC LR6 " ~ cr.t ~ " LR0", true, true) }}
{% endif %}
{% if main >= 1 %}
{{ P2("p2", dsf, e1, "ACC.ADD.FIRST", e2, "ACC.ADD", "exp2", cr.e, "LD.MULT.CYCLIC LR6 " ~ cr.t ~ " LR0", hastrail, false) }}
{% endif %}
{% if hastrail %}
{{ P2("p2t", dsl, e1, "ACC.ADD.FIRST", e2, "ACC.ADD", "exp2", cr.e, "", false, false) }}
{% endif %}
{#- ======================= p3: q = 1/(1+e), the ones row's +1 ==================== -#}
    LD.MULT R0 LR0 {{ cr.one }} ;;                          {#- the ones row -> Ra's R0: MULT.EE's source -#}
{{ PRE(cr.e) }}
{% set r1 = "MULT.RC.VE LR0 CR1 0 LR0 " %}
{% set r2 = "MULT.EE LR0 CR1 0 LR0 " %}
{% if main >= 2 %}
{{ P2("p3", dsf, r1, "ACC.ADD.FIRST", r2, "ACC.ADD", "reciprocal", cr.q, "LD.MULT.CYCLIC LR6 " ~ cr.e ~ " LR0", true, true) }}
{% endif %}
{% if main >= 1 %}
{{ P2("p3", dsf, r1, "ACC.ADD.FIRST", r2, "ACC.ADD", "reciprocal", cr.q, "LD.MULT.CYCLIC LR6 " ~ cr.e ~ " LR0", hastrail, false) }}
{% endif %}
{% if hastrail %}
{{ P2("p3t", dsl, r1, "ACC.ADD.FIRST", r2, "ACC.ADD", "reciprocal", cr.q, "", false, false) }}
{% endif %}
{#- -------- p4: w = e q = sigmoid(-|z|), the product of two stored rows --------- -#}
{% macro PG(label, dsx, loads, branch) -%}
{% if branch %}{{ label }}:
{% endif %}
    {% if loads %}INC LR8 1 ; LD.MULT R0 LR8 {{ cr.q }} ;{% endif %}
    INC LR7 1 ;
    MULT.RC.VV LR0 R0 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD.FIRST ;                                         {#- the product is this word's MULT_RES -#}
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.w }} LR7 ;;
{% if loads %}
    INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.e }} LR0 ; DEC LR2 1{% if branch %} ;
    BLT.S CR0 LR2 {{ label }} ;;{% else %} ;;{% endif %}
{% endif %}
{%- endmacro %}
    SET LR2 {{ cr.bound }} ; SET LR6 CR0 ; SET LR8 CR0 ;;
    SUB LR7 LR0 CR1 ;;                                      {#- the store walk, one behind -#}
    LD.MULT.CYCLIC LR0 {{ cr.e }} LR0 ;;                    {#- prime: e[0] -> slot 0 -#}
    LD.MULT R0 LR0 {{ cr.q }} ;;                            {#- and q[0] -> Ra -#}
{% if main >= 2 %}
{{ PG("p4", dsf, true, true) }}
{% endif %}
{% if main >= 1 %}
{{ PG("p4", dsf, hastrail, false) }}
{% endif %}
{% if hastrail %}
{{ PG("p4t", dsl, false, false) }}
{% endif %}
{#- ====================== p5: y = max(x q, x w): two products ==================== -#}
    SET LR2 {{ cr.bound }} ; SET LR6 CR0 ; SUB LR7 LR0 CR1 ;;
    SET LR8 CR0 ; SET LR9 CR0 ;;                            {#- the q and w row walks -#}
    LD.MULT.CYCLIC LR0 {{ cr.x }} LR0 ;;                    {#- prime: x[0] -> slot 0 -#}
    LD.MULT R0 LR0 {{ cr.q }} ;;                            {#- and q[0] -> Ra, w[0] -> R1 -#}
    LD.MULT R1 LR0 {{ cr.w }} ;;
{% set p1v = "MULT.RC.VV LR0 R0 0 LR0 " %}
{% set p2v = "MULT.RC.VV LR0 R1 0 LR0 " %}
{% if main >= 2 %}
{{ P3("p5", dsf, "INC LR8 1 ; LD.MULT R0 LR8 " ~ cr.q, p1v, "ACC.MAX.FIRST", "INC LR9 1 ; LD.MULT R1 LR9 " ~ cr.w, p2v, "ACC.MAX", "INC LR6 1 ; LD.MULT.CYCLIC LR6 " ~ cr.x ~ " LR0", "identity", cr.y, true, true) }}
{% endif %}
{% if main >= 1 %}
{{ P3("p5", dsf, "INC LR8 1 ; LD.MULT R0 LR8 " ~ cr.q, p1v, "ACC.MAX.FIRST", "INC LR9 1 ; LD.MULT R1 LR9 " ~ cr.w, p2v, "ACC.MAX", "INC LR6 1 ; LD.MULT.CYCLIC LR6 " ~ cr.x ~ " LR0", "identity", cr.y, hastrail, false) }}
{% endif %}
{% if hastrail %}
{{ P3("p5t", dsl, "", p1v, "ACC.MAX.FIRST", "", p2v, "ACC.MAX", "", "identity", cr.y, false, false) }}
{% endif %}
{% else %}
{#- ==================== relu / relu6 / neg: one word per row ===================== -#}
{% set act = "identity" if fn == "neg" else fn %}
{% set acc = "ACC.SUB.FIRST" if fn == "neg" else "ACC.ADD.FIRST" %}
    SET LR0 CR0 ; LD.MASK LR0 {{ cr.maskr }} ;;             {#- 0: slot 0, the mask shift, the mask offset -#}
    SET LR2 {{ cr.bound }} ; SET LR6 CR0 ;;                 {#- the loop's bound; the row walk -#}
    LD.MULT.CYCLIC LR0 {{ cr.x }} LR0 ;;                    {#- prime: x[0] -> slot 0 -#}
{% if main >= 2 %}
{{ P1("srow", dsf, acc, act, true, true) }}
{% endif %}
{% if main >= 1 %}
{{ P1("srow", dsf, acc, act, hastrail, false) }}
{% endif %}
{% if hastrail %}
{{ P1("srowt", dsl, acc, act, false, false) }}
{% endif %}
{% endif %}
end:
    HALT ;;
