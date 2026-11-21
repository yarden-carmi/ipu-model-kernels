{#- bmm: out[h, m, n] = sum_k in0[h, m, k] * in1[h, k, n], one head at a time.
    in0 row (h*k + kk) holds lanes m; in1 row (h*k + kk) holds lanes n. For each (h, n) the
    accumulator over kk is in0-row times the in1 element at lane n (read from R0 by the LR n).
    The output row (h*n + nn) holds lanes m; the store's partial DS (.H) zeroes its pad lanes. -#}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR4 CR0 ;;
head:
    SET LR3 CR0 ;;
col:
    SET LR5 CR0 ; ADD LR6 LR1 CR0 ;;
{% macro product(first) %}
    LD.MULT R0 LR6 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.dsfull }}.H {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; INC LR5 1 ; INC LR6 1 ;;
{% endmacro %}
    {{ product(true) }}
kloop:
    BLT.S LR5 {{ cr.k }} kbody ;;
    B kdone ;;
kbody:
    {{ product(false) }}
    B kloop ;;
kdone:
    ACTIVATE.QUANTIZE identity {{ cr.dsfull }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.n }} col ;;
    ADD LR1 LR1 {{ cr.k }} ; INC LR4 1 ;;
    BLT.S LR4 {{ cr.b }} head ;;
    HALT ;;
