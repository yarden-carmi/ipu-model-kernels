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

// Traverse (d1,d0) groups in storage-offset order for the strided view.
// LR4:LR5 is the padded row base and column of each group's first element.
y_loop:
    SET LR1 LR13 ; SET LR15 {{ cr.width_batch }}.H ;;
batch:
    SET LR6 LR4 ; SET LR7 LR5 ; SET LR12 {{ cr.width_batch }}.L ;;
chunk:
{% if schedule.phases %}
    // All columns in a phase have the same physical row and lane deltas.
    // LR9 tracks the lane; LR6 tracks the loaded row. Each scatter loads
    // the next row, except the last scatter, which drains the pipeline.
    SET LR6 LR4 ; SET LR9 LR5 ; SET LR10 LR14 ; BNE LR12 CR1 phase_dispatch ;;
    SET LR10 LR8 ;
    {% if in0_d2 > 128 %}
        {% set chunk_stride = 128 * in0_d0 * in0_d1 %}
        {% set chunk_rows = chunk_stride // in0_d2 * 2 %}
        {{ shift('LR9', chunk_stride % in0_d2) }} ;;
        {% for block in range(chunk_rows // 128) %}
            INC LR6 128 ;;
        {% endfor %}
        {{ shift('LR6', chunk_rows % 128) }}
        BLT.S LR9 {{ cr.col_limit }}.L phase_dispatch ;;
        SUB LR9 LR9 {{ cr.col_limit }}.L ; ADD LR6 LR6 LR11 ;
    {% endif %}
    ;;
phase_dispatch:
    SET LR7 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    INC LR7 {{ schedule.tile }} ;;
    {% for p in range(schedule.phases - 1) %}
        INC LR7 {{ schedule.tile }} ; BLT.S LR9 LR7 phase_start_{{ p }} ;;
    {% endfor %}
    B phase_start_{{ schedule.phases - 1 }} ;;
    {% for p in range(schedule.phases) %}
        {% set col = p * schedule.tile %}
        {% set next_col = (col + step) % in0_d2 %}
        {% set next_phase = next_col // schedule.tile %}
        {% set prev_col = (col - step) % in0_d2 %}
        {% set row_delta = (in0_d0 * in0_d1 + col) // in0_d2 * ((in0_d2 + 127) // 128) + next_col // 128 - col // 128 %}
phase_start_{{ p }}:
        {{ shift('LR6', col // 128) }} {{ shift('LR9', -(col // 128) * 128) }} LD.MULT R0 LR6 {{ cr.in0 }} ;;
        {{ scatter('LR9') }} {{ shift('LR6', row_delta) }} LD.MULT R0 LR6 {{ cr.in0 }} ; B phase_loop_{{ next_phase }} ;;
phase_loop_{{ p }}:
        {{ scatter('LR9') }} {{ shift('LR6', row_delta) }} {{ shift('LR9', col % 128 - prev_col % 128) }} ADDBI LRD2 1 ;
        LD.MULT R0 LR6 {{ cr.in0 }} ; BLT.S LR2 LR10 phase_loop_{{ next_phase }} ;;
        {{ scatter('LR9') }} {{ shift('LR9', next_col % 128 - col % 128) }} ADDBI LRD2 1 ; B gather_done ;;
    {% endfor %}
gather_done:
{% else %}
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
{% endif %}
    LD.MULT R0 LR1 {{ cr.in1 }} ; BNE LR12 CR1 full_store ;;
    {{ add_store(cr.tail ~ '.L') }}
    BEQ LR0 CR0 stored ;;
full_store:
    {{ add_store('CR15.L') }}
stored:
    INC LR1 1 ; DEC LR12 1 ;;
    BNE LR12 CR0 chunk ;;
    INC LR5 1 ; ADD LR1 LR1 {{ cr.jump }} ; DEC LR15 1 ;;
    BLT.S LR5 {{ cr.col_limit }}.L batch_next ;;
    SET LR5 CR0 ; ADD LR4 LR4 LR11 ;;
batch_next:
    BNE LR15 CR0 batch ;;
    ADD LR13 LR13 {{ cr.width_batch }}.L ;;
    BLT.S LR13 {{ cr.batch_rows }} y_loop ;;
    HALT ;;
