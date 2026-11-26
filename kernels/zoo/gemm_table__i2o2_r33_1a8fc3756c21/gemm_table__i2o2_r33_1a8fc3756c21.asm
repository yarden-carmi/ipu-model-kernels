{% macro coeff() -%}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1
{%- endmacro %}
{% macro mac(more) %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR3 1 {% if more %}; {{ coeff() }} ; BLT.S LR3 LR7 taps{% endif %} ;;
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE generic {{ cr.ds_pair }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endmacro %}
{% macro lut_row(i) %}
    LD.LUT {{ i }} {{ cr.lut }} LR10 ;;
    INC LR10 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR10 CR0 ;;
    SET LR8 CR0 ; SET LR12 {{ cr.in0_d0 }} ; DEC LR5 1 ;;
{% for i in range(5) %}
    {{ lut_row(i) }}
{% endfor %}
batch:
    SET LR11 {{ cr.in0_d1 }} ; SET LR13 CR0 ;;
row:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ; SET LR1 CR0 ;;
    DEC LR4 1 ; DEC LR1 1 ;;
tile:
    SET LR2 LR8 ; SET LR3 LR13 ; ADD LR9 LR13 {{ cr.k }} ;;
{% if bias %}
    LD.MULT R0 LR1 {{ cr.b }} ; INC LR1 1 ;;
{% endif %}
    MULT.VE LR0 {{ 'CR1' if bias else 'CR0' }} 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; DEC LR6 1 ;;
    # LR2/LR3 locate the input row/lane; LR9 is the exclusive end relative to that row.
chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ; DEC LR3 1 ; SET LR7 {{ cr.lanes }} ; BLT.S {{ cr.lanes }} LR9 bound ;;
    SET LR7 LR9 ;;
bound:
    DEC LR7 3 ;;
    {{ coeff() }} ; BLT.S LR7 LR3 last_tap ;;
taps:
    {{ mac(true) }}
last_tap:
    {{ mac(false) }}
    BLT.S {{ cr.lanes }} LR9 next_chunk ;;
    BEQ LR6 CR0 last_tile ;;
    {{ store('L') }}
    B tile ;;
next_chunk:
    INC LR2 1 ; SET LR3 CR0 ; SUB LR9 LR9 {{ cr.lanes }} ; B chunk ;;
last_tile:
    {{ store('H') }}
    SET LR8 LR2 ; SET LR13 LR9 ; DEC LR11 1 ; BLT.S LR9 {{ cr.lanes }} row_end ;;
    INC LR8 1 ; SET LR13 CR0 ;;
row_end:
    BNE LR11 CR0 row ;;
    # Discard only the padding at the end of each batch.
    DEC LR12 1 ; BEQ LR13 CR0 batch_end ;;
    INC LR8 1 ;;
batch_end:
    BNE LR12 CR0 batch ;;
    HALT ;;
