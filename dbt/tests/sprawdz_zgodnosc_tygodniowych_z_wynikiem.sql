-- SINGULAR

-- Test singular: sprawdza, czy DANE są poprawne. Plik .sql w tests/, każdy zwrócony wiersz = błąd.
-- Biegnie w dbt build po modelach, z których czyta (deploy, harmonogram); CI go nie odpala.
-- Ostatni tydzień fct_wyniki_testow_ab_tygodniowo musi dać te same liczby co fct_wyniki_testow_ab — inaczej
-- jeden z modeli inaczej liczy wykluczenia albo konwersje. Wiersz = rozjazd.
SELECT
	r.id_testu,
	r.wariant,
	r.uzytkownicy,
	w.uzytkownicy AS uzytkownicy_tygodniowo,
	r.konwertujacy,
	w.konwertujacy AS konwertujacy_tygodniowo,
	r.wykluczeni_mieszani,
	w.wykluczeni_mieszani AS wykluczeni_mieszani_tygodniowo

FROM {{ ref('fct_wyniki_testow_ab') }} AS r
JOIN {{ ref('stg_seeds__rejestr_testow') }} AS t
	USING (id_testu)
JOIN {{ ref('fct_wyniki_testow_ab_tygodniowo') }} AS w
	ON w.id_testu = r.id_testu
	AND w.wariant = r.wariant
	AND w.koniec_tygodnia = t.koniec_testu
WHERE r.uzytkownicy != w.uzytkownicy
	OR r.konwertujacy != w.konwertujacy
	OR r.wykluczeni_mieszani != w.wykluczeni_mieszani
