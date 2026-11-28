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
    DEC LR3 1 ; SET LR11 CR0 ; SET LR12 {{ cr.plane }} ;;
{% for i in range(5) %}
    {% if i %}INC LR11 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR11 ;;
{% endfor %}

{% if narrow_pair %}
{# Each coefficient row carries two adjacent 64-lane taps. Keep the two
   input rows in R0/R1 so the narrow case never requantizes input pixels. #}
{% macro pair_mac(slot, src, op='ACC.ADD') %}
    MULT.RC.VE {{ slot }} {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; {{ op }}
{% endmacro %}
{% macro pair_coeff(slot) %}
    INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} {{ slot }}
{% endmacro %}
    INC LR1 128 ; INC LR7 64 ; SET LR11 CR0 ;;
    ADD LR4 LR1 LR1 ; SET LR14 {{ cr.pixels }} ; INC LR11 192 ;;
    ADD LR6 LR4 LR1 ; DEC LR14 1 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR4 ;;
    SET LR8 CR1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR6 ;;
pair_group:
    SET LR9 CR0 {% if short_pair %}; SET LR8 CR1 ; LD.MULT R0 LR5 {{ cr.in0 }}{% endif %} ;;
pair_pixel:
    {% if not short_pair %}SET LR8 CR1 ; SET LR2 LR5 ; LD.MULT R0 LR2 {{ cr.in0 }} ;;{% endif %}
    {{ pair_mac('LR4', 'CR1', 'ACC.ADD.FIRST') }} ; {{ pair_coeff('LR0') }} ; ADD LR15 LR9 LR1 {% if short_pair %}; SET LR2 LR5{% endif %} ;;
    {{ pair_mac('LR6', 'CR1') }} ; {{ pair_coeff('LR1') }} ;;
{% for pair in range(k // 2) %}
    {{ pair_mac('LR1' if short_pair and loop.last else 'LR0', 'LR9') }} ; ADD LR2 LR2 {{ cr.plane }} ; LD.MULT R1 LR2 {{ cr.in0 }} ;;
    {{ pair_mac('LR11' if short_pair and loop.last else 'LR7' if short_pair and pair == 6 else 'LR1', 'LR15' if short_pair and pair >= 6 else 'LR9') }} {% if not loop.last %}; ADD LR2 LR2 {{ cr.plane }} ; LD.MULT R0 LR2 {{ cr.in0 }}{% elif short_pair %}; {{ store(cr.tail_ds) }} ; INC LR9 1 ; SET LR8 CR1 ; LD.MULT R0 LR5 {{ cr.in0 }} ; BLT.S LR9 LR14 pair_pixel{% endif %} ;;
    {% if not short_pair or pair < 6 %}
    {{ pair_mac('LR7', 'LR15') }} {% if not loop.last %}; {{ pair_coeff('LR0') }}{% endif %} ;;
    {{ pair_mac('LR11', 'LR15') }} {% if loop.last %}; {{ store(cr.tail_ds) }} ; INC LR9 1 ; BLT.S LR9 LR14 pair_pixel{% else %}; {{ pair_coeff('LR1') }}{% endif %} ;;
    {% endif %}
{% endfor %}
    INC LR5 1 ; DEC LR10 1 ; DEC LR12 1 ; BEQ LR10 CR1 pair_end ;;
    BNE LR12 CR0 pair_group ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; SET LR12 {{ cr.plane }} ; B pair_group ;;
pair_end:
    HALT ;;
{% elif n <= 64 and k <= 32 and not packed %}
{# Keep both bias components in cyclic slots and stream the original input
   rows. This avoids a second quantization for the narrow output tile. #}
{% macro bias_mac(slot, op) %}
    MULT.RC.VE {{ slot }} CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; {{ op }}
{% endmacro %}
    INC LR1 128 ; SET LR14 {{ cr.pixels }} ;;
    DEC LR14 1 ; ADD LR4 LR1 LR1 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR1 ;;
    SET LR8 CR1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR4 ;;
narrow_group:
    SET LR9 CR0 ;;
narrow_pixel:
    {{ bias_mac('LR1', 'ACC.ADD.FIRST') }} ; SET LR2 LR5 ; SET LR8 CR1 ; SET LR13 LR9 ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
    {{ bias_mac('LR4', 'ACC.ADD') }} ; {{ next_coeff() }} ;;
{% for tap in range(k) %}
    {{ mac('LR13') }} ; {{ next_coeff() }} ;;
    {% if not loop.last %}
    {{ mac('LR13') }} ; ADD LR2 LR2 {{ cr.plane }} ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
    {{ next_coeff() }} ;;
    {% else %}
    {{ mac('LR13') }} ; {{ store(cr.tail_ds) }} ; INC LR9 1 ; BLT.S LR9 LR14 narrow_pixel ;;
    {% endif %}
{% endfor %}
    INC LR5 1 ; DEC LR10 1 ; DEC LR12 1 ; BEQ LR10 CR1 narrow_end ;;
    BNE LR12 CR0 narrow_group ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; SET LR12 {{ cr.plane }} ; B narrow_group ;;
narrow_end:
    HALT ;;
{% elif center64 %}
{# Stage sixteen channels for eight pixels per panel row. #}
    SET LR1 CR0 ;;
    INC LR1 128 ;;
center_group:
{% set chunks = [8] * 8 %}
    SET LR2 LR5 ; SET LR11 CR0 ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
    {{ 'DEC LR11 1' if center_full else 'INC LR11 4' }} ;;
{% for chunk in range(chunks|length) %}
{% for tap in range(chunks[chunk]) %}
    {% set end_sum = loop.last %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; {{ 'ACC.ADD.FIRST' if loop.first else 'ACC.ADD' }}
    {% if not (chunk == chunks|length - 1 and loop.last) %}; ADD LR2 LR2 {{ cr.plane }} ; LD.MULT R0 LR2 {{ cr.in0 }}{% endif %}
    {% if end_sum %}; ACTIVATE.QUANTIZE identity {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L {{ cr.panel }} LR11 ; INC LR11 1{% endif %} ;;
{% endfor %}
{% endfor %}
    SET LR13 LR5 ; SET LR9 CR0 ;;
{% if center_full %}
    SET LR8 {{ cr.pixels }} ;;
    DEC LR8 8 ;;
{% endif %}
center_tile:
    SET LR2 LR13 ; SET LR5 LR15 ; SET LR4 LR14 ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
    ADDB LRD4 LR9 {% if not center_full %}; SUB LR11 LR0 CR1{% endif %} ;;
{% for panel in range(5) %}
{% set sums = loop.last %}
{% for tap in range(chunks|length if sums else 16) %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD4 LRD6 0
    {% if loop.first %}; SET LR6 LR14 ; SET LR7 LR15{% else %}; ADDBI LRD6 8{% endif %}
    {% if tap == 1 %}; INC LR11 1{% endif %}
    {% if not center_full and panel == 3 and tap == 14 %}; ADD LR8 LR11 CR1{% endif %}
    {% if not loop.last or not sums %}
        {% if panel == 3 and loop.last %}; {{ 'SET LR2 CR0' if center_full else 'ADD LR2 LR8 CR1' }} ; LD.MULT R0 LR2 {{ cr.panel }}
        {% elif sums %}; INC LR2 1 ; LD.MULT R0 LR2 {{ cr.panel }}
        {% else %}; ADD LR2 LR2 {{ cr.plane }} ; LD.MULT R0 LR2 {{ cr.in0 }}{% endif %}
    {% endif %}
    {% if loop.last %}; ACTIVATE.QUANTIZE identity {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L {{ cr.panel }} LR11{% if sums and center_full %}; INC LR9 8 ; BLT.S LR9 LR8 center_tile{% endif %}{% endif %} ;;
{% endfor %}
{% endfor %}
{% if n % 128 == 0 %}
{# Keep panel 0 in R0 and alternate the traversal of panels 1–4 in R1.
   Cache a coefficient at each R1 panel boundary so the LOAD slot can
   switch panels without interrupting the MAC stream. #}
{% macro center_pair_pixel(reverse) %}
    {{ mac('CR1', 'ACC.ADD.FIRST') }} ; ADD LR8 LR6 CR1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; SET LR4 LR2 ;;
    {% set order = [0, 4, 3, 2, 1] if reverse else [0, 1, 2, 3, 4] %}
    {% set cache = {33: 'LR1', 48: 'LR5', 64: 'LR7'} %}
    {% set seq = namespace(taps=[], scalar=[], switches=[]) %}
    {% for panel in order %}
        {% set count = chunks|length if panel == 4 else 16 %}
        {% for i in range(count) %}
            {% set t = count - 1 - i if reverse and panel >= 2 else i %}
            {% set seq.taps = seq.taps + [panel * 16 + t + 1] %}
            {% set seq.scalar = seq.scalar + [128 * (panel != 0)|int + t * 8] %}
            {% set seq.switches = seq.switches + [(i == count - 1 and panel != 0 and not (panel == order[-1]))] %}
        {% endfor %}
    {% endfor %}
    {% set stream = namespace(prev=1, loads={}) %}
    {% for index in range(1, seq.taps|length) %}
        {% if seq.taps[index] not in cache %}
            {% set word = index - 1 if not seq.switches[index - 1] else index - 2 %}
            {% set stream.loads = dict(stream.loads, **{(word|string): seq.taps[index] - stream.prev}) %}
            {% set stream.prev = seq.taps[index] %}
        {% endif %}
    {% endfor %}
    {% for panel in order %}
    {% set base = 0 if panel == 0 else 16 + (order.index(panel) - 1) * 16 + (chunks|length - 16 if reverse and panel != 4 else 0) %}
    {% for t in range(chunks|length if panel == 4 else 16) %}
    {% set j = base + t %}
    {% set delta = seq.scalar[j] - seq.scalar[j-1] if j else 0 %}
    {% set weight = stream.loads.get(j|string) %}
    MULT.RC.VE {{ cache.get(seq.taps[j], 'LR0') }} LR4 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
        {% if delta %}; {{ 'INC' if delta > 0 else 'DEC' }} LR4 {{ delta|abs }}{% endif %}
        {% if seq.switches[j] %}; {{ 'DEC' if reverse else 'INC' }} LR11 1 ; LD.MULT R1 LR11 {{ cr.panel }}
        {% elif weight is not none %}; {{ 'INC' if weight > 0 else 'DEC' }} LR8 {{ weight|abs }} ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0{% endif %}
        {% if j == seq.taps|length - 1 %}; ADD LR3 LR3 {{ cr.blocks }} ; INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ cr.full_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; LD.MULT.CYCLIC LR6 {{ cr.coeff }} LR0 {% if reverse %}; BLT.S LR2 {{ cr.loop_k }} center_pixel{% endif %}{% endif %} ;;
    {% endfor %}
    {% endfor %}
{% endmacro %}
    SET LR6 CR0 {% if n > 128 %}; DEC LR3 {{ n // 128 - 1 }}{% endif %} ;;
center_cache:
    SET LR8 LR6 ; ADD LR5 LR1 LR1 ; SET LR11 CR0 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ;;
    INC LR8 33 ; ADD LR7 LR5 LR1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR1 ;;
    INC LR8 15 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR5 ;;
    INC LR8 16 ; INC LR11 8 ; SET LR9 {{ cr.pixels }} ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR7 ;;
center_dot_tile:
    SET LR2 CR0 ; LD.MULT R0 LR11 {{ cr.panel }} ;;
    INC LR11 1 ; DEC LR9 8 ; LD.MULT R1 LR11 {{ cr.panel }} ;;
center_pixel:
    {{ center_pair_pixel(false) }}
    {{ center_pair_pixel(true) }}
    INC LR11 4 ; BNE LR9 CR0 center_dot_tile ;;
    INC LR6 {{ center_rows }} ; BEQ LR6 {{ cr.tail_ds }} center_cache_end ;;
    SUB LR3 LR3 {{ cr.batch_skip }} ; B center_cache ;;
center_cache_end:
{% else %}
    SET LR2 CR0 ; SET LR5 CR0 ; LD.MULT R0 LR0 {{ cr.panel }} ;;
    INC LR5 7 ;;
center_pixel:
    SET LR8 CR0 ; SET LR6 {{ cr.blocks }} ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ;;
center_block:
    {{ mac('CR1', 'ACC.ADD.FIRST') }} ; {{ next_coeff() }} ; SET LR11 CR0 ; DEC LR6 1 ;;
{% for panel in range(5) %}
    {% set last_panel = loop.last %}
    {% for tap in range(8 if last_panel else 16) %}
    {{ mac('LR4') }} {% if not loop.first %}; INC LR4 8{% endif %}
    {% if panel == 0 and loop.first %}; SET LR4 LR2{% endif %}
    {% if not (last_panel and loop.last) %}; {{ next_coeff() }}{% endif %} ;;
    {% endfor %}
    {% if not last_panel %}INC LR11 1 ; LD.MULT R1 LR11 {{ cr.panel }} ; ADD LR4 LR2 LR1 ;;{% endif %}
{% endfor %}
    BNE LR6 CR0 center_full ;;
    {{ store(cr.tail_ds) }} ; INC LR2 1 ; BLT.S LR2 LR5 center_pixel ;;
{% endif %}
{% if not center_full %}
    INC LR9 8 ;;
    BLT.S LR9 {{ cr.pixels }} center_tile ;;
{% endif %}
    ADD LR5 LR13 CR1 ; DEC LR10 1 ; DEC LR12 1 ; BEQ LR10 CR1 center_end ;;
    BNE LR12 CR0 center_group ;;
{% if center_full %}
    SET LR12 {{ cr.plane }} ;;
    {% for part in range(3) %}{% for step in range(21) %}
    ADD LR5 LR5 {{ cr.plane }} {% if part == 2 and loop.last %}; B center_group{% endif %} ;;
    {% endfor %}{% endfor %}
{% else %}
    ADD LR5 LR5 {{ cr.batch_skip }} ; SET LR12 {{ cr.plane }} ; B center_group ;;
{% endif %}
center_end:
    HALT ;;
{% if n % 128 != 0 %}center_full:
    {{ store(cr.full_ds) }} ; {{ next_coeff() }} ; B center_block ;;
{% endif %}
{% elif packed %}
{# Pack eight consecutive pixels across sixteen input channels into each
   scratch row. The original tensor and output traversal remain unchanged. #}
{% macro gather_next() %}
    ADD LR2 LR2 {{ cr.plane }} ; LD.MULT R0 LR2 {{ cr.in0 }}
{% endmacro %}
    INC LR1 7 ; SET LR13 CR0 ;;
{% if resident_panels %}
    INC LR6 128 ; INC LR8 33 ;;
    ADD LR7 LR6 LR6 ;;
    ADD LR5 LR7 LR6 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR6 ;;
    INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR5 ;;
    LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR7 ;;
{% endif %}
packed_group:
    SET LR9 CR0 ;;
{% if resident_panels %}
    SET LR2 LR13 ; SET LR11 CR1 ; SET LR8 CR0 ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    INC LR8 35 ; LD.MULT R1 LR8 {{ cr.coeff }} ; SET LR4 CR0 ;;
    INC LR4 127 ;;
{% for group in range(2) %}
    {% for tap in range(32) %}
    MULT.RC.VE LR0 LR4 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; INC LR4 1 ; {{ 'ACC.ADD.FIRST' if loop.first else 'ACC.ADD' }}
    {% if loop.last %}; INC LR11 1 ; ACTIVATE.QUANTIZE identity {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L {{ cr.panel }} LR11{% endif %}
    {% if group == 0 and loop.last %}; SET LR2 LR13 ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0
    {% elif not loop.last %}; ADD LR2 LR2 {{ cr.plane }} ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0{% endif %} ;;
    {% endfor %}
{% endfor %}
{% endif %}
packed_tile:
{% if resident_panels %}
    SET LR4 LR14 ; SET LR5 LR15 ; SET LR2 LR13 ;;
    ADDB LRD4 LR9 ; SET LR6 LR14 ; SET LR7 LR15 ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
{% for panel in range(2) %}
{% for tap in range(16) %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD4 LRD6 0 ;
    {% if tap == 0 and panel == 1 %}SET LR6 LR14 ; SET LR7 LR15 ; {{ gather_next() }}
    {% elif loop.last and panel == 0 %}ADDBI LRD6 8 ; ACTIVATE.QUANTIZE identity {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L {{ cr.panel }} LR0 ; {{ gather_next() }}
    {% elif loop.last %}ADDBI LRD6 8 ; SET LR11 CR1 ; ACTIVATE.QUANTIZE identity {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L {{ cr.panel }} LR11
    {% else %}{{ gather_next() }}{% if not loop.first %} ; ADDBI LRD6 8{% endif %}{% endif %} ;;
{% endfor %}
{% endfor %}
    LD.MULT R0 LR0 {{ cr.panel }} ; SET LR2 CR0 ; SET LR6 CR0 ; SET LR5 CR0 ;;
    LD.MULT R1 LR11 {{ cr.panel }} ; INC LR6 128 ; INC LR5 192 ;;
    ADD LR7 LR6 LR6 ; INC LR5 192 ; INC LR11 2 ;;
{% else %}
    SET LR4 LR14 ; SET LR5 LR15 ; SET LR2 LR13 ;;
    ADDB LRD4 LR9 ; SET LR11 CR0 ; SET LR8 {{ cr.loop_k }} ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
gather_group:
    SET LR6 LR14 ; SET LR7 LR15 ;;
{% for tap in range(16) %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD4 LRD6 0 ;
    {% if loop.last %}ADDBI LRD6 8 ; ACTIVATE.QUANTIZE identity {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L {{ cr.panel }} LR11{% else %}{{ gather_next() }}{% if not loop.first %} ; ADDBI LRD6 8{% endif %}{% endif %} ;;
{% endfor %}
    INC LR11 1 ; DEC LR8 16 ;;
    BEQ LR8 CR0 gather_end ;;
    {{ gather_next() }} ; B gather_group ;;
gather_end:
    SET LR2 CR0 {% if k == 64 %}; SET LR7 CR0{% endif %} {% if k == 32 and n <= 128 %}; SET LR8 CR1 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0{% endif %} ;;
    {% if k == 64 %}INC LR7 128 ;;{% endif %}
{% endif %}
packed_pixel:
{% if resident_panels %}
    SET LR8 CR1 ; SET LR4 LR2 ; DEC LR11 1 ; MULT.RC.VE LR7 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ;;
{% for tap in range(32) %}
    {{ mac('LR4') }} ; {% if tap == 16 %}ADD LR4 LR2 LR6 ;{% elif not loop.first %}INC LR4 8 ;{% endif %}
    {% if tap == 15 %}
    LD.MULT R0 LR11 {{ cr.panel }} ;;
    MULT.RC.VE LR6 LR4 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ADD LR4 LR2 LR9 ; ACC.ADD ; {{ next_coeff() }} ;;
    {% elif loop.last %}
    ADD LR8 LR2 LR9 ; INC LR11 1 ; LD.MULT R0 LR11 {{ cr.panel }} ;;
    {% else %}
    {{ next_coeff() }} ;;
    {% endif %}
{% endfor %}
    MULT.RC.VE LR5 LR8 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT R0 LR0 {{ cr.panel }} ; {{ store(cr.tail_ds) }} ; INC LR2 1 ; BLT.S LR2 LR1 packed_pixel ;;
{% else %}
    {% if not (k == 32 and n <= 128) %}SET LR6 {{ cr.blocks }} ; SUB LR8 LR0 CR1 ;;{% endif %}
    {% if not (k == 32 and n <= 128) %}packed_block:{% endif %}
    {% if not (k == 32 and n <= 128) %}SET LR11 CR0 {% if k != 64 %}; SET LR7 {{ cr.loop_k }}{% endif %} ; {{ next_coeff() }} ;;{% endif %}
    {% if resident_panels %}
    {{ mac('CR1', 'ACC.ADD.FIRST') }} ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; SET LR4 LR2 ;;
    {{ mac('CR1') }} ; {{ next_coeff() }} ;;
    {% else %}
    {{ mac('CR1', 'ACC.ADD.FIRST') }} ; {% if k == 32 and n <= 128 %}SET LR11 CR0 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0{% else %}{{ next_coeff() }} ; DEC LR6 1{% endif %} ;;
    {{ mac('CR1') }} ; LD.MULT R0 LR11 {{ cr.panel }} ; SET LR4 LR2 ;;
    {% endif %}
panel_taps:
{% for panel in range(2 if k == 32 else 4 if k == 64 else 1) %}
    {% if not resident_panels %}{{ next_coeff() }} ; INC LR11 1 {% if k != 32 and k != 64 %}; DEC LR7 16{% endif %}{% if k == 64 and panel > 0 %}; {{ 'ADD LR4 LR2 LR7' if panel % 2 else 'SET LR4 LR2' }}{% endif %} ;;{% endif %}
{% for tap in range(16) %}
    {% if (tap < split_taps - (1 if panel == 1 else 0) if k == 32 and n > 64 else tap >= 16 - split_taps if k == 96 else tap < split_taps) %}
    {{ mac('LR4') }} ; {{ next_coeff() }} ;;
    {% endif %}
    {% if not loop.last %}
    {{ mac('LR5') }} ; {{ next_coeff() }} ; SET LR5 LR4 ; INC LR4 8 ;;
    {% else %}
    {% if k == 32 %}
    {% if resident_panels and panel == 0 %}
    {{ mac('LR5') }} ; {{ next_coeff() }} ; SET LR5 LR4 ; ADD LR4 LR2 LR6 ;;
    {% else %}
    {{ mac('LR4') }} {% if panel == 1 %}{% if n <= 128 %}; {{ store(cr.tail_ds) }} ; INC LR2 1 ; SET LR8 CR1 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0 ; BLT.S LR2 LR1 packed_pixel{% else %}; B packed_store{% endif %}{% endif %} ;;
    {% endif %}
    {% if panel == 0 and not resident_panels %}LD.MULT R0 LR11 {{ cr.panel }} ; SET LR4 LR2 ;;{% endif %}
    {% elif k == 64 %}
    {{ mac('LR4') }} {% if panel != 3 %}; LD.MULT {{ 'R1' if panel % 2 == 0 else 'R0' }} LR11 {{ cr.panel }}{% endif %} ;;
    {% else %}
    {{ mac('LR4') }} ; BEQ LR7 CR0 packed_store ;;
    LD.MULT R0 LR11 {{ cr.panel }} ; SET LR4 LR2 ; B panel_taps ;;
    {% endif %}
    {% endif %}
{% endfor %}
{% endfor %}
packed_store:
    {% if n > 128 %}BNE LR6 CR0 packed_full_store ;;{% endif %}
    {% if not (k == 32 and n <= 128) %}{{ store(cr.tail_ds) }} ; INC LR2 1 ; BLT.S LR2 LR1 packed_pixel ;;{% endif %}
{% endif %}
packed_advance:
{% if resident_panels %}
    INC LR9 8 ; BLT.S LR9 {{ cr.loop_k }} packed_tile ;;
{% else %}
    INC LR9 8 ;;
    BLT.S LR9 {{ cr.pixels }} packed_tile ;;
{% endif %}
    INC LR13 1 ; DEC LR10 1 ; DEC LR12 1 ; BEQ LR10 CR1 packed_end ;;
    BNE LR12 CR0 packed_group ;;
    ADD LR13 LR13 {{ cr.batch_skip }} ; SET LR12 {{ cr.plane }} ; B packed_group ;;
packed_end:
    HALT ;;
    {% if n > 128 %}
packed_full_store:
    {{ store(cr.full_ds) }} ; B packed_block ;;
    {% endif %}
{% else %}
group:
    SET LR9 CR0 ;;
pixel:
    SET LR8 CR0 ; SET LR6 {{ cr.blocks }} ;;
    DEC LR8 1 ;;
block:
    SET LR2 LR5 ; SET LR7 {{ cr.k }} ; {{ next_coeff() }} ;;
    {{ mac('CR1', 'ACC.ADD.FIRST') }} ; {{ next_coeff() }} ; DEC LR6 1 ; DEC LR7 1 ;;
    {{ mac('CR1') }} ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
    {{ next_coeff() }} ;;
channel:
    {{ mac('LR9') }} ; {{ next_coeff() }} ; BEQ LR7 CR0 last_channel ;;
    {{ mac('LR9') }} ; ADD LR2 LR2 {{ cr.plane }} ; LD.MULT R0 LR2 {{ cr.in0 }} ; DEC LR7 1 ;;
    {{ next_coeff() }} ; B channel ;;
last_channel:
    {{ mac('LR9') }} ; BNE LR6 CR0 full_store ;;
    {{ store(cr.tail_ds) }} ; INC LR9 1 ;;
    BLT.S LR9 {{ cr.pixels }} pixel ;;
    INC LR5 1 ; DEC LR10 1 ; DEC LR12 1 ;;
    BEQ LR10 CR0 end ;;
    BNE LR12 CR0 group ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; SET LR12 {{ cr.plane }} ; B group ;;
end:
    HALT ;;
full_store:
    {{ store(cr.full_ds) }} ; B block ;;
{% endif %}
