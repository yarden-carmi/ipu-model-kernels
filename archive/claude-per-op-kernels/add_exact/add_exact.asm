{#- add_exact.asm -- y = a + b elementwise over numel elements, one XMEM row (128 elements) per iteration.

    Design notes
    - a, b and y are 1-D tensors of numel elements: ceil(numel / 128) rows,
      zero past numel.
    - There is no vector add: each addend passes through the multiplier
      against CR1 (1.0 as a MULT constant in every mode, so the product is
      the decoded element, exact) and the accumulator sums the two:
        word 1: MULT.RC.VE  a[r] x 1.0       ; ACC.ADD.FIRST  (R_ACC = a[r])
        word 2: MULT.VE     b[r] x 1.0       ; ACC.ADD        (R_ACC = a[r] + b[r])
                ACTIVATE.QUANTIZE identity stores R_ACC in that same word
                (timing rule 3): in NX8 it rounds the FP32 sum to the case's
                QF, the only approximation; in FP32 it stores it unchanged.
    - operands = "tensor" ({{ operands }} here): a row of a is in R_CYCLIC and
      the same row of b in R0. A broadcast b is expanded to a's shape on the
      host first, so the program is the same for broadcast = true and false.
    - operands = "scalar": y[i] = a[i] + b[0]. b's first row is loaded into R0
      once, and word 2 is MULT.EE, which broadcasts R0[0] x 1.0 to all 128
      lanes. The rest of b is never read. Padding lanes of a partial last row
      store b[0]; they lie past numel.
    - MULT reads R_CYCLIC and R0 at cycle start (rule 2), so each load runs one
      word ahead of its MULT: word 1 loads b[r] into R0 (tensor mode), word 2
      increments LR1 and loads a[r + 1] into R_CYCLIC (the load's offset is
      forwarded). The store's offset is forwarded too, so it uses the base
      {{ cr.y }} = y - 1. BLT.S reads LR1 at cycle start (= r), so it compares
      with last = rows - 1. The last iteration loads one row past a, which is
      the next region, and never uses it.
    - Words per row: 2 in both modes (one LOAD slot; two MULTs per row).
    - Registers: LR0 = 0 (R_CYCLIC index, Ra index, mask shift, scalar index);
      LR1 = the row (row + 1 after the increment in word 2).
-#}
    SET LR0 CR0 ;
    SET LR1 CR0 ;;
{%- if operands == "scalar" %}
    LD.MULT R0 LR0 {{ cr.b }} ;;
{%- endif %}
    LD.MULT.CYCLIC LR1 {{ cr.a }} LR0 ;;
row_loop:
{%- if operands == "scalar" %}
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD.FIRST ;;
{%- else %}
    LD.MULT R0 LR1 {{ cr.b }} ;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD.FIRST ;;
{%- endif %}
    INC LR1 1 ;
    LD.MULT.CYCLIC LR1 {{ cr.a }} LR0 ;
{%- if operands == "scalar" %}
    MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
{%- else %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
{%- endif %}
    ACC.ADD ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.y }} LR1 ;
    BLT.S LR1 {{ cr.last }} row_loop ;;
    HALT ;;
