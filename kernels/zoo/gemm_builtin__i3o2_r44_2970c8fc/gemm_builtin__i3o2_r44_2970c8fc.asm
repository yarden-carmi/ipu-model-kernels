{% macro coeff(reg) %}LD.MULT {{ reg }} LR11 {{ cr.w }} ; INC LR11 1 ;;{% endmacro %}
{% macro mac(src, mode) %}MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}{% endmacro %}
{% macro bias_row(mode) %}LD.MULT.CYCLIC LR11 {{ cr.w }} LR0 ; INC LR11 1 ;; {{ mac('CR1', mode) }} ;;{% endmacro %}
{% macro load_input() %}LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ; ADD LR4 LR4 {{ cr.tiles }}{% endmacro %}
{% macro pass(label) %}
    SET LR2 CR0 ; SET LR3 LR1 ;;
{% if k % 128 %}
    BNE LR14 CR1 {{ label }}_coeff ;;
    SET LR3 CR0 ;;
    INC LR3 {{ k % 128 }} ;;
{{ label }}_coeff:
{% endif %}
    {{ coeff('R0') }}
    {{ coeff('R1') }}
    {{ load_input() }} ; DEC LR3 1 ;;
{{ label }}_reduce:
    {{ mac('LR2', 'ADD') }} ;;
    {{ mac('LR2', 'ADD') }} ; ADD LR2 LR2 LR1 ; BLT.S LR2 LR3 {{ label }}_next ;;
    B {{ label }}_end ;;
{{ label }}_next:
    {{ load_input() }} ; DEC LR2 127 ; B {{ label }}_reduce ;;
{{ label }}_end:
{% endmacro %}
{% macro store() %}
{% for i in range(4) %}
    ACTIVATE.QUANTIZE identity {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L {{ cr.tmp }} LR5 ; INC LR5 1 ;;
{% if not loop.last %}
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ;;
{% endif %}
{% endfor %}
    INC LR12 1
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    INC LR1 128 ; SET LR8 CR0 ; SET LR15 CR0 ;;
    INC LR15 {{ out0_d0 }} ;;
    DEC LR5 1 ;;
batch:
    SET LR13 {{ cr.in0_d2 }} ;;
row:
    SET LR9 CR0 ; SET LR6 {{ cr.n }} ;;
channel:
    SET LR12 LR8 ; SET LR7 {{ cr.tiles }} ;;
tile:
    SET LR11 LR9 ; SET LR4 LR12 ; SET LR14 CR0 ;;
    INC LR14 {{ chunks }} ; DEC LR11 1 ; SUB LR4 LR4 {{ cr.tiles }} ;;
    {{ bias_row('ADD.FIRST') }}
    {{ bias_row('ADD') }}
    {{ bias_row('ADD') }}
    {{ bias_row('ADD') }}
chunk:
    {{ pass('first') }}
{% if k % 128 %}
    BNE LR14 CR1 rewind_full ;;
    DEC LR4 {{ k % 128 }} ; B rewind_done ;;
rewind_full:
{% endif %}
    DEC LR4 128 ;;
rewind_done:
    {{ pass('second') }}
    DEC LR14 1 ; BNE LR14 CR1 chunk ;;
    MULT.VE LR0 CR0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.MAX ;;
    BNE LR7 CR1 full_tile ;;
    {{ store() }} ;;
    ADD LR9 LR11 CR1 ; DEC LR6 1 ; BNE LR6 CR1 channel ;;
    ADD LR8 LR8 {{ cr.row_stride }} ; DEC LR13 1 ; BNE LR13 CR1 row ;;
    DEC LR15 1 ; BNE LR15 CR1 batch ;;
    B transpose ;;
full_tile:
    {{ store() }} ; DEC LR7 1 ; B tile ;;
transpose:
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    SET LR14 CR0 ;;
    INC LR14 {{ out0_d0 }} ;;
transpose_batch:
    SET LR2 LR1 ; SET LR15 {{ cr.n }} ;;
transpose_channel:
    SET LR10 CR0 ; SET LR4 CR0 ;;
    INC LR4 {{ out0_d3 }} ;;
transpose_column:
{% for plane in range(4) %}
    SET LR6 LR2 ; SET LR8 {{ cr.in0_d2 }} ; SET LR12 CR0 ;;
    SET LR13 CR0 ;;
{% if plane %}    INC LR6 {{ plane }} ;;{% endif %}
transpose_row_{{ plane }}:
    LD.MULT R0 LR6 {{ cr.tmp }} ;;
    MULT.EE LR10 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD12 LRD12 7 ;;
    ADDBI LRD12 1 ; ADD LR6 LR6 {{ cr.tmp_pitch }} ; DEC LR8 1 ;;
    BNE LR8 CR0 transpose_row_{{ plane }} ;;
    SET LR5 CR0 ;;
{% if plane %}    INC LR5 {{ plane * 2 }} ;;{% endif %}
    ACTIVATE.QUANTIZE identity {{ cr.y_tail }}.L {{ cr.qf_in0 }}.L {{ cr.trans }} LR5 ;;
    LD.MULT R0 LR5 {{ cr.trans }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ; INC LR5 1 ;;
    ACTIVATE.QUANTIZE identity {{ cr.y_tail }}.L {{ cr.qf_in0 }}.L {{ cr.trans }} LR5 ;;
{% endfor %}
{% for plane in range(8) %}
    SET LR5 CR0 ;;
{% if plane %}    INC LR5 {{ plane }} ;;{% endif %}
    LD.MULT R0 LR5 {{ cr.trans }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if loop.first %}.FIRST{% endif %}{% if loop.last %} ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.y_tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3{% endif %} ;;
{% endfor %}
    INC LR3 1 ; INC LR10 1 ; DEC LR4 1 ;;
    BNE LR4 CR0 transpose_column ;;
    INC LR2 4 ; DEC LR15 1 ;;
    BNE LR15 CR0 transpose_channel ;;
    SUB LR1 LR6 {{ cr.tmp_pitch }} ; DEC LR14 1 ;;
    INC LR1 1 ; BNE LR14 CR0 transpose_batch ;;
    HALT ;;
