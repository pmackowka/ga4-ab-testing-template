{% docs __overview__ %}
# Testy A/B na eksporcie GA4

Projekt liczy wyniki wszystkich testów A/B z rejestru naraz, prosto z eksportu GA4 w BigQuery. Wynik wpisujesz do kalkulatora [Po teście A/B](https://pmdata.pl/kalkulatory/istotnosc-testu-ab/?utm_source=dbt_docs&utm_medium=referral), a plan testu liczy [Przed testem](https://pmdata.pl/kalkulatory/wielkosc-proby-test-ab/?utm_source=dbt_docs&utm_medium=referral). Wdrożenie (GTM, eksport GA4, GCP, GitHub Actions) opisuje [README w repozytorium](https://github.com/pmackowka/ga4-ab-testing-template#readme) — ta strona mówi, jak czytać dane.

## Od czego zacząć

Tabela wynikowa to `fct_wyniki_testow_ab`: wiersz = test × wariant. Do kalkulatora bierz tylko wiersze z `czy_koncowy = true` — od końca testu minęły 3 dni i GA4 nie dopisze już danych. `pole_kalkulatora` mówi, czy wiersz idzie w pole A (kontrola), czy B (wariant). Graf zależności otworzysz niebieską ikoną w prawym dolnym rogu. Gotowy widok tej tabeli i rejestru testów z opisem pól kalkulatora: [raport Data Studio](https://datastudio.google.com/reporting/c45c9272-2566-4ebf-a257-d2ed7ba516c0/page/U4ADG) — skopiuj go i podepnij pod własne tabele.

## Przepływ danych

| Warstwa | Model | Wiersz | Co robi |
|---|---|---|---|
| źródło | `ga4.zdarzenia` | event | dzienne tabele `events_YYYYMMDD` z eksportu GA4 |
| seed | `rejestr_testow` | test | slot, daty, warianty, event konwersji i ekspozycji |
| staging | `stg_seeds__rejestr_testow` | test | listy jako `ARRAY`, `id_testu`, `czy_koncowy` |
| staging | `stg_ga4__zdarzenia` | event × slot | tylko eventy z wariantem testu i eventy konwersji |
| intermediate | `int_ab__ekspozycje` | test × użytkownik | pierwsza ekspozycja i liczba wariantów u osoby |
| intermediate | `int_ab__konwersje` | test × użytkownik z konwersją | pierwsza konwersja po ekspozycji i przychód |
| mart | `fct_wyniki_testow_ab` | test × wariant | liczby do kalkulatora i kolumny jakości |

## Reguły liczenia

- Użytkownik wchodzi do testu przy pierwszym evencie ekspozycji z wariantem; liczy się wariant z tego eventu.
- Konwersja liczy się tylko po pierwszej ekspozycji i w oknie testu.
- Zamówienie liczy się raz na `transaction_id`.
- Przychód osoby jest przycięty do 99,9 percentyla przychodu konwertujących w teście (oba warianty razem).
- `(not set)` i pusty tekst to NULL.
- Osoby z 2+ wariantami wypadają z `uzytkownicy` i `konwertujacy`; ich liczbę pokazuje `wykluczeni_mieszani`.

## Kontrola jakości

| Test | Co sprawdza |
|---|---|
| `sprawdz_srm` | podział kontrola–wariant odbiega od 50/50 bardziej niż przypadek (p < 0,001); ostrzeżenie, nie błąd |
| `sprawdz_komplet_dni_ga4` | brak dziennej tabeli eksportu w dniach testu |
| `sprawdz_konfiguracje_testow` | błędy w rejestrze: nazwa slotu, pełne tygodnie, lista wariantów, okno nakładające się na poprzedni test w slocie albo zaczęte przed wygaśnięciem jego ciasteczek |
| `wariant_w_seedzie` | wariant spoza rejestru — zły tag albo literówka w GTM |

Kolumny `ponownie_przydzieleni` i `bez_przydzialu` nie idą do kalkulatora: pokazują utratę ciasteczek testu i GA, czyli jak bardzo ufać podziałowi.

---

Autor: Piotr Maćkówka · [pmdata.pl](https://pmdata.pl/?utm_source=dbt_docs&utm_medium=referral) · [licencja MIT](https://github.com/pmackowka/ga4-ab-testing-template/blob/main/LICENSE)
{% enddocs %}
