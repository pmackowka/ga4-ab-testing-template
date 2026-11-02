{#
	Test generic: sprawdza, czy DANE są poprawne. Ten plik to definicja (makro: jak sprawdzać),
	użycie to `data_tests: - variant_in_seed` przy kolumnie w YAML modelu (co sprawdzać). Wbudowane
	not_null i unique oraz dbt_utils.unique_combination_of_columns nie mają definicji w repo — tylko
	użycie w YAML. Biegnie w dbt build po modelu (deploy, harmonogram); CI go nie odpala.

	Wariant spoza listy variants testu w seeds/ab_tests.csv = błąd: tag z innymi wartościami albo
	literówka w zmiennej GTM. Model musi mieć kolumnę test_id.
#}
{% test variant_in_seed(model, column_name) %}

SELECT
	m.test_id,
	m.{{ column_name }} AS variant

FROM {{ model }} AS m
JOIN {{ ref('stg_seeds__ab_tests') }} AS t
	ON t.test_id = m.test_id
WHERE m.{{ column_name }} NOT IN UNNEST(t.variants)

{% endtest %}
