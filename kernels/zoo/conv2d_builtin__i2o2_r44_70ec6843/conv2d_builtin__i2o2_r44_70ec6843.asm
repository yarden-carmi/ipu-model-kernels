{% set chunks = (h + 127) // 128 %}
{% set pair_rows = (2*h + 127) // 128 %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set slots = ['LR0', 'LR11', 'LR12'] %}

{% macro delta(r, n) %}{% if n %} ;; {{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ n|abs }}{% endif %}{% endmacro %}
{% macro weight() %}LD.MULT R0 LR5 {{ cr.weights }} ; INC LR5 1{% endmacro %}

{% macro tap(tag, p, c, x) %}
 {% set start = ((p+x) % 2)*h + 128*c %}
 {% set first = (start-1)//128 %}
 {% set last = (start+128)//128 %}
 {% set q = (p+x)//2 * pair_rows %}
 {% if p == 0 and x == -1 %}BEQ LR1 CR0 {{ tag }}_skip ; INC LR5 6 ;;
 DEC LR5 6 ;;
 {% elif p == 1 and x == 1 %}BEQ LR1 {{ cr.last_x }} {{ tag }}_skip ; INC LR5 6 ;;
 DEC LR5 6 ;;
 {% endif %}
 {% for i in range(first, last+1) %}
 SET LR9 LR8{{ delta('LR9', q + [[i,0]|max,pair_rows-1]|min) }} ;;
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} {{ slots[i-first] }} ;;
 {% endfor %}
 SET LR13 {{ slots[(start-1-128*first)//128] }} ;;
 {{ weight() }}{% if (start-1)%128 %} ; INC LR13 {{ (start-1)%128 }}{% endif %} ;;
 {% for y in range(3) %}
 {% for part in range(2) %}
 MULT.RC.VV LR13 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD{% if y != 2 or part == 0 %} ; {{ weight() }}{% endif %}{% if part == 0 and y != 0 %} ; INC LR13 1{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {{ tag }}_skip:
{% endmacro %}

{% macro column(tag, p) %}
 SET LR5 CR0 ;;
 DEC LR5 1 ;;
 {% for c in range(chunks) %}
 {% set label = tag ~ c %}
 SET LR6 CR0 ; SET LR14 LR4{{ delta('LR14', c) }} ;;
 {{ label }}_oc:
 {{ weight() }} ; SET LR7 CR0 ; SET LR8 LR2 ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; {{ weight() }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
 {{ label }}_ic:
 {% for x in range(-1,2) %}
 {{ tap(label ~ '_' ~ (x+1), p, c, x) }}
 {% endfor %}
 ADD LR8 LR8 {{ cr.channel_rows }} ; INC LR7 1 ;;
 BLT.S LR7 {{ cr.cin }} {{ label }}_ic ;;
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ (cr.tail if c == chunks-1 else cr.full) }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ; INC LR6 1 ;;
 BLT.S LR6 {{ cr.cout }} {{ label }}_oc ; INC LR14 {{ chunks }} ;;
 {% endfor %}
 SET LR4 LR14{{ delta('LR4', 1-chunks) }} ; INC LR1 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR11 CR0 ; SET LR12 CR0 ;;
 INC LR11 128 ; INC LR12 255 ; SET LR3 CR0 ;;
 INC LR12 1 ; SET LR2 CR0 ; SET LR4 CR0 ;;
batch:
 SET LR1 CR0 ;;
pair:
 {{ column('even', 0) }}
 {{ column('odd', 1) }}
 INC LR2 {{ pair_rows }} ;;
 BLT.S LR1 {{ cr.w }} pair ;;
 ADD LR2 LR2 {{ cr.batch_rows }} ; INC LR3 1 ;;
 SUB LR2 LR2 {{ cr.channel_rows }} ;;
 BLT.S LR3 {{ cr.in0_d0 }} batch ;;
 HALT ;;
