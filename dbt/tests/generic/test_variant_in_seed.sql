{#
	Wariant spoza listy variants testu w seeds/ab_tests.csv = błąd: tag z innymi wartościami albo
	literówka w zmiennej GTM. Model musi mieć kolumnę test_name.
#}
{% test variant_in_seed(model, column_name) %}

SELECT
	m.test_name,
	m.{{ column_name }} AS variant

FROM {{ model }} AS m
JOIN {{ ref('stg_seeds__ab_tests') }} AS t
	ON t.test_name = m.test_name
WHERE m.{{ column_name }} NOT IN UNNEST(t.variants)

{% endtest %}
