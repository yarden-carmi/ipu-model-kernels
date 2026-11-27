{% macro pixel(phase, yphase) %}
SET LR2 LR1 ; SET LR4 LR3 ;;
BEQ LR7 {{ 'CR0' if yphase == 'even' else cr.last_y }} ydone_{{ phase }}_{{ yphase }} ;;
{% if yphase == 'even' %}
BEQ LR3 CR0 yprev_{{ phase }}_{{ yphase }} ;;
SET LR4 CR0 ; BEQ CR0 CR0 ydone_{{ phase }}_{{ yphase }} ;;
yprev_{{ phase }}_{{ yphase }}:
DEC LR2 1 ; INC LR4 {{ in0_d3 }} ;;
{% else %}
BEQ LR3 CR0 ysame_{{ phase }}_{{ yphase }} ;;
INC LR2 1 ; SET LR4 CR0 ; BEQ CR0 CR0 ydone_{{ phase }}_{{ yphase }} ;;
ysame_{{ phase }}_{{ yphase }}:
INC LR4 {{ in0_d3 }} ;;
{% endif %}
ydone_{{ phase }}_{{ yphase }}:
ADD LR9 LR3 LR5 ; ADD LR10 LR3 LR6 ; ADD LR11 LR4 LR5 ;;
ADD LR12 LR4 LR6 ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
MULT.EE LR9 {{ cr.center }} 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR14 {{ cr.one }}.L ;;
MULT.EE LR10 {{ cr.side }} 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR14 {{ cr.one }}.L ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
MULT.EE LR11 {{ cr.side }} 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR14 {{ cr.one }}.L ;;
MULT.EE LR12 {{ cr.corner }} 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR14 {{ cr.one }}.L ;;
INC LR14 1 ;;
{% endmacro %}
{% macro column(phase) %}
SET LR6 LR5 ; BEQ LR5 {{ 'CR0' if phase == 'even' else cr.last_x }} xdone_{{ phase }} ;;
{% if phase == 'even' %}
DEC LR6 1 ;;
{% else %}
INC LR6 1 ;;
{% endif %}
xdone_{{ phase }}:
SET LR1 LR8 ; SET LR3 CR0 ; SET LR7 CR0 ;;
SET LR14 CR0 ;;
MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
yloop_{{ phase }}:
{{ pixel(phase, 'even') }}
{{ pixel(phase, 'odd') }}
BEQ LR7 {{ cr.last_y }} yend_{{ phase }} ;;
BEQ LR3 CR0 yfirst_{{ phase }} ;;
SET LR3 CR0 ; INC LR1 1 ; BEQ CR0 CR0 ynext_{{ phase }} ;;
yfirst_{{ phase }}:
INC LR3 {{ in0_d3 }} ;;
ynext_{{ phase }}:
INC LR7 1 ; BEQ CR0 CR0 yloop_{{ phase }} ;;
yend_{{ phase }}:
ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
INC LR13 1 ;;
{% endmacro %}
SET LR0 CR0 ; SET LR8 CR0 ; SET LR13 CR0 ;;
SET LR15 CR0 ;;
plane:
SET LR5 CR0 ;;
xloop:
{{ column('even') }}
{{ column('odd') }}
BEQ LR5 {{ cr.last_x }} xend ;;
INC LR5 1 ; BEQ CR0 CR0 xloop ;;
xend:
BEQ LR15 {{ cr.last_plane }} finished ;;
INC LR15 1 ; INC LR8 {{ (in0_d2 + 1) // 2 }} ; BEQ CR0 CR0 plane ;;
finished:
HALT ;;
