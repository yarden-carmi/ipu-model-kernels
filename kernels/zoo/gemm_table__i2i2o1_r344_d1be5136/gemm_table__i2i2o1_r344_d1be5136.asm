{% set chunks = (in0_d2 + 127) // 128 %}
{% set skipfull = n // 128 %}
{% set shift = n % 128 %}
{% set tiles = (n + shift + 127) // 128 %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% set step = m % in0_d2 %}
{% set periodic = in0_d2 == 192 and step in [64, 128] and k % 3 == 0 and shift == 0 %}
{% set granule = 16 %}
{% set schedule = namespace(period=0) %}
{% if chunks == 2 and in0_d2 % granule == 0 and m % granule == 0 and m <= 4 * granule %}
{% for length in range(1, 17) %}
{% if not schedule.period and (length * m) % in0_d2 == 0 %}
{% set schedule.period = length %}
{% endif %}
{% endfor %}
{% endif %}
{% set grouped = schedule.period and k % schedule.period == 0 %}
{% set yreg = 'LR8' if grouped or periodic else 'LR13' %}
{% set ypair = 'LRD8' if grouped or periodic else 'LRD12' %}
{% macro fetch() %}INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0{% endmacro %}
{% macro mac(src, accum='ADD') %}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ accum }}
{%- endmacro %}
{% macro copy(qf, accum='ADD.FIRST') %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ qf }}.L ; ACC.{{ accum }}
{%- endmacro %}
{% macro store(base, offset, fn, ds) %}
    ACTIVATE.QUANTIZE {{ fn }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ base }} {{ offset }}
{%- endmacro %}
{% macro period(phase, final=false) %}
{% for j in range(3) %}
{% set position = (phase + j * (step // 64)) % 3 %}
{% set advance = chunks * (m // in0_d2 + (position + step // 64) // 3) + ((position + step // 64) % 3 == 2)|int - (position == 2)|int %}
{% set src = 'LR12' if position == 1 else 'LR6' %}
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    {{ mac(src) }} ; {{ fetch() }}{% if not final or not loop.last %} ; INC LR5 {{ advance }}{% endif %}{% if not final and loop.last %} ; DEC LR10 1{% endif %} ;;
    {{ mac(src) }}{% if not final or not loop.last %} ; {{ fetch() }}{% endif %}{% if not final and loop.last %} ; BNE LR10 CR0 period_{{ phase }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro advance_lane(delta) %}
{% if delta > 0 %} ; INC LR12 {{ delta }}{% elif delta < 0 %} ; DEC LR12 {{ -delta }}{% endif %}
{%- endmacro %}
{% macro grouped_taps(phase) %}
{% set start = phase * granule %}
group_{{ phase }}:
{% for tap in range(schedule.period) %}
{% set pos = start + tap * m %}
{% set next = pos + m %}
{% set lane = (pos % in0_d2) % 128 %}
{% set row = 2 * (pos // in0_d2) + (pos % in0_d2) // 128 %}
{% set next_row = 2 * (next // in0_d2) + (next % in0_d2) // 128 %}
{% set prev = pos - m %}
{% set delta = lane - (prev % in0_d2) % 128 %}
{% set prev_row = 2 * (prev // in0_d2) + (prev % in0_d2) // 128 %}
{% if loop.first or prev_row != row %}
    LD.MULT R0 LR5 {{ cr.in0 }}{% if loop.first %} ; DEC LR10 1 ; SET LR12 LR7{% elif delta %}{{ advance_lane(delta) }}{% endif %} ;;
{% endif %}
    {{ mac('LR12') }} ; {{ fetch() }}{% if not loop.first and prev_row == row %}{{ advance_lane(delta) }}{% endif %}{% if loop.last %} ; BEQ LR10 CR0 last_channel{% endif %} ;;
    {{ mac('LR12') }} ; {{ fetch() }}{% if next_row != row %} ; INC LR5 {{ next_row - row }}{% endif %}{% if loop.last %} ; B group_{{ phase }}{% endif %} ;;
{% endfor %}
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
{% if not grouped and not periodic %}
    SET LR13 CR0 ;;
{% endif %}
    SET LR11 CR0 ;;
    SET LR15 CR0 ;;
    INC LR15 {{ tiles }} ;;
{% if periodic %}
    SET LR13 CR0 ; SET LR14 CR0 ;;
    INC LR13 64 ; INC LR14 128 ;;
{% elif grouped %}
{% for phase in range(1, [m // granule, 3] | min) %}
{% set bound = 'LR' ~ (phase + 12) %}
    SET {{ bound }} CR0 ;;
    INC {{ bound }} {{ phase * granule }} ;;
{% endfor %}
{% endif %}
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR11 ;;
    INC LR11 1 ;;
{% endfor %}
pixel:
{% if skipfull %}
    SET LR5 CR0 ; SET LR4 LR3 ;;
    INC LR5 {{ skipfull }} ;;
skip_tile:
    SET LR10 CR0 ; SET LR11 CR0 ; SET LR6 CR0 ;;
    INC LR6 128 ;;
    LD.MULT R0 LR4 {{ cr.in1 }} ;;
skip_channel:
    MULT.EE {{ yreg }} CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE {{ ypair }} LRD10 7 ; INC LR4 {{ in1_d3 }} ; DEC LR6 1 ; BEQ LR6 CR1 skip_store ;;
    ADDBI LRD10 1 ; LD.MULT R0 LR4 {{ cr.in1 }} ; B skip_channel ;;
skip_store:
    {{ store(cr.out0, 'LR2', 'identity', cr.full) }} ;;
    INC LR2 1 ; DEC LR5 1 ; BNE LR5 CR1 skip_tile ;;
{% endif %}
    SET LR4 CR0 ; SET LR11 CR0 ;;
    DEC LR4 1 ;;
gemm_tile:
    SET LR5 LR1 ; SET LR6 LR7 ; SET LR10 CR0 ;;
    INC LR10 {{ k // 3 - 1 if periodic else (k // schedule.period if grouped else k) }} ; INC LR11 1 ; {{ fetch() }} ;;
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ fetch() }} ;;
    {{ mac('CR1') }} ; {{ fetch() }} ;;
{% if periodic %}
    # For a 192-wide source row, the tap lane repeats every three channels.
    # Select the row half in the address, so only the used half is loaded.
    BLT.S LR7 LR13 phase_0 ;;
    BLT.S LR7 LR14 phase_1 ;;
{% for phase in [2, 1, 0] %}
phase_{{ phase }}:
{% if phase %}
    SUB LR6 LR7 LR{{ 12 + phase }}{% if phase == 2 %} ; INC LR5 1{% endif %} ;;
{% endif %}
    ADD LR12 LR6 LR13 ;;
{% if k > 3 %}
period_{{ phase }}:
    {{ period(phase) }}
{% endif %}
    {{ period(phase, true) }}
{% if not loop.last %}
    B gemm_store ;;
{% endif %}
{% endfor %}
gemm_store:
    BEQ LR11 LR15 final_tile ;;
{% else %}
{% if grouped %}
    # Each group returns to the same lane in a later physical row. Stream
    # coefficients without per-tap address tests, loading only the used half.
{% for phase in range(1, [m // granule, 3] | min) %}
{% set bound = 'LR' ~ (phase + 12) %}
    BLT.S LR7 {{ bound }} group_{{ phase - 1 }} ;;
{% endfor %}
{% if m // granule == 4 %}
    INC LR14 16 ;;
    BLT.S LR7 LR14 group_phase2 ;;
    DEC LR14 16 ; B group_3 ;;
group_phase2:
    DEC LR14 16 ; B group_2 ;;
{% endif %}
{% for phase in range(m // granule - 1, -1, -1) %}
    {{ grouped_taps(phase) }}
{% endfor %}
{% elif m % in0_d2 and m < in0_d2 %}
{% if chunks == 2 %}
    ADD LR8 LR5 CR1 ; LD.MULT R0 LR5 {{ cr.in0 }} ;;
    LD.MULT R1 LR8 {{ cr.in0 }} ;;
{% else %}
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
{% endif %}
channel_reuse:
    SET LR12 LR6 ; DEC LR10 1 ;;
    {{ mac('LR12') }} ; {{ fetch() }} ; INC LR6 {{ m }} ; BEQ LR10 CR0 last_channel ;;
    {{ mac('LR12') }} ; {{ fetch() }} ; BLT.S LR6 {{ cr.in0_d2 }} channel_reuse ;;
    SUB LR6 LR6 {{ cr.in0_d2 }} ; INC LR5 {{ chunks }} ;;
{% if chunks == 2 %}
    ADD LR8 LR5 CR1 ; LD.MULT R0 LR5 {{ cr.in0 }} ;;
    LD.MULT R1 LR8 {{ cr.in0 }} ; B channel_reuse ;;
{% else %}
    LD.MULT R0 LR5 {{ cr.in0 }} ; B channel_reuse ;;
{% endif %}
{% else %}
channel:
{% if chunks == 2 %}
    ADD LR8 LR5 CR1 ; LD.MULT R1 LR8 {{ cr.in0 }} ;;
{% endif %}
    LD.MULT R0 LR5 {{ cr.in0 }} ; DEC LR10 1 {% if m % in0_d2 %}; SET LR12 LR6{% endif %} ;;
{% if m % in0_d2 %}
    # Advance the lane while both coefficient parts still use the saved index.
    {{ mac('LR12') }} ; {{ fetch() }} ; INC LR6 {{ m % in0_d2 }} ; BEQ LR10 CR0 last_channel ;;
    {{ mac('LR12') }} ; {{ fetch() }} ; ADD LR5 LR5 {{ cr.stride }} ; BLT.S LR6 {{ cr.in0_d2 }} channel ;;
    SUB LR6 LR6 {{ cr.in0_d2 }} ; INC LR5 {{ chunks }} ; B channel ;;
{% else %}
    {{ mac('LR6') }} ; {{ fetch() }} ; BEQ LR10 CR0 last_channel ;;
    {{ mac('LR6') }} ; {{ fetch() }} ; ADD LR5 LR5 {{ cr.stride }} ; B channel ;;
{% endif %}
{% endif %}
last_channel:
{% set last_src = 'LR12' if m % in0_d2 else 'LR6' %}
{% if shift %}
    BEQ LR11 CR1 merge_skip ;;
{% endif %}
    {{ mac(last_src) }} ; BEQ LR11 LR15 final_tile ;;
{% endif %}
    {{ store(cr.out0, 'LR2', act, cr.full) }} ;;
    INC LR2 1 ; B gemm_tile ;;
final_tile:
    {{ store(cr.out0, 'LR2', act, cr.tail) }} ;;
next_pixel:
    INC LR2 1 ; INC LR7 1 ; DEC LR9 1 ; BEQ LR9 CR1 done ;;
    INC LR3 1 ; SET LR12 CR0 ;;
    INC LR12 {{ in1_d3 }} ;;
    BNE LR3 LR12 x_ready ;;
    SET LR3 CR0 ; INC {{ yreg }} 1 ;;
x_ready:
    BNE LR7 {{ cr.in0_d2 }} pixel ;;
    SET LR7 CR0 ; INC LR1 {{ chunks }} ; B pixel ;;
done:
    HALT ;;
{% if shift %}
merge_skip:
    {{ mac(last_src) }} ; {{ store(cr.tmp, 'LR0', act, cr.full) }} ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ; SET LR12 LR4 ;;
    {{ copy(cr.qf_out0) }} ; SET LR10 CR0 ; SET LR11 CR0 ; SET LR6 CR0 ;;
    SET LR4 LR3 ; INC LR6 {{ shift }} ;;
    ADD LR4 LR4 {{ cr.skip_offset }} ;;
    LD.MULT R0 LR4 {{ cr.in1 }} ;;
merge_channel:
    MULT.EE {{ yreg }} CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE {{ ypair }} LRD10 7 ; INC LR4 {{ in1_d3 }} ; DEC LR6 1 ; BEQ LR6 CR1 merge_done ;;
    ADDBI LRD10 1 ; LD.MULT R0 LR4 {{ cr.in1 }} ; B merge_channel ;;
merge_done:
    SET LR11 CR1 ; SET LR4 LR12 ;;
{% if tiles == 1 %}
    {{ store(cr.out0, 'LR2', 'identity', cr.tail) }} ; B next_pixel ;;
{% else %}
    {{ store(cr.out0, 'LR2', 'identity', cr.full) }} ;;
    INC LR2 1 ; B gemm_tile ;;
{% endif %}
{% endif %}
