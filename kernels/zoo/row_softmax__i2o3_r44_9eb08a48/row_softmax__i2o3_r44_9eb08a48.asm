{% set K = (n + 127) // 128 %}
    SET LR0 CR0 ;;
    SET LR2 CR0 ;;
    SET LR3 CR0 ;;
    SET LR7 LR15 ;;
transpose_batch:
    SET LR8 CR0 ;;
    SET LR9 CR0 ;;
    SET LR14 CR0 ;;
transpose_row:
    ADD LR4 LR2 LR14 ;;
    SET LR5 CR0 ;;
    SET LR6 CR0 ;;
    SET LR12 CR0 ;;
    SET LR13 CR0 ;;
    SET LR10 LR9 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
transpose_column:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.EE LR10 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD12 LRD12 7 ;;
    ADDBI LRD12 1 ;;
    ADD LR4 LR4 CR12 ;;
    INC LR5 1 ;;
    INC LR6 1 ;;
    SET LR11 CR0 ;;
    INC LR11 128 ;;
    BEQ LR6 LR11 transpose_store ;;
    SET LR11 CR0 ;;
    SET LR11 CR13 ;;
    BLT.S LR5 LR11 transpose_column ;;
transpose_store:
    SET LR11 CR0 ;;
    SET LR11 CR13 ;;
    BLT.S LR5 LR11 transpose_full ;;
    ACTIVATE.QUANTIZE identity CR14.L {{ cr.qf_in0 }}.L {{ cr.transposed }} LR3 ;;
    INC LR3 1 ;;
    B transpose_next ;;
transpose_full:
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_in0 }}.L {{ cr.transposed }} LR3 ;;
    INC LR3 1 ;;
    SET LR6 CR0 ;;
    SET LR12 CR0 ;;
    SET LR13 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    B transpose_column ;;
transpose_next:
    INC LR9 1 ;;
    SET LR11 CR0 ;;
    INC LR11 128 ;;
    BNE LR9 LR11 transpose_lane_ready ;;
    SET LR9 CR0 ;;
    INC LR14 1 ;;
transpose_lane_ready:
    INC LR8 1 ;;
    SET LR11 CR0 ;;
    SET LR11 LR1 ;;
    BLT.S LR8 LR11 transpose_row ;;
    ADD LR2 LR2 CR4 ;;
    DEC LR7 1 ;;
    BNE LR7 CR0 transpose_batch ;;
{% set cr = dict(qf=cr.qf_in0, qfo=cr.qf_out0, in0=cr.transposed, out0=cr.out0, tmp=cr.tmp, exps=cr.exps, K=cr.K, M=cr.M) %}
    SET LR0 CR0 ;;
    SET LR2 CR0 ;;
    SET LR9 CR0 ;;
    INC LR9 128 ;;
    SET LR1 CR0 ;;
    INC LR1 7 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE exp2 CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
{% for power, num, idx in [(5,23,8),(13,21,9),(19,18,10),(26,19,11),(32,23,14)] %}
    SET LR1 CR0 ;;
    INC LR1 7 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR6 CR0 ;;
    INC LR6 {{ power }} ;;
constant_power_{{ idx }}:
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    DEC LR6 1 ;;
    BNE LR6 CR0 constant_power_{{ idx }} ;;
    INC LR1 {{ idx - 7 }} ;;
    ACTIVATE.QUANTIZE exp2 CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR6 {{ num }} ;;
constant_num_{{ idx }}:
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    DEC LR6 1 ;;
    BNE LR6 CR0 constant_num_{{ idx }} ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
{% endfor %}
    SET LR1 CR0 ;;
    INC LR1 7 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR5 CR0 ;;
    INC LR5 126 ;;
epsilon_loop:
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    DEC LR5 1 ;;
    BNE LR5 CR0 epsilon_loop ;;
    INC LR1 5 ;;
    ACTIVATE.QUANTIZE exp2 CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
{% macro tiles(name) %}
    SET LR7 CR0 ;;
    SET LR8 {{ cr.K }} ;;
    DEC LR8 1 ;;
    BEQ LR7 LR8 {{ name }}_tail ;;
{{ name }}_full:
{{ caller('CR15.L', name ~ '_full') }}
    INC LR7 1 ;;
    BLT.S LR7 LR8 {{ name }}_full ;;
{{ name }}_tail:
{{ caller('CR14.L', name ~ '_tail') }}
{% endmacro %}
{% macro maximum(ds, first) %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf }}.L ; AGG.MAX{% if first %}.FIRST{% endif %} LR0 {{ ds }} ;;
    INC LR4 1 ;;
{% endmacro %}
row_loop:
    SET LR4 LR2 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% if K == 1 %}
{{ maximum('CR14.L', true) }}
{% else %}
{{ maximum('CR15.L', true) }}
    SET LR7 CR1 ;;
    SET LR8 {{ cr.K }} ;;
    DEC LR8 1 ;;
    BEQ LR7 LR8 max_tail ;;
