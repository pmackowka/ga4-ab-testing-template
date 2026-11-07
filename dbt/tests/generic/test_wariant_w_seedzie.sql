-- GENERIC

{#
	Test generic: wiersz = wariant spoza listy warianty w seedzie (zły tag albo literówka w GTM).
	Użycie: data_tests: - wariant_w_seedzie przy kolumnie modelu z id_testu.
#}
{% test wariant_w_seedzie(model, column_name) %}

SELECT
	m.id_testu,
	m.{{ column_name }} AS wariant

FROM {{ model }} AS m
JOIN {{ ref('stg_seeds__rejestr_testow') }} AS t
	ON t.id_testu = m.id_testu
WHERE m.{{ column_name }} NOT IN UNNEST(t.warianty)

{% endtest %}

{#
	Przykładowy wynik (błąd):
	id_testu     | wariant
	ab2_20260907 | V1
#}
