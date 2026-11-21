{# binary_mul_scalar_e2m5: out0 = in0 * operand, scalar broadcast, e2.

   Layout: dimension 1 (channels) runs along the 128 lanes, padded to a
   multiple of 128; dimensions 0, 2, 3 (batch, height, width) are in row
   order [0, 2, 3]. Each logical group (one (batch, height, width) cell)
   spans `chunks = ceil(dim1 / 128)` physical rows of 128 lanes. The first
   chunks-1 rows of a group are full (128 active lanes); the last row is
   the tail with `dim1 - (chunks-1)*128` active lanes.

   Streaming: R0 holds the decoded scalar. The template unrolls the chunk
   loop: it emits (chunks-1) full stores then one tail store, per physical
   group. LR1 walks the physical row index; LD.MULT.CYCLIC loads each row
   into cyclic slot 0, MULT.RC.VE multiplies by the scalar in FP32, and
   ACTIVATE.QUANTIZE rounds once to e2 on store. Inactive tail lanes are
   written zero. #}
{% set chunks = (numel // 4096 + 127) // 128 %}
    SET LR0 CR0 ;;
    LD.MULT R0 LR0 {{ cr.operand }} ;;
    SET LR1 CR0 ;;
loop:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.valid }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for c in range(chunks - 1) %}
    ACTIVATE.QUANTIZE identity {{ cr.valid }}.L {{ cr.qf }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.valid }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} loop ;;
    HALT ;;