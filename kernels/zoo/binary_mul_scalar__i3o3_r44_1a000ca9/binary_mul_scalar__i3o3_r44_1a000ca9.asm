{% macro multiply(offset, acc) -%}
    MULT.RC.VE {{ offset }} LR0 0 LR0 {{ cr.ds_single }}.H {{ cr.qf_in0 }}.L ; ACC.{{ acc }}
{%- endmacro %}
{% macro scalar_part(coef, acc) -%}
    MULT.VE LR0 {{ coef }} 0 LR0 {{ cr.ds_single }}.H {{ cr.qf_in0 }}.L ; ACC.{{ acc }}
{%- endmacro %}
{% macro store(ds) -%}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    {{ scalar_part('CR0', 'ADD.FIRST') }} ; ACTIVATE.QUANTIZE exp2 {{ cr.ds_single }}.H {{ cr.qf_in0 }}.L {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ; DEC LR1 1 ; DEC LR2 1 ; INC LR7 128 ;;
    {{ scalar_part(cr.fp_hi, 'ADD.FIRST') }} ;;
    {{ scalar_part(cr.fp_lo, 'SUB') }} ;;
    {{ scalar_part(cr.scale, 'ADD') }} ; ACTIVATE.QUANTIZE identity {{ cr.ds_single }}.H {{ cr.qf_in0 }}.L {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    SET LR3 {{ cr.groups }} ; SET LR4 {{ cr.pair_shift }} ; SET LR6 {{ cr.pack }} ; BEQ LR6 CR1 unpacked ;;
packed:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ; INC LR1 1 ; DEC LR3 1 ; BEQ LR3 CR1 odd_row ;;
    {{ multiply('LR0', 'ADD.FIRST') }} ; LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR7 ; INC LR1 1 ; DEC LR3 1 ;;
    # Start in the first row's zero padding so the second begins at lane in0_d3.
    {{ multiply('LR4', 'ADD') }} ; {{ store(cr.ds_pair ~ '.L') }} ; INC LR2 1 ; BNE LR3 CR0 packed ;;
    HALT ;;
odd_row:
    {{ multiply('LR0', 'ADD.FIRST') }} ; {{ store(cr.ds_single ~ '.L') }} ; INC LR2 1 ; HALT ;;

unpacked:
    SET LR5 {{ cr.chunks }} ;;
chunk:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ; INC LR1 1 ; DEC LR5 1 ; BEQ LR5 CR1 tail ;;
    {{ multiply('LR0', 'ADD.FIRST') }} ; {{ store(cr.ds_single ~ '.H') }} ; INC LR2 1 ; B chunk ;;
tail:
    {{ multiply('LR0', 'ADD.FIRST') }} ; {{ store(cr.ds_single ~ '.L') }} ; INC LR2 1 ; DEC LR3 1 ; BNE LR3 CR1 unpacked ;;
    HALT ;;
