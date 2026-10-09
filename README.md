# ab-test-bigquery

SQL pod BigQuery (eksport GA4) do kalkulatorów testów A/B na pmdata.pl. Scenariusz: e-commerce testuje kartę produktu; wejście do testu to `view_item`, konwersja to `purchase`.

Cała wiedza — co liczy zapytanie, które pole kalkulatora wypełnia i dlaczego tak — jest w komentarzach SQL.

## Kroki

| # | Kiedy | Plik | Wynik → pole kalkulatora |
|---|---|---|---|
| 1 | przed testem | `sql/01_przed_testem_tygodniowo.sql` | wiersz ŚREDNIA → [Przed testem](https://pmdata.pl/kalkulatory/wielkosc-proby-test-ab/): Użytkownicy w tygodniu, Konwertujący w tygodniu |
| 2 | przed testem, gdy test ma trwać 2+ tygodnie | `sql/02_przed_testem_okno_testu.sql` | to samo, z poprawką na powracających użytkowników |
| 3 | przed testem | kalkulator | ustawiasz MDE, warianty, ufność, moc, rodzaj testu, czas (opis w `01`) |
| 4 | w trakcie | — | nie zaglądasz do wyniku |
| 5 | po teście | `sql/03_po_tescie_warianty.sql` | [Po teście](https://pmdata.pl/kalkulatory/istotnosc-testu-ab/): Użytkownicy i Konwertujący A/B |
| 6 | po teście | `sql/04_po_tescie_przychod_miesieczny.sql` | Po teście: Miesięczny przychód ze strony testowej |

## Definicje

| Metryka | Definicja | Kolumna |
|---|---|---|
| Użytkownicy | unikalni `user_pseudo_id` z pierwszym `view_item` (przed testem) albo pierwszym przypisaniem do wariantu (po teście); nie sesje | `users_weekly`, `users` |
| Konwertujący | użytkownicy z `purchase` po pierwszym wejściu; osoby, nie zamówienia | `converters_weekly`, `converters` |
| CR | konwertujący / użytkownicy | `cr_pct` |
| Przychód miesięczny | przychód z `purchase` po pierwszym `view_item`, 30 dni przed testem | `monthly_revenue` |
| Wielokrotnie przypisani | użytkownicy z 2+ wariantami; wykluczeni z wyniku | `users_in_many_variants` |
