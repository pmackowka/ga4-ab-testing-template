{% test wariant_w_seedzie(model, column_name) %}

SELECT
	m.id_testu,
	m.{{ column_name }} AS wariant

FROM {{ model }} AS m
JOIN {{ ref('stg_seeds__rejestr_testow') }} AS t
	ON t.id_testu = m.id_testu
WHERE m.{{ column_name }} NOT IN UNNEST(t.warianty)

{% endtest %}
