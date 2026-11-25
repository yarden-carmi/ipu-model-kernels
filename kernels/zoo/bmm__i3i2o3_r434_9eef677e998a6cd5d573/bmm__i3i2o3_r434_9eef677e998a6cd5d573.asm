{% set off = (in1_d2-in0_d1*n)%128 %}
{% set shared = k >= 3 and k <= 32 and in0_d1 == 4 and n <= 64 and off+n > 128 and off+2*n <= 256 and off+3*n > 256 and off+4*n <= 384 and (k-1)*((in1_d2+127)//128)+2 <= 255 %}
{% set fast = k == 64 or k == 256 %}
{% set chunks = 2 if k == 256 else 1 %}
{% set steps = 6 if chunks == 2 else 5 %}
{% macro out() %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13
{%- endmacro %}
{% macro save(ptr, half='L', desc=cr.ds) %}
    ACTIVATE.QUANTIZE identity {{ desc }}.{{ half }} {{ cr.qf_in1 }}.L {{ cr.panel }} {{ ptr }}
{%- endmacro %}
    INC LR7 128 ; DEC LR13 1 ; INC LR15 {{ k-1 if shared else 2 }} ;;
{% if shared %}
    ADD LR12 LR7 LR7 ; ADD LR2 LR7 LR3 ;;
    ADD LR14 LR12 LR7 ; SET LR11 LR12 ;;
    INC LR11 {{ off+2*n-128 }} ;;
{% endif %}
group:
{% if shared %}
{# The two crossing heads share the middle source row. Stream all
   three rows once per key and stage both windows in one pass. #}
    SET LR5 LR1 ; SET LR8 CR0 ; SET LR9 LR15 ; LD.MULT.CYCLIC LR5 {{ cr.vbase }} LR7 ;;
shared_middle:
    INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.vbase }} LR12 ;;
    INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.vbase }} LR14 ; BEQ LR8 LR15 shared_end ;
    MULT.RC.VE LR2 CR1 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; {{ save('LR8','H') }} ;;
    INC LR5 {{ (in1_d2+127)//128-2 }} ; INC LR8 1 ; INC LR9 1 ; LD.MULT.CYCLIC LR5 {{ cr.vbase }} LR7 ;
    MULT.RC.VE LR11 CR1 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; {{ save('LR9','H') }} ; B shared_middle ;;
shared_end:
    INC LR9 1 ; MULT.RC.VE LR11 CR1 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; {{ save('LR9','H') }} ; LD.MULT R0 LR0 {{ cr.in0 }} ;;
{% macro shared_head(h) %}
{% set staged = h%2 == 0 %}
{% set base = cr.panel if staged else cr.vbase %}
{% set back = 'DEC LR5 1' if staged else 'SUB LR5 LR5 ' ~ cr.stride ~ '.L' %}
{% set vec = 'LR6' if staged else 'LR8' %}
{% if staged %}
    SET LR5 CR0 ; SET LR4 {{ cr.mh }}.L ;;
    INC LR5 {{ k-1+h//2*k }} ; {% if h != 0 %} LD.MULT.CYCLIC LR5 {{ base }} LR7 ; {% endif %} ;;
{% else %}
{% set slot = 'LR12' if h == 1 else 'LR14' %}
{# Reuse the previous head's last panel row for the negated first key.
   SUB.FIRST starts each query without a separate zero-init word and
   avoids propagating negative zero. All other keys are read in place. #}
    INC LR10 {{ (off+h*n)%128 }} ; SET LR5 LR1 ; SET LR4 {{ cr.mh }}.L ;
    MULT.RC.VE LR10 CR1 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.SUB.FIRST ; {{ save('LR15','H') }} ;;
    INC LR5 {{ (k-2)*((in1_d2+127)//128)+(off+h*n)//128 }} ; SUB LR8 LR10 {{ slot }} ; LD.MULT.CYCLIC LR15 {{ cr.panel }} LR7 ;;
{% endif %}
{% macro first(again) %}
    {% if again %} SET LR5 LR3 ; {% elif staged %} {{ back }} ; {% endif %} DEC LR4 1 ; SET LR9 LR15 ; LD.MULT.CYCLIC LR5 {{ base }} LR6 ;
    MULT.RC.VE {{ 'LR2' if h == 0 else 'LR7' }} LR15 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.{{ 'ADD' if staged else 'SUB' }}.FIRST ;
{%- endmacro %}
    {{ first(false) }} B shared_keys_{{ h }} ;;
shared_query_{{ h }}:
    {{ first(true) }} ;;
shared_keys_{{ h }}:
{% for key in range(k-2,0,-1) %}
    DEC LR9 1 ; {{ back }} ; {% if loop.first %} SET LR3 LR5 ; {% endif %} LD.MULT.CYCLIC LR5 {{ base }} LR6 ;
    MULT.RC.VE {{ vec }} LR9 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; {% if loop.last %} BEQ LR4 CR0 shared_last_{{ h }} ; {% endif %} ;;
{% endfor %}
{% macro end_query(last) %}
    INC LR13 1 ; ADD LR0 LR0 {{ cr.stride }}.H ;
    {% if last and staged %} SET LR10 {{ 'LR12' if h == 0 else 'LR14' }} ; {% endif %}
    MULT.RC.VE {{ vec }} LR6 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; {{ out() }} ;
    {% if not last or h != 3 %} LD.MULT R0 LR0 {{ cr.in0 }} ; {% endif %}
    {% if not last %} B shared_query_{{ h }} ; {% endif %} ;;
{% endmacro %}
    {{ end_query(false) }}
shared_last_{{ h }}:
    {{ end_query(true) }}
{% endmacro %}
{% for head in range(4) %}
    {{ shared_head(head) }}
{% endfor %}
{% elif fast and n >= 3 and n <= 128 %}
{# Bitwise transpose: form two-key rows and replace one channel bit
   with one key bit per pass. Use both parity extracts before reloading. #}
    SET LR2 LR1 ; INC LR4 {{ off//64*64 }} ; INC LR11 {{ off//64*64 }} ;;
segment:
{% macro prepare(chunk) %}
    SET LR5 LR2 ; SET LR8 CR0 ; SET LR9 CR0 ;;
{% if chunk %}
{% for bit in range(7) %}
    {% if loop.first %} SET LR5 {{ cr.stride }}.L {% else %} ADD LR5 LR5 LR5 {% endif %} ;;
{% endfor %}
    ADD LR5 LR5 LR5 ;;
    ADD LR5 LR5 LR2 ;;
{% endif %}
    INC LR9 {{ k//(2*chunks)-2 }} ; DEC LR8 1 ; LD.MULT.CYCLIC LR5 {{ cr.vbase }} LR6 ;;
{% macro pack_tail(more) %}
    MULT.RC.VE LR11 CR1 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 64 off on LR15 ; {{ save('LR8') }} ;
    {% if more %} ADD LR5 LR5 {{ cr.stride }}.L ; LD.MULT.CYCLIC LR5 {{ cr.vbase }} LR6 ; B pack_{{ chunk }} ; {% endif %} ;;
{% endmacro %}
pack_{{ chunk }}:
    ADD LR5 LR5 {{ cr.stride }}.L ; INC LR8 1 ; LD.MULT.CYCLIC LR5 {{ cr.vbase }} LR6 ;
    MULT.RC.VE LR11 CR1 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 64 off on LR6 ; BEQ LR8 LR9 pack_last_{{ chunk }} ;;
    {{ pack_tail(true) }}
pack_last_{{ chunk }}:
    {{ pack_tail(false) }}
{% endmacro %}
{% macro shuffle(chunk, phase) %}
{% set count = 64 if chunks == 2 else 32 %}
{% set src = phase%2*64 %}
{% set dst = 64-src %}
{% set final = chunks == 2 and phase == steps-1 %}
{% set step = 2 if final else 1 %}
    SET LR5 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
    {% if src %} INC LR5 {{ src }} ; {% endif %} INC LR9 {{ src+count-1 }} ;
    {% if final %} ADD LR8 LR4 LR4 ; {% else %} {% if dst %} INC LR8 {{ dst }} ; {% endif %} {% endif %}
    LD.MULT.CYCLIC LR5 {{ cr.panel }} LR6 ;;
    INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.panel }} LR7 ;
    {% if final %} INC LR8 {{ 128+chunk }} ; {% endif %} ;;
    DEC LR8 {{ step }} ;;
    SET LR10 LR8 ;;
    INC LR10 {{ count//2*step }} ;;
{% macro shuffle_tail(more) %}
    {% if more %} INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.panel }} LR6 ; {% endif %}
    MULT.RC.VE LR6 CR1 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 64 on_inv off LR6 ;;
    {% if more %} INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.panel }} LR7 ; {% endif %}
    MULT.RC.VE LR7 CR1 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 64 on_inv off LR15 ; {{ save('LR10') }} ;
    INC LR10 {{ step }} ; {% if more %} B shuffle_{{ chunk }}_{{ phase }} ; {% endif %} ;;
{% endmacro %}
shuffle_{{ chunk }}_{{ phase }}:
    MULT.RC.VE LR6 CR1 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 64 on off LR6 ;;
    MULT.RC.VE LR7 CR1 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 64 on off LR15 ; {{ save('LR8') }} ; BEQ LR5 LR9 shuffle_last_{{ chunk }}_{{ phase }} ; INC LR8 {{ step }} ;;
    {{ shuffle_tail(true) }}
shuffle_last_{{ chunk }}_{{ phase }}:
    {{ shuffle_tail(false) }}
{% endmacro %}
{% for chunk in range(chunks) %}
    {{ prepare(chunk) }}
{% for phase in range(steps) %}
    {{ shuffle(chunk,phase) }}
{% endfor %}
{% endfor %}
{% if chunks == 1 %}
    SET LR5 CR0 ; SET LR8 LR4 ; SET LR9 LR4 ;;
    INC LR5 64 ; INC LR8 127 ; INC LR9 159 ;;
    SET LR10 CR0 ; LD.MULT R0 LR5 {{ cr.panel }} ;;
    INC LR10 31 ;;
unpack:
    MULT.VE LR6 CR1 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 64 on off LR6 ; {{ save('LR8','H',cr.k_ds) }} ; INC LR8 1 ; BEQ LR10 CR0 unpack_last ;;
    MULT.VE LR6 CR1 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 64 on_inv off LR6 ; {{ save('LR9','H',cr.k_ds) }} ;
    INC LR5 1 ; LD.MULT R0 LR5 {{ cr.panel }} ; INC LR9 1 ; DEC LR10 1 ; B unpack ;;
unpack_last:
    MULT.VE LR6 CR1 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 64 on_inv off LR6 ; {{ save('LR9','H',cr.k_ds) }} ; INC LR9 1 ;;
{% endif %}
    BEQ LR4 LR14 staged ; INC LR4 64 ;;
    BEQ LR11 LR6 second_half ;;
    SET LR11 CR0 ; INC LR2 1 ; B segment ;;
second_half:
    INC LR11 64 ; B segment ;;
staged:
    SET LR4 CR0 ; SET LR2 LR3 ; SET LR12 {{ cr.mh }}.H ;;
dot_head:
    SET LR4 {{ cr.mh }}.L ; {% if chunks == 2 %} ADD LR8 LR2 LR2 {% else %} SET LR8 LR2 {% endif %} ; SET LR10 {{ cr.n }} ;;
    INC LR8 128 ; DEC LR10 {{ 4 if chunks == 1 else 3 }} ;;
{% if chunks == 1 %}
    LD.MULT.CYCLIC LR8 {{ cr.panel }} LR7 ; ADD LR11 LR8 CR1 ;;
    LD.MULT R0 LR0 {{ cr.in0 }} ;;
dot_row:
    SET LR5 LR11 ; SET LR9 CR0 ; DEC LR4 1 ; LD.MULT.CYCLIC LR5 {{ cr.panel }} LR6 ;
    MULT.RC.VV LR7 R0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR9 {{ cr.k_ds }}.H ;;
dot_column:
    INC LR5 1 ; INC LR9 1 ; LD.MULT.CYCLIC LR5 {{ cr.panel }} LR6 ;
    MULT.RC.VV LR6 R0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR9 {{ cr.k_ds }}.H ; BLT.S LR9 LR10 dot_column ;;
    INC LR5 1 ; INC LR9 1 ; LD.MULT.CYCLIC LR5 {{ cr.panel }} LR6 ;
    MULT.RC.VV LR6 R0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR9 {{ cr.k_ds }}.H ; BEQ LR4 CR0 dot_last ;;
{% macro finish_dot(more) %}
    INC LR9 1 ; INC LR13 1 ; ADD LR0 LR0 {{ cr.stride }}.H ;
    MULT.RC.VV LR6 R0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR9 {{ cr.k_ds }}.H ; {{ out() }} ;
    {% if more %} LD.MULT R0 LR0 {{ cr.in0 }} ; B dot_row ; {% endif %} ;;
{% endmacro %}
    {{ finish_dot(true) }}
dot_last:
    {{ finish_dot(false) }}
{% else %}
dot_row:
    LD.MULT.CYCLIC LR0 {{ cr.in0 }} LR6 ; ADD LR11 LR0 CR1 ; SET LR5 LR8 ; SET LR9 CR0 ;;
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR7 ; DEC LR9 1 ;;
    LD.MULT R0 LR5 {{ cr.panel }} ;;
{% macro wide_first() %}
    INC LR5 1 ; INC LR9 1 ; LD.MULT R0 LR5 {{ cr.panel }} ;
    MULT.RC.VV LR6 R0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR9 {{ cr.ds }}.L
{%- endmacro %}
{% macro wide_second(more) %}
    MULT.RC.VV LR7 R0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR9 {{ cr.ds }}.L ;
    {% if more %} INC LR5 1 ; LD.MULT R0 LR5 {{ cr.panel }} ; {% else %} INC LR13 1 ; ADD LR0 LR0 {{ cr.stride }}.H ; DEC LR4 1 ; {{ out() }} ; BGT.S LR4 CR1 dot_row ; {% endif %}
{%- endmacro %}
dot_column:
    {{ wide_first() }} ; BEQ LR9 LR10 dot_penultimate ;;
    {{ wide_second(true) }} B dot_column ;;
dot_penultimate:
    {{ wide_second(true) }} ;;
    {{ wide_first() }} ;;
    {{ wide_second(false) }} ;;
{% endif %}
    ADD LR2 LR2 {{ cr.n }} ; DEC LR12 1 ; BGT.S LR12 CR1 dot_head ;;
{% else %}
    B narrow_group ;;
{% endif %}
next_group:
    ADD LR1 LR1 {{ cr.group_rows }} ;;
    {% if fast and n >= 3 and n <= 128 %} SET LR4 CR0 ; SET LR11 CR0 ; {% endif %} BNE LR1 {{ cr.all_group_rows }} group ;;
    HALT ;;
{% if not shared and not (fast and n >= 3 and n <= 128) %}
narrow_group:
    SET LR2 LR1 ; SET LR11 LR3 ; SET LR14 {{ cr.mh }}.H ;;
narrow_head:
    SET LR4 {{ cr.mh }}.L ;;
generic_row:
    SET LR12 LR2 ; SET LR15 {{ cr.n }} ;;
generic_tile:
    SET LR8 LR0 ; SET LR5 LR12 ; SET LR9 {{ cr.k_ds }}.L ;;
    MULT.VE LR6 CR0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
generic_chunk:
    SET LR10 LR6 ; LD.MULT R0 LR8 {{ cr.in0 }} ;;
generic_key:
    LD.MULT.CYCLIC LR5 {{ cr.vbase }} LR6 ; ADD LR5 LR5 CR1 ;;
    BGT.S LR15 LR7 generic_split ;;
    ADD LR8 LR11 LR15 ;;
    BGT.S LR8 LR7 generic_split ;;
    B generic_mac ;;
generic_split:
    BEQ LR11 LR6 generic_mac ;;
    LD.MULT.CYCLIC LR5 {{ cr.vbase }} LR7 ;;
generic_mac:
    MULT.RC.VE LR11 LR10 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;
    DEC LR5 1 ; DEC LR9 1 ; INC LR10 1 ; BEQ LR9 CR1 generic_store ;;
    ADD LR5 LR5 {{ cr.stride }}.L ; BEQ LR10 LR7 generic_next_chunk ;;
    B generic_key ;;
generic_next_chunk:
    {# Reconstruct the A chunk offset from the number of keys consumed. #}
    SUB LR8 {{ cr.k_ds }}.L LR9 ;;
    SET LR10 LR0 ;;
generic_chunk_offset:
    DEC LR8 128 ; INC LR10 1 ; BGT.S LR8 LR7 generic_chunk_offset ;;
    SET LR8 LR10 ; B generic_chunk ;;
generic_store:
    INC LR13 1 ; BGT.S LR15 LR7 generic_full ;;
    {{ out() }} ; ADD LR0 LR0 {{ cr.stride }}.H ; DEC LR4 1 ; BGT.S LR4 CR1 generic_row ;;
    ADD LR11 LR11 {{ cr.n }} ; DEC LR14 1 ; BEQ LR14 CR1 next_group ;;
normalize:
    BLT.S LR11 LR7 narrow_head ;;
    DEC LR11 128 ; INC LR2 1 ; B normalize ;;
generic_full:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;
    INC LR12 1 ; DEC LR15 128 ; B generic_tile ;;
{% endif %}
