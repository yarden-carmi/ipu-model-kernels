{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ {'silu': 'generic'}[act_out0] }} {{ cr.ds_pair }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endmacro %}
{% macro lut_row(i) %}
    LD.LUT {{ i }} {{ cr.lut }} LR10 ;;
    INC LR10 1 ;;
{% endmacro %}
{% macro mac(next) %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; ACC.ADD {% if next %}; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ; B tap {% endif %};;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR10 CR0 ;;
    SET LR8 CR0 ; SET LR3 CR0 ; SET LR11 {{ cr.m }} ;;
    DEC LR5 1 ; SET LR14 CR0 ; SET LR13 LR15 ;;
{% for i in range(5) %}
    {{ lut_row(i) }}
{% endfor %}
row:
    # Input position s*d0+b is split into row offset LR8 and lane LR3.
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ; SET LR1 CR0 ;;
    DEC LR4 1 ; DEC LR1 1 ;;
tile:
    SET LR2 LR8 ; SET LR7 {{ cr.k }} ; DEC LR6 1 ;;
{% if bias %}
    LD.MULT R0 LR1 {{ cr.b }} ; INC LR1 1 ;;
{% endif %}
    MULT.VE LR0 {{ 'CR1' if bias else 'CR0' }} 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
tap:
    # Each reduction tap advances one full slab of packed input positions.
    LD.MULT R0 LR2 {{ cr.in0 }} ; DEC LR7 1 ; BEQ LR7 CR1 final_tap ;;
    ADD LR2 LR2 {{ cr.stride }} ; {{ mac(true) }}
final_tap:
    {{ mac(false) }}
    BEQ LR6 CR0 last_tile ;;
    {{ store('L') }}
    B tile ;;
last_tile:
    {{ store('H') }}
    ADD LR3 LR3 {{ cr.in0_d0 }} ; DEC LR11 1 ; DEC LR13 1 ;;
    BEQ LR11 CR0 done ;;
    BEQ LR13 CR0 next_batch ;;
    BLT.S LR3 {{ cr.lanes }} row ;;
    SUB LR3 LR3 {{ cr.lanes }} ; INC LR8 1 ; B row ;;
next_batch:
    INC LR14 1 ; SET LR13 LR15 ; SET LR8 CR0 ;;
    SET LR3 LR14 ; B row ;;
done:
    HALT ;;
