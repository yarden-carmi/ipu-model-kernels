# out0 = cat(in0 / op0_const0, in1) along the lane dimension: out0 row (g, c) carries
# in0's row (g, c) and, in the tail chunk, in1's value at lane q = in0_d2 % 128.
#
# Rows (every tensor: lanes = dimension 2, rows in order [0, 1]):
#   in0 : in0_rows = groups * ic rows, group g chunk c at row g*ic + c
#   in1 : groups rows,  group g at row g (its one value in lane 0)
#   out0: out0_rows = groups * oc rows, group g chunk c at row g*oc + c
# with ic = ceil(in0_d2 / 128), oc = ceil((in0_d2 + 1) / 128), groups = in0_d0 * in0_d1.
#
# The factor 1/op0_const0 and the lane masks are constants in R_CYCLIC (fold makes
# them): slot 0 = 1/c on every lane (full chunks), slot 128 = 1/c on lanes 0..q-1
# only (the tail's in0 part, so in0's padding never reaches lane q), slot 256 = 1 at
# lane q only (MULT.RC.VE with src = Ra[128] = R1[0] puts in1[g] exactly there).
# Chunks ascend inside a group, groups ascend; a store always follows the load of the
# row it overwrites, so an output in place over an input stays correct.
{% set dsH = cr.ds_pair ~ '.H' %}
{% set dsL = cr.ds_pair ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set q1 = cr.qf_in1 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set fn = act_out0 | default('identity') %}

    SET LR15 CR0 ;;                                   {# zero: slot 0 window, mask shift #}
    SET LR14 {{ cr.full_lanes }} ;;                   {# 128: slot 128 window, Ra[128] #}
    ADD LR13 LR14 LR14 ;;                             {# 256: slot 256 window #}
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;        {# in0 row, out0 row, group #}
    LD.MULT.CYCLIC LR15 {{ cr.constfull }} LR15 ;;    {# 1/c on all lanes #}
    LD.MULT.CYCLIC LR15 {{ cr.consttail }} LR14 ;;    {# 1/c on lanes 0..q-1 #}
    LD.MULT.CYCLIC LR15 {{ cr.onehot }} LR13 ;;       {# 1 at lane q #}
    SET LR3 CR0 ;;
group:
    SET LR3 CR0 ;;
chunk:
    BGE.S LR3 {{ cr.ocm1 }} tail ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.RC.VV LR15 R0 0 LR15 {{ dsH }} {{ qi }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE {{ fn }} {{ dsH }} {{ qo }} {{ cr.out0 }} LR5 ;;
    INC LR4 1 ; INC LR5 1 ; INC LR3 1 ;;
    B chunk ;;
tail:
    LD.MULT R1 LR6 {{ cr.in1 }} ; BEQ {{ cr.gstep }} CR0 extra ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.RC.VV LR14 R0 0 LR15 {{ dsH }} {{ qi }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR13 LR14 0 LR15 {{ dsH }} {{ q1 }} ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ fn }} {{ dsL }} {{ qo }} {{ cr.out0 }} LR5 ;;
    INC LR4 1 ; INC LR5 1 ;;
    B gend ;;
extra:
    MULT.RC.VE LR13 LR14 0 LR15 {{ dsH }} {{ q1 }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE {{ fn }} {{ dsL }} {{ qo }} {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
gend:
    INC LR6 1 ;;
    BLT.S LR6 {{ cr.groups }} group ;;
    HALT ;;
