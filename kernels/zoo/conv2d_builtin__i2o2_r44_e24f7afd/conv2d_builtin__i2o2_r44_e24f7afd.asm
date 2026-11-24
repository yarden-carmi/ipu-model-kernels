{% set rows = (2*h+127)//128 %}
{% set slots = ['LR0','LR11','LR12'] %}
{% set ds = cr.full ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% macro delta(r,n) %}{% if n %} ;; {{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ n|abs }}{% endif %}{% endmacro %}
{% macro weight() %}LD.MULT R0 LR5 {{ cr.weights }} ; INC LR5 1{% endmacro %}

{# An output row may straddle two columns. Each side tap then has two
   pieces, with complementary lane masks folded into the weights. #}
{% macro tap(label, c, p, x) %}
 {% set q = (p+x)//2 %}
 {% set start = 128*c + ((p+x)%2-p)*h %}
 {% set first = (start-1)//128 %}
 {% set last = (start+128)//128 %}
 {% if q %}
 BEQ LR1 {{ 'CR0' if q < 0 else cr.last_pair }} {{ label }}_skip ; INC LR5 6 ;;
 DEC LR5 6 ;;
 {% endif %}
 {% for i in range(first,last+1) %}
 SET LR10 LR8{{ delta('LR10', q*rows + [[i,0]|max,rows-1]|min) }} ;;
 LD.MULT.CYCLIC LR10 {{ cr.in0 }} {{ slots[i-first] }} ;;
 {% endfor %}
 SET LR13 CR0{{ delta('LR13', (start-1)%128) }} ;;
 {{ weight() }} ;;
 {% for y in range(3) %}
 {% for part in range(2) %}
 MULT.RC.VV LR13 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD{% if y != 2 or part == 0 %} ; {{ weight() }}{% endif %}{% if part == 0 and y != 0 %} ; INC LR13 1{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {{ label }}_skip:
{% endmacro %}

{% macro chunk(c) %}
 {{ weight() }} ; SET LR6 CR0 ; SET LR8 LR3 ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; {{ weight() }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
 ic_{{ c }}:
 {{ tap('center_' ~ c, c, 0, 0) }}
 {% for p in range(2) %}
 {% if 128*c < (p+1)*h and 128*(c+1) > p*h %}
 {% for x in [-1,1] %}
 {{ tap('side_' ~ c ~ '_' ~ p ~ '_' ~ (x+1), c, p, x) }}
 {% endfor %}
 {% endif %}
 {% endfor %}
 INC LR6 1 ; ADD LR8 LR8 {{ cr.channel_rows }} ;;
 BLT.S LR6 {{ cr.cin }} ic_{{ c }} ;;
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ (cr.tail if c == rows-1 else cr.full) }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ;;
 INC LR14 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR11 CR0 ; SET LR12 CR0 ;;
 INC LR11 128 ; INC LR12 255 ;;
 INC LR12 1 ; SET LR14 CR0 ; SET LR2 CR0 ;;
 SET LR15 CR0 ;;
batch:
 SET LR7 CR0 ; SET LR4 CR0 ;;
 DEC LR4 1 ;;
oc:
 SET LR1 CR0 ; SET LR3 LR2 ;;
pair:
 SET LR5 LR4 ;;
 {% for c in range(rows) %}
 {{ chunk(c) }}
 {% endfor %}
 INC LR1 1 ; INC LR3 {{ rows }} ;;
 BLE.S LR1 {{ cr.last_pair }} pair ;;
 SET LR4 LR5 ; INC LR7 1 ;;
 BLT.S LR7 {{ cr.cout }} oc ;;
 ADD LR2 LR2 {{ cr.batch_rows }} ; INC LR15 1 ;;
 BLT.S LR15 {{ cr.in0_d0 }} batch ;;
 HALT ;;
