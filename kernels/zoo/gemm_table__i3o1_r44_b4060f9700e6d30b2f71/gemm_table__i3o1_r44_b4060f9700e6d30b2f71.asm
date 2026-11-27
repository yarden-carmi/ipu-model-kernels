{% macro coeff(slot='LR0') %}INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} {{ slot }}{% endmacro %}
{% macro mac(src, op='ACC.ADD', slot='LR0') %}MULT.RC.VE {{ slot }} {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ op }}{% endmacro %}
{% macro store(ds) %}INC LR3 1 ; ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3{% endmacro %}
    SET LR0 CR0 ; SET LR3 CR0 ; {% if not pair %}SET LR13 CR0{% else %}SET LR1 CR0{% endif %} ;;
    DEC LR3 1 ; SET LR11 CR0 ; SET LR12 {{ cr.blocks }} ;;
    {% if not pair %}SET LR5 CR0 ;;{% endif %}
{% for i in range(5) %}
    {% if i %}INC LR11 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR11 {% if pair and i == 0 %}; SET LR7 CR0{% endif %} ;;
{% endfor %}
{% if pair %}
{# Two short coefficient vectors share one cyclic row. #}
    INC LR1 128 ; INC LR7 64 ; SET LR11 CR0 ;;
    ADD LR4 LR1 LR1 ; SET LR14 {{ cr.pixels }} ; INC LR11 192 ;;
    ADD LR6 LR4 LR1 ; DEC LR14 1 ; SET LR5 CR0 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR4 ;;
    SET LR8 CR1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR6 ;;
group:
    SET LR9 CR0 ;;
pixel:
    SET LR8 CR1 ; SET LR2 LR5 ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
    {{ mac('CR1','ACC.ADD.FIRST','LR4') }} ; {{ coeff() }} ; ADD LR15 LR9 LR1 ;;
    {{ mac('CR1','ACC.ADD','LR6') }} ; {{ coeff('LR1') }} ;;
{% for p in range(k // 2) %}
    {{ mac('LR9') }} ; ADD LR2 LR2 {{ cr.blocks }} ; LD.MULT R1 LR2 {{ cr.in0 }} ;;
    {{ mac('LR9','ACC.ADD','LR1') }} {% if not loop.last %}; ADD LR2 LR2 {{ cr.blocks }} ; LD.MULT R0 LR2 {{ cr.in0 }}{% endif %} ;;
    {{ mac('LR15','ACC.ADD','LR7') }} {% if not loop.last %}; {{ coeff() }}{% endif %} ;;
    {{ mac('LR15','ACC.ADD','LR11') }} ; {% if loop.last %}{{ store(cr.tail) }} ; INC LR9 1 ; BLT.S LR9 LR14 pixel{% else %}{{ coeff('LR1') }}{% endif %} ;;
{% endfor %}
{% elif center %}
{# Reuse each four-tap spatial sum across all output channels. Keep the
   second tap panel resident in R1 while R0 alternates taps and sums. #}
{% macro gather(count, base, step, preload=false, first=false) %}
    SET LR4 LR14 ; SET LR5 LR15 ; {% if first %}SET LR2 LR13 ; {% endif %}LD.MULT R0 LR2 {{ base }} ;;
    SET LR6 LR14 ; SET LR7 LR15 ; ADDB LRD4 LR9 ;;
{% for t in range(count) %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD4 LRD6 0
    {%- if not loop.first %} ; ADDBI LRD6 8{% endif %}
    {%- if loop.last %} ; ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.panel }} LR11 {% if preload %}; SET LR8 CR1 ; LD.MULT R1 LR8 {{ cr.panel }}{% endif %}
    {%- else %} ; {{ step }} ; LD.MULT R0 LR2 {{ base }}{% endif %} ;;
{% endfor %}
{% endmacro %}
group:
    SET LR2 LR13 ; SET LR11 CR0 ; SET LR9 CR0 ;;
    INC LR11 1 ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
{% for g in range(8) %}
{% if not loop.first %}LD.MULT R0 LR2 {{ cr.in0 }} ;;{% endif %}
{% for t in range(4) %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ 'ACC.ADD.FIRST' if loop.first else 'ACC.ADD' }} ; ADD LR2 LR2 {{ cr.blocks }}
    {%- if loop.last %} ; ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.panel }} LR11 ; INC LR11 1
    {%- else %} ; LD.MULT R0 LR2 {{ cr.in0 }}{% endif %} ;;
{% endfor %}
{% endfor %}
    SET LR11 CR0 ;;