max_full:
{{ maximum('CR15.L', false) }}
    INC LR7 1 ;;
    BLT.S LR7 LR8 max_full ;;
max_tail:
{{ maximum('CR14.L', false) }}
{% endif %}
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    SET LR3 CR0 ;;
    SET LR4 LR2 ;;
{% call(ds, tile) tiles('exp') %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.SUB ;;
    SET LR5 CR0 ;;
    INC LR5 15 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ cr.qf }}.L {{ cr.tmp }} LR5 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR5 1 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ cr.qf }}.L {{ cr.tmp }} LR5 ;;
    LD.MULT R1 LR5 {{ cr.tmp }} ;;
{% for idx in [8,9,10,11,14] %}
    SET LR5 CR0 ;;
    INC LR5 {{ idx }} ;;
    SET LR10 CR0 ;;
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR10 ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.{% if idx >= 11 %}SUB{% else %}ADD{% endif %}{% if idx == 8 %}.FIRST{% endif %} ;;
    MULT.RC.VV LR10 R1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.{% if idx >= 11 %}SUB{% else %}ADD{% endif %} ;;
{% endfor %}
    SET LR5 CR0 ;;
    INC LR5 12 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE exp2 {{ ds }} {{ cr.qf }}.L {{ cr.exps }} LR3 ;;
    LD.MULT R0 LR3 {{ cr.exps }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu {{ ds }} {{ cr.qf }}.L {{ cr.exps }} LR3 ;;
    INC LR4 1 ;;
    INC LR3 1 ;;
{% endcall %}
    SET LR3 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% call(ds, tile) tiles('sum') %}
    LD.MULT R0 LR3 {{ cr.exps }} ;;
    LD.MULT.CYCLIC LR3 {{ cr.exps }} LR9 ;;
    MULT.RC.VV LR9 R0 0 LR0 {{ ds }} {{ cr.qf }}.L ; AGG.SUM LR0 {{ ds }} ;;
    INC LR3 1 ;;
{% endcall %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.EE LR9 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE reciprocal CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    SET LR1 CR0 ;;
    INC LR1 7 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for j in [3,4] %}
    SET LR1 CR0 ;;
    INC LR1 {{ j }} ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR9 ;;
    SET LR5 CR0 ;;
    INC LR5 7 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR6 CR0 ;;
    INC LR6 16 ;;
sixteen_loop:
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    DEC LR6 1 ;;
    BNE LR6 CR0 sixteen_loop ;;
    INC LR5 10 ;;
    ACTIVATE.QUANTIZE reciprocal CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR5 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR5 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR5 ;;
    SET LR11 CR0 ;;
    INC LR11 128 ;;
    INC LR11 128 ;;
    INC LR11 128 ;;
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR11 ;;
    SET LR3 CR0 ;;
    SET LR4 LR2 ;;
{% call(ds, tile) tiles('store') %}
    LD.MULT R0 LR3 {{ cr.exps }} ;;
    SET LR10 CR0 ;;
    INC LR10 128 ;;
    INC LR10 128 ;;
    LD.MULT.CYCLIC LR3 {{ cr.exps }} LR10 ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR5 CR0 ;;
    INC LR5 13 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ cr.qf }}.L {{ cr.tmp }} LR5 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    LD.MULT R1 LR3 {{ cr.exps }} ;;
    MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR6 CR0 ;;
    INC LR6 16 ;;
residual_{{ tile }}:
    MULT.RC.VV LR10 R1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.SUB ;;
    DEC LR6 1 ;;
    BNE LR6 CR0 residual_{{ tile }} ;;
    INC LR5 2 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ cr.qf }}.L {{ cr.tmp }} LR5 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR9 R0 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.ADD ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.RC.VV LR11 R0 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE relu {{ ds }} {{ cr.qfo }}.L {{ cr.out0 }} LR4 ;;
    INC LR3 1 ;;
    INC LR4 1 ;;
{% endcall %}
    ADD LR2 LR2 {{ cr.K }} ;;
    BLT.S LR2 {{ cr.M }} row_loop ;;
    HALT ;;
