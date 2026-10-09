# ab-test-bigquery

SQL pod BigQuery (eksport GA4) do kalkulatorów testów A/B na pmdata.pl. Scenariusz: e-commerce testuje kartę produktu; wejście do testu to `view_item`, konwersja to `purchase`. Każde zapytanie kończy się przykładową tabelą wyniku.

## Kroki

| # | Kiedy | Plik | Wynik → pole kalkulatora |
|---|---|---|---|
| 1 | przed testem | `sql/01_przed_testem_tygodniowo.sql` | wiersz ŚREDNIA → [Przed testem](https://pmdata.pl/kalkulatory/wielkosc-proby-test-ab/): Użytkownicy w tygodniu, Konwertujący w tygodniu |
| 2 | przed testem, gdy test ma trwać 2+ tygodnie | `sql/02_przed_testem_okno_testu.sql` | to samo, z poprawką na powracających użytkowników |
| 3 | przed testem | kalkulator | ustawiasz pola z tabeli „Pola bez SQL” |
| 4 | w trakcie | — | nie zaglądasz do wyniku |
| 5 | po teście | `sql/03_po_tescie_warianty.sql` | [Po teście](https://pmdata.pl/kalkulatory/istotnosc-testu-ab/): Użytkownicy i Konwertujący A/B |
| 6 | po teście | `sql/04_po_tescie_przychod_miesieczny.sql` | Po teście: Miesięczny przychód ze strony testowej |

## Definicje metryk

| Metryka | Definicja | Kolumna |
|---|---|---|
| Użytkownicy | unikalni `user_pseudo_id` od pierwszego `view_item` (przed testem) albo pierwszego przypisania do wariantu (po teście). Nie sesje: test losuje ludzi, a sesje jednej osoby nie są niezależne | `users_weekly`, `users` |
| Konwertujący | użytkownicy z `purchase` po pierwszym wejściu. Osoby, nie zamówienia; zakup sprzed wejścia nie zależał od wariantu | `converters_weekly`, `converters` |
| CR | konwertujący / użytkownicy | `cr_pct` |
| Przychód miesięczny | przychód z `purchase` po pierwszym `view_item`, 30 dni przed testem | `monthly_revenue` |
| Wielokrotnie przypisani | użytkownicy z 2+ wariantami (wyczyszczone cookies, błąd w tagu); wykluczeni. Powyżej ~1% — szukaj błędu | `users_in_many_variants` |

## Pola bez SQL — ustawiasz w kalkulatorze

| Pole | Co znaczy | Typowo |
|---|---|---|
| MDE (najmniejszy wzrost do wykrycia) | najmniejszy wzrost CR, który ma znaczenie biznesowe — nie wzrost, którego się spodziewasz. 2× mniejsze MDE = 4× więcej użytkowników. Nie wiesz? Sprawdź w kalkulatorze, jakie MDE wykryjesz w swoim czasie | +10–20% |
| Liczba wariantów | razem z kontrolą. Przy 3+ próg α dzielony przez k − 1 (korekta Bonferroniego) | 2 |
| Poziom ufności (1 − α) | chroni przed fałszywym pozytywem: przy 95% w 1 teście na 20 ogłosisz wzrost, którego nie ma | 95% |
| Moc testu (1 − β) | chroni przed fałszywym negatywem: przy 80% realny wzrost równy MDE wykryjesz w 4 testach na 5 | 80% |
| Rodzaj testu | dwustronny sprawdza wzrost i spadek; jednostronny tylko wzrost — ~21% krócej, ale nie wykryje szkody | dwustronny |
| Najdłużej możesz testować | pełne tygodnie, w których strona, ceny i kampanie się nie zmienią; powyżej ~6 tygodni psują kasowanie cookies i sezonowość | 2–6 tyg. |

## Jak czytać wynik po teście

| Pojęcie | Znaczenie |
|---|---|
| p-value | prawdopodobieństwo takiego lub bardziej skrajnego wyniku, gdyby wzrostu nie było; istotny, gdy < α. Nie jest prawdopodobieństwem, że wariant jest lepszy |
| Zakres wzrostu (przedział ufności) | wzrosty zgodne z danymi; obejmuje zero = wzrostu nie da się odróżnić od przypadku |
| SRM | nierówny podział użytkowników A/B; p-value < 0,001 = test zepsuty, wyniku nie interpretujesz |
| Winner's curse | istotny wynik przy wzroście mniejszym niż MDE zawyża wzrost — realny jest prawdopodobnie mniejszy |
| Analizuj raz | każde zerknięcie w trakcie z możliwością zatrzymania podnosi ryzyko fałszywego pozytywu |
