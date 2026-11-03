-- SINGULAR

-- Test singular: sprawdza, czy DANE są poprawne. Plik .sql w tests/, każdy zwrócony wiersz = błąd.
-- Biegnie w dbt build po modelach, z których czyta (deploy, harmonogram); CI go nie odpala.
{#
	wykluczeni_mieszani to ok. połowa ponownie wylosowanych — druga połowa trafiła w ten sam wariant
	i jest niewidoczna. Przy podobnej liczbie użytkowników różnica wykluczeni_mieszani między wariantem a kontrolą
	większa niż 2 × √(suma obu) jest podejrzana. Przykład: 410 vs 398 → różnica 12, próg
	2 × √808 ≈ 57 → w normie.
	Dwie możliwe przyczyny alarmu:
	- błąd: tag losuje ponownie mimo cookie albo zapisuje je tylko w jednym wariancie;
	- efekt wariantu: wariant zmienia, jak często ludzie wracają, więc częściej tracą cookie —
	  z jednego wariantu wypadają akurat najbardziej zaangażowani i wynik jest obciążony.
#}
{{ config(severity='warn') }}
	{# warn, nie error: w obu przypadkach nie ufaj wynikowi bez wyjaśnienia różnicy, ale decyduje człowiek — build się kończy #}

SELECT
	v.id_testu,
	v.wariant,
	c.wykluczeni_mieszani AS wykluczeni_mieszani_kontrola,
	v.wykluczeni_mieszani AS wykluczeni_mieszani_wariant

FROM {{ ref('fct_wyniki_testow_ab') }} AS v
JOIN {{ ref('fct_wyniki_testow_ab') }} AS c
	ON c.id_testu = v.id_testu
	AND c.czy_kontrola
WHERE NOT v.czy_kontrola
	AND ABS(v.wykluczeni_mieszani - c.wykluczeni_mieszani) > 2 * SQRT(v.wykluczeni_mieszani + c.wykluczeni_mieszani)
