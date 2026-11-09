{#- mul_exact.asm -- y = a * b elementwise over numel elements, one XMEM row (128 elements) per iteration.

    Design notes
    - a, b and y are 1-D tensors of numel elements: ceil(numel / 128) rows,
      zero past numel (a partial last row computes 0 * 0 = 0 in its padding).
    - operands = "tensor" ({{ operands }} here): y[i] = a[i] * b[i]. A row of a
      is loaded into R_CYCLIC, the same row of b into R0, and MULT.RC.VV
      multiplies them exactly (FP32 product of two decoded elements). A
      broadcast b is expanded to a's shape on the host first, so the program
      is the same for broadcast = true and false.
    - operands = "scalar": y[i] = a[i] * b[0]. b's first row is loaded into R0
      once, and MULT.RC.VE with the LR source LR0 (= 0) reads the scalar R0[0].
      The rest of b is never read.
    - ACC.ADD.FIRST takes the product, and ACTIVATE.QUANTIZE identity stores
      the row in the same word (timing rule 3): in NX8 it rounds to the case's
      QF, the only approximation; in FP32 it stores the product unchanged.
    - MULT reads R_CYCLIC and R0 at cycle start (rule 2), so each row is
      loaded one word ahead: LR1 is incremented first in the multiply word,
      that word's LD.MULT.CYCLIC already fetches the next row of a, and the
      store uses the base {{ cr.y }} = y - 1. The last iteration loads one row
      past a (and in tensor mode past b), which is the next region, in XMEM,
      and never used.
    - Words per row: 2 in tensor mode (two loads, one LOAD slot), 1 in scalar
      mode.
    - Registers: LR0 = 0 (R_CYCLIC index, mask shift, scalar index); LR1 = the
      row (after the increment, row + 1).
-#}
    SET LR0 CR0 ;
    SET LR1 CR0 ;;
{%- if operands == "scalar" %}
    LD.MULT R0 LR0 {{ cr.b }} ;;
    LD.MULT.CYCLIC LR1 {{ cr.a }} LR0 ;;
row_loop:
    INC LR1 1 ;
    LD.MULT.CYCLIC LR1 {{ cr.a }} LR0 ;
    MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.y }} LR1 ;
    BLT.S LR1 {{ cr.last }} row_loop ;;
{%- else %}
    LD.MULT.CYCLIC LR1 {{ cr.a }} LR0 ;;
    LD.MULT R0 LR1 {{ cr.b }} ;;
row_loop:
    INC LR1 1 ;
    LD.MULT.CYCLIC LR1 {{ cr.a }} LR0 ;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.y }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.b }} ;
    BLT.S LR1 {{ cr.rows }} row_loop ;;
{%- endif %}
    HALT ;;
