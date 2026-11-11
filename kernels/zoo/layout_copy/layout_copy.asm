{#- layout_copy.asm -- layout: data movement (copy) of numel elements.

    kind = copy: y[i] = x[i]. x and y are ceil(numel/128) rows each, row i
    holding elements 128i..128i+127, lanes past numel zero -- the layout every
    activation on the chip uses, so y is the next kernel's input.

    Dataflow: the only way into R_ACC is a multiply result, so each row is
    multiplied by the CR constant 1.0 and stored with ACTIVATE.QUANTIZE
    identity -- a copy at the store's exact quantization. One word per row:
    the row being multiplied is resident in R1 (MULT.VE reads Ra, R1's elements
    sit at Ra offset 128), the next row's load rides in the same word (LOAD
    reads LRs after the same word's writes; MULT reads R1 as the word began).

    Timing contract: the Control stage (branch) reads LRs at cycle start; the
    LOAD and AAQ stages read them after the same word's LR writes. LR1 is the
    x row pointer and LR3 the row being stored, each INC'd in the word whose
    LOAD / store uses the new value, so iteration k stores row k-1 and loads
    row k; the branch reads LR3 as the word began, i.e. the last row stored,
    so the loop runs while that is below the bound -- the last load stays
    inside x's region.

    The last row is emitted straight-line with its own DS half (tail lanes
    when numel is not a multiple of 128), reading the row the loop's last
    iteration already loaded into R1; when numel is a multiple of 128 that
    row is a full row and the store names 128 lanes. When rows = 1 the whole
    call is the prime load plus that one word.

    LR: LR0 0 (mask shift); LR1 the x row pointer; LR2 the last row's store
    index; LR3 the store counter; LR4 the loop bound; LR11 128 (R1's offset
    in Ra). The program sets every LR it reads and loads its own mask row, so
    it runs after another kernel as well as from reset.
-#}
{% set rows = (numel + 127) // 128 %}
{% set tail = numel - 128 * (rows - 1) %}
{% set hastrail = tail != 128 %}
{% set dsf = cr.ds ~ ".L" %}
{% set dslast = cr.ds ~ (".H" if hastrail else ".L") %}
{% set qfl = cr.qf ~ ".L" %}
    SET LR0 CR0 ; SET LR11 CR12 ; SET LR4 CR5 ;;   {#- mask shift; R1's Ra offset; loop bound -#}
    SET LR3 CR0 ; SET LR1 CR0 ; SET LR2 CR6 ;;     {#- store counter; x row pointer; last row's index -#}
    DEC LR3 1 ; LD.MASK LR0 CR4 ;;                 {#- counter one behind; every lane active -#}
    LD.MULT R1 LR1 CR2 ;;                          {#- prime: x[0] -> R1 -#}
{% if rows >= 2 %}
row_loop:
    INC LR1 1 ; INC LR3 1 ; LD.MULT R1 LR1 CR2 ; MULT.VE LR11 CR1 0 LR0 {{ dsf }} {{ qfl }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ dsf }} {{ qfl }} {{ cr.y }} LR3 ; BLT.S LR1 LR4 row_loop ;;
{% endif %}
    MULT.VE LR11 CR1 0 LR0 {{ dslast }} {{ qfl }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ dslast }} {{ qfl }} {{ cr.y }} LR2 ;;
    HALT ;;
