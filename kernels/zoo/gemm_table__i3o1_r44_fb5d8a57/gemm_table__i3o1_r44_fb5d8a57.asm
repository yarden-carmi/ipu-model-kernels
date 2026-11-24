{# Each input row holds x in the lanes; each coefficient row holds output channels. #}
{% macro next_coeff() %}
    INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0
{% endmacro %}
{% macro mac(src, op='ACC.ADD') %}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; {{ op }}
{% endmacro %}
{% macro store(ds) %}
    INC LR3 1 ; ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3
{% endmacro %}

    SET LR0 CR0 ; SET LR3 CR0 ; SET LR5 CR0 ;;
    SET LR11 CR0 ; DEC LR3 1 ; SET LR12 {{ cr.in0_d2 }} ;;
    SET LR10 {{ cr.stripes }} ;;
{% for i in range(5) %}
    {% if i %}INC LR11 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR11 ;;
{% endfor %}
stripe:
    SET LR9 CR0 ;;
pixel:
    SET LR8 CR0 ; SET LR6 {{ cr.blocks }} ;;
    DEC LR8 1 ;;
block:
    SET LR2 LR5 ; SET LR7 {{ cr.k }} ; {{ next_coeff() }} ;;
    {{ mac('CR1', 'ACC.ADD.FIRST') }} ; {{ next_coeff() }} ; DEC LR6 1 ;;
    {{ mac('CR1') }} ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
channel:
    {{ next_coeff() }} ; ADD LR2 LR2 {{ cr.in0_d2 }} ;;
    {{ mac('LR9') }} ; {{ next_coeff() }} ; DEC LR7 1 ;;
    BNE LR7 CR0 more_channels ;;
    {{ mac('LR9') }} ; BNE LR6 CR0 full_store ;;
    {{ store(cr.tail_ds) }} ; INC LR9 1 ;;
    BLT.S LR9 {{ cr.in0_d3 }} pixel ;;
    INC LR5 1 ; DEC LR10 1 ; DEC LR12 1 ;;
    BEQ LR10 CR0 end ;;
    BNE LR12 CR0 stripe ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; SET LR12 {{ cr.in0_d2 }} ; B stripe ;;
end:
    HALT ;;
more_channels:
    {{ mac('LR9') }} ; LD.MULT R0 LR2 {{ cr.in0 }} ; B channel ;;
full_store:
    {{ store(cr.full_ds) }} ; B block ;;
