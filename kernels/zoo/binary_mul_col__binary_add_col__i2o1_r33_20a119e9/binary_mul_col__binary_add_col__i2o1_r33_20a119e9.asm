{# One row of 128 lanes: out = in0 * c0 + c1, lane-wise; c0/c1 are the same padded
   constant row 0 for every row (broadcast col), so the add is c1 x 1.0 through MULT.VE.
   in0 row r and out0 row r hold the same view elements (in0: dim 2 along the lanes,
   rows [0, 1]; out0: dim 1 along the lanes, rows [0, 2]), so LR2 serves both: it is
   the load row offset, and LR3 the store row offset, started at -1 because its INC
   lives in the row's first word, off the store's word (AAQ sees the same word's INC).
   Loop nest: i0 (in0_d0) -> k (in0_d1) -> chunks of 128 lanes (cb full .H rows, then
   one tail .L row with in0_d2 - 128*(cb-1) valid lanes).
   Pipeline: load in0 -> load c0 into R_CYCLIC slot 0 -> mul (ACC.ADD.FIRST) with the
   c1 load -> add pass of c1 (ACC.ADD) and store, the four words overlap across rows. #}
{% macro row(ds, tail_op, cnt_op) %}
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR3 1 ;;
    LD.MULT.CYCLIC LR0 {{ cr.c0 }} LR0 ; INC LR2 1 ;;
    LD.MULT R1 LR0 {{ cr.c1 }} ; MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ cnt_op }} ;;
    MULT.VE LR1 CR1 0 LR0 {{ ds }} {{ cr.qf_c1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; {{ tail_op }} ;;
{% endmacro %}

    SET LR0 CR0 ;;
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    INC LR1 128 ; DEC LR3 1 ; SET LR8 CR0 ;;
    INC LR8 1 ; SET LR9 {{ cr.in0_d0 }} ;;
i0:
    SET LR5 CR0 ;;
k:
    SET LR4 {{ cr.cb }} ;;
    BEQ LR4 LR8 tail ;;
chunk:
    {{ row(cr.ds_pair ~ '.H', 'BNE LR4 LR8 chunk', 'DEC LR4 1') }}
tail:
    {{ row(cr.ds_pair ~ '.L', 'BLT.S LR5 ' ~ cr.in0_d1 ~ ' k', 'INC LR5 1') }}
    DEC LR9 1 ;;
    BNE LR9 CR0 i0 ;;
    HALT ;;
