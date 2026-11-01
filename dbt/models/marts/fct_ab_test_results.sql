{#
	Wynik testu do kalkulatora „Po teście A/B” — jeden wiersz na test i wariant (odpowiednik sql/03).
	Spine z seeda: wariant bez ani jednego użytkownika zostaje jako wiersz z zerami, zamiast zniknąć
	z wyniku. FULL JOIN: wariant z danych, którego nie ma w seedzie, też zostaje i zatrzymuje build
	na teście variant_in_seed. sql/03 robi to samo funkcją ERROR().
#}
WITH tests AS (
	SELECT * FROM {{ ref('stg_seeds__ab_tests') }}
),

seed_variants AS (
	SELECT
		t.test_id,
		variant

	FROM tests AS t
	CROSS JOIN UNNEST(t.variants) AS variant
),

observed AS (
	-- users i converters bez ponownie wylosowanych: nie wiadomo, któremu wariantowi przypisać ich
	-- zakup. excluded_mixed to kontrola jakości — opis progu w tests/assert_excluded_mixed_balanced.sql
	SELECT
		x.test_id,
		x.variant,
		COUNTIF(x.variants_seen = 1) AS users,
		COUNTIF(x.variants_seen = 1 AND c.user_pseudo_id IS NOT NULL) AS converters,
		COUNTIF(x.variants_seen > 1) AS excluded_mixed

	FROM {{ ref('int_ab__exposures') }} AS x
	LEFT JOIN {{ ref('int_ab__conversions') }} AS c
		USING (test_id, user_pseudo_id)
	GROUP BY x.test_id, x.variant
)

SELECT
	test_id,
	t.test_name,
	variant,
	variant = t.control_variant AS is_control,
	IF(variant = t.control_variant, 'A (kontrola)', CONCAT('B (wariant ', variant, ')'))
		AS calculator_field,
	IFNULL(o.users, 0) AS users,
	IFNULL(o.converters, 0) AS converters,
	IFNULL(o.excluded_mixed, 0) AS excluded_mixed,
	t.is_final

FROM seed_variants
FULL JOIN observed AS o
	USING (test_id, variant)
JOIN tests AS t
	USING (test_id)
