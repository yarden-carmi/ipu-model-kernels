{% macro add_store(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}

{% set step = (in0_d0 * in0_d1) % in0_d2 %}
{% set small = in0_d2 <= 256 %}
{% set schedule = namespace(phases=0, tile=0) %}
{% if small and out0_d2 == in0_d2 and (out0_d2 - 1) % 128 >= 2 and in0_d0 * in0_d1 // in0_d2 < 16 %}
    {% for n in range(1, 33) %}
        {% if schedule.phases == 0 and in0_d2 % n == 0 %}
            {% set tile = in0_d2 // n %}
            {% if 128 % tile == 0 and step % tile == 0 %}
                {% set schedule.phases = n %}
                {% set schedule.tile = tile %}
            {% endif %}
        {% endif %}
    {% endfor %}
{% endif %}
// Load the first physical row while checking both the lane boundary and
// whether the next logical column needs a carry. Save the current lane
// because MULT sees the cursor updates in the scatter word.
{% macro issue_gather(next_lane, branch, target) %}
    LD.MULT R0 LR6 {{ cr.in0 }} ;
    ADD LR8 LR6 CR1 ; SET LR9 LR7 ;
    {% if next_lane %}ADDBI LRD2 1 ;{% endif %}
    {{ branch }} LR7 {{ cr.col_limit ~ '.H' if in0_d2 - step >= 128 else cr.col_step ~ '.H' }} {{ target }} ;;
{% endmacro %}
{% macro scatter(index) %}
    MULT.EE {{ index }} CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD2 0 ;
{% endmacro %}
{% macro shift(reg, delta) %}
    {% if delta > 0 %}INC {{ reg }} {{ delta }} ;{% elif delta < 0 %}DEC {{ reg }} {{ -delta }} ;{% endif %}
{% endmacro %}

{% set stride = in0_d0 * in0_d1 %}
{% set fast = schedule.phases and schedule.phases <= 15 and in0_d2 > 128 %}
{% set paired = fast and 64 <= stride < 128 %}
// The longest paired orbit is fully specialized per starting phase. Keep
// that path only when at least the first half-row can often supply a pair.
{% set paired = paired and (schedule.phases <= 12 or stride <= 64) %}
{% set fast = fast and (paired or stride >= 128) %}
{% if fast %}
{% set tile = schedule.tile %}
{% set phases = schedule.phases %}
{% set tail = out0_d2 - 128 %}
{% macro vector_scatter(count, advance) %}
    MULT.VE LR7 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD8 LRD2 {{ 8 - count }} ;
    {% if advance %}ADDBI LRD2 {{ advance }} ;{% endif %}
{% endmacro %}
{% macro fast_store(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;
{% endmacro %}
{% macro full_store_and_prefetch() %}
    {{ fast_store('CR15.L') }} LD.MULT R0 LR6 {{ cr.in0 }} ;
    SET LR2 CR0 ; SET LR3 {{ 'LR14' if paired else 'CR0' }} ;;
{% endmacro %}
{% macro gather_word(col, previous, count, advance, last, full, branch='') %}
    {% set row = col // in0_d2 * 2 + col % in0_d2 // 128 %}
    {% set next = col + count * stride %}
    {% set next_row = next // in0_d2 * 2 + next % in0_d2 // 128 %}
    {{ vector_scatter(count, advance) }}
    {{ shift('LR7', col % in0_d2 % 128 - previous % in0_d2 % 128) }}
    {% if not last or full %}{{ shift('LR6', next_row - row) }}{% else %}INC LR1 1 ;{% endif %}
    {% if last %}LD.MULT R0 LR1 {{ cr.in1 }} ;{% else %}LD.MULT R0 LR6 {{ cr.in0 }} ;{% endif %}
    {{ branch }} ;;
{% endmacro %}
{% macro first_load(p) %}
    {% if p * tile >= 128 %}ADD LR6 LR4 CR1 ;{% else %}SET LR6 LR4 ;{% endif %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR7 LR5 ;;
    {% if p * tile >= 128 %}DEC LR7 128 ;;{% endif %}
{% endmacro %}
{% if paired %}
    SET LR14 LR3 ; SET LR9 LR8 ;;
{% else %}
    SET LR9 CR0 ;
    {% if phases == 3 %}INC LR11 {{ tile - 2 }} ;{% endif %} ;;
{% endif %}
    SET LR15 {{ cr.width_batch }}.H ;;
fast_dispatch:
{% if phases == 3 %}
    SET LR2 CR0 ; SET LR3 {{ 'LR14' if paired else 'CR0' }} ; BGE.S LR5 {{ cr.col_limit }}.H fast_start_2 ;;
    BLT.S LR5 LR11 fast_start_0 ;;
{% else %}
    SET LR7 CR0 ; SET LR2 CR0 ; SET LR3 {{ 'LR14' if paired else 'CR0' }} ;;
    INC LR7 {{ tile }} ;;
    {% for p in range(phases - 1) %}
        INC LR7 {{ tile }} ; BLT.S LR5 LR7 fast_start_{{ p }} ;;
    {% endfor %}
    B fast_start_{{ phases - 1 }} ;;
{% endif %}
{% if not paired %}
{% macro single_phase(p, full) %}
    {% set col = p * tile %}
    {% set nxt = (col + stride) % in0_d2 // tile %}
    {% set prev = (col - stride) % in0_d2 %}
    {% set tag = 'full' if full else 'tail' %}
    {% set limit = 'LR14' if full else 'LR10' %}
fast_{{ tag }}_loop_{{ p }}:
    {{ gather_word(col, prev, 1, 1, false, full, 'BLT.S LR2 ' ~ limit ~ ' fast_' ~ tag ~ '_loop_' ~ nxt ~ ' ;') }}
    {{ gather_word(col + stride, col, 1, 1, true, full, '' if full else 'B fast_tail_store ;') }}
    {% if full %}
        {{ full_store_and_prefetch() }}
        {% set after = (col + 3 * stride) % in0_d2 // tile %}
        {{ gather_word(col + 2 * stride, col + stride, 1, 0, false, false, 'B fast_tail_loop_' ~ after ~ ' ;') }}
    {% endif %}
{% endmacro %}
{% macro single_start(p) %}
fast_start_{{ p }}:
    {{ first_load(p) }}
    {% set col = p * tile %}
    {% set nxt = (col + stride) % in0_d2 // tile %}
    {{ gather_word(col, col, 1, 0, false, true, 'B fast_full_loop_' ~ nxt ~ ' ;') }}
{% endmacro %}
{% if phases == 3 %}{{ single_start(1) }}{% endif %}
{% for p in range(phases) %}
    {% if phases != 3 or p != 1 %}{{ single_start(p) }}{% endif %}
    {{ single_phase(p, true) }}
    {{ single_phase(p, false) }}
{% endfor %}
{% else %}
// For short strides a single vector multiply can supply two output lanes.
// Rotate a periodic gather schedule after a scalar peel, then emit its residue.
{% set orbit = namespace(size=phases) %}
{% for k in range(1, phases) %}
    {% if orbit.size == phases and k * stride % in0_d2 == 0 %}{% set orbit.size = k %}{% endif %}
{% endfor %}
{% macro pair_block(col, previous, length, full, p) %}
    {% set period = orbit.size %}
    {% set repeats = (length - 2) // period %}
    {% set rest = length - 1 - repeats * period %}
    {% set tag = 'full' if full else 'tail' %}
    {{ gather_word(col, previous, 1, 0, false, full) }}
    {% if repeats %}
        SET LR10 CR0 ;;
        INC LR10 {{ repeats - 1 }} ;;
pair_{{ tag }}_{{ p }}:
        {{ pair_segment(col + stride, col, 1, period, false, full) }}
        DEC LR10 1 ; BNE LR10 CR0 pair_{{ tag }}_{{ p }} ;;
    {% endif %}
    {% set before = namespace(width=1) %}
    {% if repeats %}
        {% set tmp = pair_segment(col + stride, col, 1, period, false, full, before, false) %}
    {% endif %}
    {% set start = col + (1 + repeats * period) * stride %}
    {{ pair_segment(start, start - before.width * stride, before.width, rest, true, full) }}
{% endmacro %}
{% macro pair_segment(col, previous, advance, length, final, full, result=none, emit=true) %}
    {% set s = namespace(index=0, previous=previous, advance=advance) %}
    {% for k in range(length) %}
        {% if k == s.index %}
            {% set c = col + k * stride %}
            {% set n = c + stride %}
            {% set count = 2 if k + 1 < length - (0 if final else 1) and c // in0_d2 == n // in0_d2 and c % in0_d2 // 128 == n % in0_d2 // 128 else 1 %}
            {% set last = final and k + count == length %}
            {% if emit %}{{ gather_word(c, s.previous, count, s.advance, last, full, 'B fast_tail_store ;' if last and not full else '') }}{% endif %}
            {% set s.index = k + count %}
            {% set s.previous = c %}
            {% set s.advance = count %}
        {% endif %}
    {% endfor %}
    {% if result is not none %}{% set result.width = s.advance %}{% endif %}
{% endmacro %}
{% macro pair_start(p) %}
fast_start_{{ p }}:
    {{ first_load(p) }}
    {% set col = p * tile %}
    {{ pair_block(col, col, 128, true, p) }}
    {{ full_store_and_prefetch() }}
    {% set before = namespace(width=1) %}
    {% set rest = (126 % orbit.size) + 1 %}
    {% set tail_col = col + 128 * stride %}
    {% set tmp = pair_segment(tail_col - rest * stride, 0, 1, rest, true, true, before, false) %}
    {{ pair_block(tail_col, tail_col - before.width * stride, tail, false, p) }}
{% endmacro %}
{% if phases == 3 %}{{ pair_start(1) }}{% endif %}
{% for p in range(phases) %}{% if phases != 3 or p != 1 %}{{ pair_start(p) }}{% endif %}{% endfor %}
{% endif %}
fast_tail_store:
    {{ fast_store(cr.tail ~ '.L') }} INC LR5 1 ; DEC LR15 1 ; BGE.S LR5 LR12 fast_wrap ;;
fast_next:
    ADD LR1 LR1 {{ cr.jump }} ; BNE LR15 CR0 fast_dispatch ;;
    ADD LR13 LR13 {{ cr.width_batch }}.L ;;
    SET LR1 LR13 ; SET LR15 {{ cr.width_batch }}.H ; BLT.S LR13 {{ cr.batch_rows }} fast_dispatch ;;
    HALT ;;
fast_wrap:
    INC LR4 2 ; SET LR5 CR0 ; B fast_next ;;
{% else %}
// Traverse (d1,d0) groups in storage-offset order for the strided view.
// LR4:LR5 is the padded row base and column of each group's first element.
y_loop:
    SET LR1 LR13 ; SET LR15 {{ cr.width_batch }}.H ;;
batch:
    SET LR6 LR4 ; SET LR7 LR5 ; SET LR12 {{ cr.width_batch }}.L ;;
chunk:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR14 {{ 'CR1' if small else 'CR0' }} ;;
    SET LR10 CR0 ; BNE LR12 CR1 full_count ;;
    SET LR10 {{ cr.tail }}.H ; BEQ LR0 CR0 gather_first ;;
full_count:
    INC LR10 128 ;;
{% if small %}
gather_first:
    {{ issue_gather(false, 'BGE.S', 'slow_gather') }}
fast_scatter:
    {{ scatter('LR9') }} ADD LR6 LR6 {{ cr.stride_rows }} ; ADD LR7 LR7 {{ cr.col_step }}.L ; INC LR14 1 ; BGE.S LR14 LR10 gather_done ;;
gather:
    {{ issue_gather(true, 'BLT.S', 'fast_scatter') }}
slow_gather:
    {% if in0_d2 - step < 128 and in0_d2 > 128 %}
    BLT.S LR7 {{ cr.col_limit }}.H slow_advance ;;
    LD.MULT R0 LR8 {{ cr.in0 }} ; SUB LR9 LR7 {{ cr.col_limit }}.H ;;
slow_advance:
    {% elif in0_d2 > 128 %}
    LD.MULT R0 LR8 {{ cr.in0 }} ; SUB LR9 LR7 {{ cr.col_limit }}.H ;
    {% endif %}
    ADD LR6 LR6 {{ cr.stride_rows }} ; ADD LR7 LR7 {{ cr.col_step }}.L ; BLT.S LR7 {{ cr.col_step }}.H slow_scatter ;;
    SUB LR7 LR7 {{ cr.col_limit }}.L ; ADD LR6 LR6 LR11 ;;
slow_scatter:
    {{ scatter('LR9') }} INC LR14 1 ; BLT.S LR14 LR10 gather ;;
gather_done:
{% else %}
gather_first:
    SET LR8 LR6 ; SET LR9 LR7 ; BLT.S LR7 {{ cr.col_limit }}.H first_row ;;
    B lane_wrap ;;
gather:
    ADDBI LRD2 1 ; SET LR8 LR6 ; SET LR9 LR7 ; BLT.S LR7 {{ cr.col_limit }}.H first_row ;;
lane_wrap:
    INC LR8 1 ; SUB LR9 LR9 {{ cr.col_limit }}.H ;;
    BGE.S LR9 {{ cr.col_limit }}.H lane_wrap ;;
first_row:
    // Control sees the old column: compare against width minus the step
    // while the LR slots advance the cursor and gather count.
    LD.MULT R0 LR8 {{ cr.in0 }} ;
    ADD LR6 LR6 {{ cr.stride_rows }} ; ADD LR7 LR7 {{ cr.col_step }}.L ; INC LR14 1 ; BLT.S LR7 {{ cr.col_step }}.H scatter ;;
    SUB LR7 LR7 {{ cr.col_limit }}.L ; ADD LR6 LR6 LR11 ;;
scatter:
    MULT.EE LR9 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD2 0 ; BLT.S LR14 LR10 gather ;;
{% endif %}
    LD.MULT R0 LR1 {{ cr.in1 }} ; BNE LR12 CR1 full_store ;;
    {{ add_store(cr.tail ~ '.L') }}
    BEQ LR0 CR0 stored ;;
full_store:
    {{ add_store('CR15.L') }}
stored:
    INC LR1 1 ; DEC LR12 1 ;;
    BNE LR12 CR0 chunk ;;
    DEC LR1 1 ;;
    INC LR5 1 ; ADD LR1 LR1 {{ cr.jump }} ; DEC LR15 1 ;;
    BLT.S LR5 {{ cr.col_limit }}.L batch_next ;;
    SET LR5 CR0 ; ADD LR4 LR4 LR11 ;;
batch_next:
    BNE LR15 CR0 batch ;;
    ADD LR13 LR13 {{ cr.width_batch }}.L ;;
    BLT.S LR13 {{ cr.batch_rows }} y_loop ;;
    HALT ;;
{% endif %}