tile:
    {{ gather(16, cr.in0, 'ADD LR2 LR2 ' ~ cr.blocks, first=true) }}
    ADD LR2 LR2 {{ cr.blocks }} ; INC LR11 1 ;;
    {{ gather(16, cr.in0, 'ADD LR2 LR2 ' ~ cr.blocks) }}
    INC LR11 1 ;;
    SET LR2 LR11 ; INC LR11 8 ;;
    {{ gather(8, cr.panel, 'INC LR2 1', true) }}
    SET LR2 CR0 ; SET LR6 CR0 ; SET LR5 CR0 ; LD.MULT R0 LR0 {{ cr.panel }} ;;
    INC LR6 128 ; INC LR5 7 ;;
    ADD LR7 LR6 LR6 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR7 ;;
pixel:
    {{ mac('CR1', 'ACC.ADD.FIRST', 'LR7') }} ; SET LR8 CR1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; SET LR1 LR2 ;;
    {{ mac('CR1') }} ; {{ coeff() }} ;;
{% for p in range(3) %}
{% for t in range(8 if p == 2 else 16) %}
    {{ mac('LR4') }} ; SET LR4 LR1
    {%- if p == 2 and loop.last %} ; {{ store(cr.tail) }} ; INC LR2 1 ; LD.MULT R0 LR0 {{ cr.panel }} ; BLT.S LR2 LR5 pixel
    {%- else %} ; {{ coeff() }}
        {%- if not loop.last %} ; INC LR1 8
        {%- elif p == 0 %} ; ADD LR1 LR2 LR6
        {%- else %} ; SET LR1 LR2{% endif %}
    {%- endif %} ;;
{% endfor %}
{% if p == 0 %}LD.MULT R0 LR11 {{ cr.panel }} ;;{% endif %}
{% endfor %}
    INC LR9 8 ; SET LR11 CR0 ; SET LR5 LR13 ;;
    BLT.S LR9 {{ cr.pixels }} tile ;;
{% else %}
{% macro bias() %}
    {{ mac('CR1','ACC.ADD.FIRST') }} ; {{ coeff() }} ; DEC LR6 1 ;;
    {{ mac('CR1') }} ; LD.MULT R0 LR11 {{ cr.panel }} ; SET LR4 LR2 ;;
{% endmacro %}
{% macro taps(final) %}
{% for t in range(16) %}
    {% if (32 < k < 160 and k != 96 and (t < 12 if k == 64 else t >= 5)) or (k == 96 and t >= 4 and t != 5) %}
    {{ mac('LR4') }} ; {{ coeff() }} ;;
    {% endif %}
    {{ mac('LR4' if loop.last and final else 'LR5') }} {% if not loop.last %}; {{ coeff() }} ; SET LR5 LR4 ; INC LR4 8{% elif not final %}; LD.MULT R0 LR11 {{ cr.panel }} ; SET LR5 LR4 ; SET LR4 LR2{% elif k <= 160 %}; BNE LR6 CR0 full_store{% endif %} ;;
{% endfor %}
{% endmacro %}
{% if panelized %}
    SET LR1 CR0 ;;
    INC LR1 7 ;;
group:
    SET LR9 CR0 ;;
tile:
    SET LR4 LR14 ; SET LR5 LR15 ; SET LR2 LR13 ;;
    ADDB LRD4 LR9 ; SET LR11 CR0 ; SET LR8 {{ cr.k }} ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
