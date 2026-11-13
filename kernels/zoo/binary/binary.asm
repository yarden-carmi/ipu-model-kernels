{#- y = a * const, elementwise (chain step 1: binary mul by a scalar). One row of the tensor per word:
    load the next row, multiply this row by the CR scalar constant into the accumulator and store it with an
    identity activation. The tensor is numel elements over ceil(numel/128) rows; the last row can be partial, so
    it is stored through ds_last instead of the full-row ds. The store's row address is computed with ADD into
    LR4 because the store reads its LR after the word's LR writes. -#}
{%- set rows = ((numel + 127) // 128) %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR4 CR0 ;;
    LD.MULT R0 LR1 {{ cr.a }} ;;
    BLT.S LR2 {{ cr.rows_m1 }} row_loop ;;
    ADD LR4 LR2 CR0 ; LD.MULT R0 LR1 {{ cr.a }} ; MULT.VE LR0 {{ cr.const }} 0 LR0 {{ cr.ds_last }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.ds_last }}.L {{ cr.qf }}.L {{ cr.y }} LR4 ;;
    HALT ;;
row_loop:
    INC LR1 1 ; INC LR2 1 ; ADD LR4 LR2 CR0 ; LD.MULT R0 LR1 {{ cr.a }} ; MULT.VE LR0 {{ cr.const }} 0 LR0 {{ cr.ds }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf }}.L {{ cr.y }} LR4 ; BLT.S LR2 {{ cr.rows_m2 }} row_loop ;;
    ADD LR4 LR2 CR0 ; LD.MULT R0 LR1 {{ cr.a }} ; MULT.VE LR0 {{ cr.const }} 0 LR0 {{ cr.ds_last }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.ds_last }}.L {{ cr.qf }}.L {{ cr.y }} LR4 ;;
    HALT ;;
