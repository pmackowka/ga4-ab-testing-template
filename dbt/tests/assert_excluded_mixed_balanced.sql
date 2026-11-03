-- SINGULAR

-- Test singular: sprawdza, czy DANE są poprawne. Plik .sql w tests/, każdy zwrócony wiersz = błąd.
-- Biegnie w dbt build po modelach, z których czyta (deploy, harmonogram); CI go nie odpala.
{#
	excluded_mixed to ok. połowa ponownie wylosowanych — druga połowa trafiła w ten sam wariant
	i jest niewidoczna. Przy podobnych users różnica excluded_mixed między wariantem a kontrolą
	większa niż 2 × √(suma obu) jest podejrzana. Przykład: 410 vs 398 → różnica 12, próg
	2 × √808 ≈ 57 → w normie.
	Dwie możliwe przyczyny alarmu:
	- błąd: tag losuje ponownie mimo cookie albo zapisuje je tylko w jednym wariancie;
	- efekt wariantu: wariant zmienia, jak często ludzie wracają, więc częściej tracą cookie —
	  z jednego wariantu wypadają akurat najbardziej zaangażowani i wynik jest obciążony.
	warn: w obu przypadkach nie ufaj wynikowi bez wyjaśnienia różnicy, ale decyduje człowiek.
#}
{{ config(severity='warn') }}

SELECT
	v.test_id,
	v.variant,
	c.excluded_mixed AS excluded_mixed_control,
	v.excluded_mixed AS excluded_mixed_variant

FROM {{ ref('fct_ab_test_results') }} AS v
JOIN {{ ref('fct_ab_test_results') }} AS c
	ON c.test_id = v.test_id
	AND c.is_control
WHERE NOT v.is_control
	AND ABS(v.excluded_mixed - c.excluded_mixed) > 2 * SQRT(v.excluded_mixed + c.excluded_mixed)