gather:
    SET LR6 LR14 ; SET LR7 LR15 ;;
{% for t in range(16) %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD4 LRD6 0 ;
    {% if loop.last %}ADDBI LRD6 8 ; ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.panel }} LR11{% else %}ADD LR2 LR2 {{ cr.blocks }} ; LD.MULT R0 LR2 {{ cr.in0 }}{% if not loop.first %} ; ADDBI LRD6 8{% endif %}{% endif %} ;;
{% endfor %}
    INC LR11 1 ; DEC LR8 16 ;;
    BEQ LR8 CR0 gathered ;;
    ADD LR2 LR2 {{ cr.blocks }} ; LD.MULT R0 LR2 {{ cr.in0 }} ; B gather ;;
gathered:
    SET LR2 CR0 ;;
pixel:
    SET LR6 {{ cr.oc }} ; SET LR8 CR0 ;;
    DEC LR8 1 ;;
oc_block:
    SET LR11 CR0 ; SET LR7 {{ cr.k }} ; {{ coeff() }} ;;
    {{ bias() }}
{% if k <= 160 %}
{% for p in range(k // 16) %}
    {{ coeff() }} ; INC LR11 1 ;;
    {{ taps(loop.last) }}
{% endfor %}
{% else %}
panel_loop:
    {{ coeff() }} ; INC LR11 1 ; DEC LR7 16 ;;
    {{ taps(true) }}
    BEQ LR7 CR0 stored ;;
    LD.MULT R0 LR11 {{ cr.panel }} ; SET LR4 LR2 ; B panel_loop ;;
{% endif %}
stored:
    {% if k > 160 %}BNE LR6 CR0 full_store ;;{% endif %}
    {{ store(cr.tail) }} ; INC LR2 1 ; BLT.S LR2 LR1 pixel ;;
    INC LR9 8 ;;
    BLT.S LR9 {{ cr.pixels }} tile ;;
    SET LR5 LR13 ;;
    B advance ;;
full_store:
    {{ store(cr.full) }} ; B oc_block ;;
{% else %}
group:
    SET LR9 CR0 ;;
pixel:
    SET LR6 {{ cr.oc }} ; SET LR8 CR0 ;;
    DEC LR8 1 ;;
oc_block:
    SET LR2 LR5 ; {{ coeff() }} ;;
    {{ mac('CR1','ACC.ADD.FIRST') }} ; {{ coeff() }} ; DEC LR6 1 ;;
    {{ mac('CR1') }} ; LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR7 {{ cr.k }} ;;
tap_loop:
    {{ coeff() }} ; DEC LR7 1 ;;
    {{ mac('LR9') }} ; {{ coeff() }} ;;
    {{ mac('LR9') }} ; ADD LR2 LR2 {{ cr.blocks }} ; BEQ LR7 CR0 stored ;;
    LD.MULT R0 LR2 {{ cr.in0 }} ; B tap_loop ;;
stored:
    BNE LR6 CR0 full_store ;;
    {{ store(cr.tail) }} ; INC LR9 1 ; BLT.S LR9 {{ cr.pixels }} pixel ;;
    B advance ;;
full_store:
    {{ store(cr.full) }} ; B oc_block ;;
{% endif %}
{% endif %}
advance:
    INC LR5 1 ; DEC LR10 1 ; DEC LR12 1 ; BEQ LR10 CR1 end ;;
{% if pair %}
    BNE LR12 CR0 group ;;
    ADD LR5 LR5 {{ cr.skip }} ; SET LR12 {{ cr.blocks }} ; B group ;;
{% else %}
    BNE LR12 CR0 next_group ;;
    ADD LR5 LR5 {{ cr.skip }} ; SET LR12 {{ cr.blocks }} ;;
next_group:
    SET LR13 LR5 ; B group ;;
{% endif %}
end:
    HALT ;;
