{# LR1 selects the spatial element in the packed row; LR2 selects its row
   within a channel. Each subsequent channel is one pitch farther away. #}
{% macro coeff_mac(src, acc, ctrl='') %}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_coeff }}.L ; {{ acc }} ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1 {{ ctrl }} ;;
{% endmacro %}
{% macro spatial_channel(last) %}
    LD.MULT R0 LR5 {{ cr.in0 }} ; ADD LR5 LR5 {{ cr.pitch }} ;;
    {{ coeff_mac('LR1', 'ACC.ADD') }}
    {% if last %}
    MULT.RC.VE LR0 LR7 0 LR0 {{ cr.full }}.L {{ cr.qf_coeff }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.last }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ; SET LR7 LR1 ; INC LR1 1 ; BLT.S LR1 {{ cr.group_last }} packed_pixel ;;
    {% else %}
    {{ coeff_mac('LR1', 'ACC.ADD') }}
    {% endif %}
{% endmacro %}
{% if paired %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR9 CR0 ;;
    INC LR9 128 ; DEC LR3 1 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR9 ;;
packed_pixel:
    MULT.RC.VE LR9 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_coeff }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; SET LR8 CR1 ; SUB LR5 LR2 {{ cr.pitch }} ;;
    {% for channel in range(k) %}
    {{ spatial_channel(loop.last) }}
    {% endfor %}
    SET LR1 CR0 ; INC LR2 1 ; BLT.S LR3 {{ cr.tile_or_last }} packed_pixel ;;
    HALT ;;
{% else %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ;;
    DEC LR3 1 ;;
spatial:
    SET LR8 CR0 ; SET LR6 CR0 ;;
    LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ;;
tile:
    SUB LR5 LR2 {{ cr.pitch }} ; SET LR7 CR0 ;;
    {{ coeff_mac('CR1', 'ACC.ADD.FIRST') }}
channel:
    LD.MULT R0 LR5 {{ cr.in0 }} ; ADD LR5 LR5 {{ cr.pitch }} ; INC LR7 1 ;;
    {{ coeff_mac('LR1', 'ACC.ADD', '; BLT.S LR7 ' ~ cr.k ~ ' channel') }}
    BLT.S LR6 {{ cr.tile_or_last }} store_full ;;
    {{ store(cr.last) }}
    INC LR4 1 ; INC LR1 1 ;;
    BLT.S LR4 {{ cr.m }} advance ;;
    HALT ;;
advance:
    BLT.S LR1 {{ cr.group }} spatial ;;
    SET LR1 CR0 ; INC LR2 1 ; BNE CR1 CR0 spatial ;;
store_full:
    {{ store(cr.full) }}
    INC LR6 1 ; BNE CR1 CR0 tile ;;
{% endif %}
