WITH testy AS (
	SELECT
		*,
		LAG(koniec_testu) OVER (PARTITION BY slot ORDER BY start_testu) AS poprzedni_koniec_w_slocie

	FROM {{ ref('stg_seeds__rejestr_testow') }}
)

SELECT
	id_testu,
	powod

FROM testy,
	UNNEST([
		IF(NOT REGEXP_CONTAINS(slot, r'^ab\d+$'),
			'slot musi być slotem abN — staging czyta tylko parametry ^ab\\d+$', NULL),
		IF(EXTRACT(DAYOFWEEK FROM start_testu) != 2, 'start_testu musi być poniedziałkiem', NULL),
		IF(EXTRACT(DAYOFWEEK FROM koniec_testu) != 1 OR koniec_testu <= start_testu,
			'koniec_testu musi być niedzielą po start_testu: pełne tygodnie', NULL),
		IF(wariant_kontrolny NOT IN UNNEST(warianty), 'wariant_kontrolny musi być na liście warianty', NULL),
		IF(ARRAY_LENGTH(warianty) < 2, 'warianty musi mieć co najmniej dwa warianty', NULL),
		IF(IFNULL(ARRAY_LENGTH(zdarzenia_ekspozycji), 0) = 0, 'zdarzenia_ekspozycji nie może być puste', NULL),
		IF(start_testu < DATE '{{ var("ga4_data_startu") }}',
			'start_testu przed ga4_data_startu: staging nie ma tych dni', NULL),
		IF(start_testu <= poprzedni_koniec_w_slocie,
			'okno nakłada się na poprzedni test w tym slocie', NULL),
		IF(start_testu > poprzedni_koniec_w_slocie
			AND DATE_DIFF(start_testu, poprzedni_koniec_w_slocie, DAY) <= 60,
			'slot wraca przed wygaśnięciem ciasteczek poprzedniego testu: start musi być > 60 dni po jego końcu', NULL)
	]) AS powod
WHERE powod IS NOT NULL
