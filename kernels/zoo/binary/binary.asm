{#- binary elementwise: out0 = in0 <op> operand. The operand is in1 (broadcast
    "none"), the constant `const` or its reciprocal (broadcast "scalar", chosen
    by `reciprocal`), a row vector of `inner` elements repeated across the flat
    rows (broadcast "row"), or one element per `inner`-element row of in0
    (broadcast "col"). One memory row of 128 elements per pass: the multiplier
    and accumulator build the row in FP32 and ACTIVATE.QUANTIZE stores it.
    The store reads its offset LR after the word's LR writes, so the output
    pointer LR4 is incremented in a word after the store that uses it; the loop
    branch shares the store word and reads LR2 before that word's INC.
    A ones row in R_CYCLIC turns a scalar into a vector; for the col case with
    inner = 320 (2.5 memory rows per period) the row that straddles two scalars
    is fixed with a zeros row in R_CYCLIC slot 1, the second scalar broadcast
    in slot 2, and a window read at index 192. -#}
    SET LR0 CR0 ;;
{% if broadcast == "scalar" %}
    SET LR2 CR0 ; SET LR4 CR0 ;;
    SUB LR4 LR4 CR1 ;;
{% if reciprocal %}
{#- 1/const: broadcast const with the ones row, store with the reciprocal
    activation into sb row 0, keep it in R0 -#}
    SET LR15 CR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.ones }} LR0 ;;
    MULT.RC.VE LR0 {{ cr.const }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE reciprocal CR15.L {{ cr.qf }}.L {{ cr.sb }} LR15 ;;
    LD.MULT R0 LR15 {{ cr.sb }} ;;
{% endif %}
{% if op == "mul" %}
s_loop:
{% if reciprocal %}
    LD.MULT.CYCLIC LR2 CR2 LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ; INC LR2 1 ; INC LR4 1 ; BLT.S LR2 {{ cr.rfm1 }} s_loop ;;
{% else %}
    LD.MULT R0 LR2 CR2 ;;
    MULT.VE LR0 {{ cr.const }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ; INC LR2 1 ; INC LR4 1 ; BLT.S LR2 {{ cr.rfm1 }} s_loop ;;
{% endif %}
{% if numel % 128 != 0 %}
{% if reciprocal %}
    LD.MULT.CYCLIC LR2 CR2 LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.dst }}.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ;;
{% else %}
    LD.MULT R0 LR2 CR2 ; INC LR4 1 ;;
    MULT.VE LR0 {{ cr.const }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.dst }}.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ;;
{% endif %}
{% endif %}
{% else %}
{% if reciprocal %}
    SET LR13 CR1 ;;
    ADD LR12 LR13 CR1 ;;
    ADD LR13 LR12 LR12 ;;
    ADD LR12 LR13 LR13 ;;
    ADD LR13 LR12 LR12 ;;
    ADD LR12 LR13 LR13 ;;
    ADD LR13 LR12 LR12 ;;
    ADD LR12 LR13 LR13 ;;
s_loop:
    LD.MULT R1 LR2 CR2 ;;
    MULT.VE LR12 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ; INC LR2 1 ; INC LR4 1 ; BLT.S LR2 {{ cr.rfm1 }} s_loop ;;
{% if numel % 128 != 0 %}
    LD.MULT R1 LR2 CR2 ;;
    MULT.VE LR12 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ cr.dst }}.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ;;
{% endif %}
{% else %}
    LD.MULT.CYCLIC LR0 {{ cr.ones }} LR0 ;;
s_loop:
    LD.MULT R0 LR2 CR2 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 {{ cr.const }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ; INC LR2 1 ; INC LR4 1 ; BLT.S LR2 {{ cr.rfm1 }} s_loop ;;
{% if numel % 128 != 0 %}
    LD.MULT R0 LR2 CR2 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 {{ cr.const }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ cr.dst }}.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ;;
{% endif %}
{% endif %}
{% endif %}
{% elif broadcast == "none" %}
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
    SUB LR4 LR4 CR1 ;;
