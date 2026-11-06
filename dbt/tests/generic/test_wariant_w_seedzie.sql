-- GENERIC

{#
	Test generic: sprawdza, czy DANE są poprawne. Ten plik to definicja (makro: jak sprawdzać),
	użycie to `data_tests: - wariant_w_seedzie` przy kolumnie w YAML modelu (co sprawdzać). Wbudowane
	not_null i unique oraz dbt_utils.unique_combination_of_columns nie mają definicji w repo — tylko
	użycie w YAML. Biegnie w dbt build po modelu (deploy, harmonogram); CI go nie odpala.

	Wariant spoza listy warianty testu w seeds/rejestr_testow.csv = błąd: tag z innymi wartościami albo
	literówka w zmiennej GTM. Model musi mieć kolumnę id_testu.
#}
{#
	{% test nazwa(argumenty) %} … {% endtest %} definiuje test generic. dbt sam podaje argumenty z YAML:
	model = relacja modelu, przy którym stoi test, column_name = nazwa kolumny (tu wariant).
	{{ model }} i {{ column_name }} wstawiają je w SQL. Jak w teście singular: wiersz wyniku = błąd.
	Przykład dla użycia przy int_ab__ekspozycje.wariant — po kompilacji:
		SELECT m.id_testu, m.wariant AS wariant
		FROM `twoj-projekt`.`dbt_dev_testy_ab`.`int_ab__ekspozycje` AS m
		JOIN `twoj-projekt`.`dbt_dev_testy_ab`.`stg_seeds__rejestr_testow` AS t ON t.id_testu = m.id_testu
		WHERE m.wariant NOT IN UNNEST(t.warianty)
	Np. wariant 'V1' (literówka w tagu) przy warianty = ['v0', 'v1'] → wiersz błędu.
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
