{#- binary_mul_scalar on a heads view: out0[b,h,s,:] = in0[b,s,h*D:(h+1)*D] * scalar.
    in0 is [B, S, L] with L along lanes (ic chunks of 128 per row); out0 rows (b,h,s) of D lanes, pad 0.
    The scalar is broadcast from R0.
    Crossing windows ping-pong between cyclic slot pairs. Single-chunk windows
    prefetch the next row in the multiply/store word. -#}
{% macro product(window) %}
    MULT.RC.VE {{ window }} LR0 0 LR0 {{ cr.tail }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;
    INC LR1 1 ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;
{% endmacro %}
{% macro crossing(window, next_first, next_second, loop, drain) %}
    ADD LR7 LR7 LR15 ; LD.MULT.CYCLIC LR7 {{ cr.in0 }} {{ next_first }} ;;
    {{ product(window) }} ADD LR14 LR14 LR15 ; LD.MULT.CYCLIC LR14 {{ cr.in0 }} {{ next_second }} ;
    DEC LR6 1 ; BLT.S CR1 LR6 {{ loop }} ;;
    B {{ drain }} ;;
{% endmacro %}
    SET LR1 CR0 ;;
    DEC LR1 1 ;;
    SET LR0 CR0 ; SET LR2 CR0 ;;
    SET LR10 CR0 ; SET LR8 CR0 ;;
    INC LR8 128 ;;
    # Form a row of ones, then generate rsqrt(head width) in the active format.
    MULT.VE LR0 CR0 0 LR0 {{ cr.tail }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ cr.tail }}.L {{ cr.qf_in0 }}.L {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    MULT.VE LR0 {{ cr.fp_top }} 0 LR0 {{ cr.tail }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR0 {{ cr.fp_base }} 0 LR0 {{ cr.tail }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ;;
    MULT.VE LR0 {{ cr.head_width }} 0 LR0 {{ cr.tail }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE rsqrt {{ cr.tail }}.L {{ cr.qf_in0 }}.L {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    ADD LR9 LR8 LR8 ;;
    ADD LR11 LR9 LR8 ;;
batch:
    SET LR5 CR0 ; SET LR4 CR0 ; SET LR3 CR0 ;;
head:
    ADD LR7 LR10 LR3 ; SET LR6 {{ cr.out0_d2 }} ;;
    DEC LR6 1 ; LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ; BGE.S {{ cr.wrap_limit }} LR4 single_head ;;
    ADD LR14 LR7 CR1 ; LD.MULT.CYCLIC LR14 {{ cr.in0 }} LR8 ;;
    ADD LR12 LR4 LR9 ; BEQ LR6 CR0 drain_a ;;
cross_a:
    {{ crossing('LR4', 'LR9', 'LR11', 'cross_b', 'drain_b') }}
cross_b:
    {{ crossing('LR12', 'LR0', 'LR8', 'cross_a', 'drain_a') }}
drain_b:
    {{ product('LR12') }} B head_done ;;
single_head:
    BEQ LR6 CR0 drain_a ;;
single_row:
    {{ product('LR4') }} ADD LR7 LR7 LR15 ; LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ; DEC LR6 1 ; BLT.S CR1 LR6 single_row ;;
drain_a:
    {{ product('LR4') }} ;;
head_done:
    # The branch sees the old lane offset, before the modular increment.
    INC LR5 1 ; INC.MODP2 LR4 LR13 7 ; BGE.S LR4 {{ cr.wrap_limit }} wrapped ;;
    BLT.S LR5 {{ cr.out0_d1 }} head ;;
batch_done:
    ADD LR10 LR10 {{ cr.brows }} ; INC LR2 1 ;;
    BLT.S LR2 {{ cr.out0_d0 }} batch ;;
    HALT ;;
wrapped:
    INC LR3 1 ; BLT.S LR5 {{ cr.out0_d1 }} head ;;
    B batch_done ;;