n_loop:
    LD.MULT R0 LR3 CR3 ;;
    LD.MULT.CYCLIC LR2 CR2 LR0 ;;
{% if op == "mul" %}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ; INC LR2 1 ; INC LR3 1 ; INC LR4 1 ; BLT.S LR2 {{ cr.rfm1 }} n_loop ;;
{% else %}
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ; INC LR2 1 ; INC LR3 1 ; INC LR4 1 ; BLT.S LR2 {{ cr.rfm1 }} n_loop ;;
{% endif %}
{% elif broadcast == "row" %}
{#- in1 row j = flat row mod inner/128: nested loops, in1 pointer reset per group -#}
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR14 ;;
g_loop:
    SET LR3 CR0 ;;
j_loop:
    LD.MULT R0 LR3 CR3 ;;
    LD.MULT.CYCLIC LR2 CR2 LR0 ;;
{% if op == "mul" %}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ; INC LR2 1 ; INC LR3 1 ;;
{% else %}
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ; INC LR2 1 ; INC LR3 1 ;;
{% endif %}
    DEC LR5 1 ; INC LR4 1 ;;
    BNE LR5 CR0 j_loop ;;
    SET LR5 CR14 ; BLT.S LR2 {{ cr.rf }} g_loop ;;
{% else %}
{#- col: flat row m holds element r = m / (inner/128) of the column vector, at
    lane r mod 128 of in1 memory row r / 128 -#}
    SET LR2 CR0 ; SET LR4 CR0 ; SET LR7 CR0 ;;
    SET LR10 CR1 ;;
    ADD LR11 LR10 CR1 ;;
    ADD LR10 LR11 LR11 ;;
    ADD LR11 LR10 LR10 ;;
    ADD LR10 LR11 LR11 ;;
    ADD LR11 LR10 LR10 ;;
    ADD LR10 LR11 LR11 ;;
    ADD LR11 LR10 LR10 ;;
{% if inner == 320 %}
{#- inner = 320: period 5 memory rows, row 5t+2 straddles scalars 2t and 2t+1.
    LR10=64, LR11=192, LR12=256, LR13=128, LR15=2 -#}
    SET LR13 LR11 ;;
    ADD LR12 LR11 LR11 ;;
    ADD LR11 LR13 LR10 ;;
    ADD LR14 LR12 LR13 ;;
    SET LR6 CR1 ;;
    ADD LR15 LR6 CR1 ;;
    SET LR3 CR0 ; SET LR5 CR1 ;;
    SET LR8 CR0 ; SET LR9 CR0 ;;
    LD.MULT R1 LR0 {{ cr.ones }} ;;
    LD.MULT.CYCLIC LR0 {{ cr.zeros }} LR13 ;;
blk_loop:
    LD.MULT R0 LR7 CR3 ;;
t_loop:
    BGE.S LR2 {{ cr.rf }} t_done ;;
    LD.MULT.CYCLIC LR2 CR2 LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR0 {{ cr.ones }} LR0 ;;
    MULT.RC.VE LR0 LR3 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ; INC LR2 1 ;;
    LD.MULT.CYCLIC LR2 CR2 LR0 ; INC LR4 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR0 {{ cr.ones }} LR0 ;;
    MULT.RC.VE LR0 LR3 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ; INC LR2 1 ;;
    MULT.EE LR3 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.sb }} LR9 ;;
    LD.MULT.CYCLIC LR9 {{ cr.sb }} LR0 ;;
    MULT.EE LR5 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; INC LR4 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.sb }} LR9 ;;
    LD.MULT.CYCLIC LR9 {{ cr.sb }} LR12 ;;
    LD.MULT.CYCLIC LR2 CR2 LR14 ;;
    MULT.RC.VV LR14 R1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR10 R1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.RC.VV LR11 R1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ; INC LR2 1 ;;
    LD.MULT.CYCLIC LR2 CR2 LR0 ; INC LR4 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR0 {{ cr.ones }} LR0 ;;
    MULT.RC.VE LR0 LR5 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ; INC LR2 1 ;;
    LD.MULT.CYCLIC LR2 CR2 LR0 ; INC LR4 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR0 {{ cr.ones }} LR0 ;;
    MULT.RC.VE LR0 LR5 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ; INC LR2 1 ;;
    INC.MODP2 LR3 LR15 7 ; INC LR8 1 ;;
    INC.MODP2 LR5 LR15 7 ; INC LR9 1 ;;
    INC LR4 1 ; BNE LR8 LR10 t_loop ;;
t_done:
    INC LR7 1 ; SET LR8 CR0 ;;
    BLT.S LR2 {{ cr.rf }} blk_loop ;;
    HALT ;;
{% else %}
blk_loop:
    SET LR6 CR0 ;;
    LD.MULT R0 LR7 CR3 ;;
e_loop:
    BGE.S LR2 {{ cr.rf }} e_done ;;
    SET LR5 CR14 ;;
j_loop:
{% if op == "mul" %}
    LD.MULT.CYCLIC LR2 CR2 LR0 ;;
    MULT.RC.VE LR0 LR6 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ; INC LR2 1 ;;
{% else %}
    LD.MULT.CYCLIC LR2 CR2 LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR0 {{ cr.ones }} LR0 ;;
    MULT.RC.VE LR0 LR6 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ; INC LR2 1 ;;
{% endif %}
    DEC LR5 1 ; INC LR4 1 ;;
    BNE LR5 CR0 j_loop ;;
e_done:
    INC LR6 1 ;;
    BLT.S LR6 LR11 e_loop ;;
    INC LR7 1 ;;
    BLT.S LR2 {{ cr.rf }} blk_loop ;;
    HALT ;;
{% endif %}
{% endif %}
    HALT ;;
