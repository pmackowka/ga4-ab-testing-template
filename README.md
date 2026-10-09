# ab-test-bigquery

SQL pod BigQuery (eksport GA4) do dwóch kalkulatorów testów A/B na pmdata.pl:

- [Przed testem](https://pmdata.pl/kalkulatory/wielkosc-proby-test-ab/) — ilu użytkowników potrzebujesz i ile tygodni potrwa test,
- [Po teście](https://pmdata.pl/kalkulatory/istotnosc-testu-ab/) — czy różnica jest istotna i jak duża może naprawdę być.

Scenariusz: e-commerce testuje kartę produktu. Wejście do testu to `view_item`, konwersja to `purchase`. Każde zapytanie zwraca tylko kolumny do wpisania w kalkulator; opis i przykład wyniku stoją tuż nad końcowym `SELECT`.

## Szybki start

1. Podmień tabelę `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` na swój eksport GA4 (`<projekt>.analytics_<id>.events_*`) we wszystkich trzech plikach.
2. Ustaw parametry `DECLARE` na górze pliku (tabela niżej).
3. Uruchom zapytanie i przepisz liczby do pól kalkulatora według kroków.

Bez zmian zapytania liczą na publicznym przykładowym eksporcie GA4 (2020-11-01 – 2021-01-31) — wystarczy, żeby zobaczyć kształt wyniku.

| Plik | Parametr | Co ustawiasz |
|---|---|---|
| `01` | `window_start` | poniedziałek, od którego liczysz okna (zapytanie sprawdza dzień tygodnia) |
| `01` | `max_weeks` | ile okien policzyć: 1, 2, … tygodni |
| `02` | `test_start`, `test_end` | pierwszy i ostatni dzień testu, pełne tygodnie |
| `02` | `test_id` | środkowa część `exp_variant_string` (`NARZĘDZIE-TEST-WARIANT`) |
| `02` | `control_variant` | wariant kontrolny, zwykle `A` |
| `02` | `demo_mode` | `TRUE` tylko na danych przykładowych (wariant z hasha `user_pseudo_id`); na własnych `FALSE` |
| `03` | `window_end` | dzień przed startem testu |
| `03` | `window_days` | długość okna przychodu, domyślnie 30 dni |

## Kroki

| # | Kiedy | Plik | Wynik → pole kalkulatora |
|---|---|---|---|
| 1 | przed testem | [`sql/01_przed_testem.sql`](sql/01_przed_testem.sql) | wiersz z planowaną liczbą tygodni → Przed testem: Użytkownicy w tygodniu, Konwertujący w tygodniu |
| 2 | przed testem | kalkulator | ustawiasz pola bez SQL; gdy kalkulator policzy inny czas testu — wracasz do wyniku `01` i bierzesz wiersz z tym czasem |
| 3 | w trakcie | — | nie zaglądasz do wyniku |
| 4 | po teście | [`sql/02_po_tescie_warianty.sql`](sql/02_po_tescie_warianty.sql) | Po teście: Użytkownicy A/B, Konwertujący A/B |
| 5 | po teście | [`sql/03_po_tescie_przychod_miesieczny.sql`](sql/03_po_tescie_przychod_miesieczny.sql) | Po teście: Miesięczny przychód ze strony testowej |

Dlaczego okna, a nie jeden tydzień: test trwa kilka tygodni, a ludzie wracają. Każdy użytkownik liczy się w oknie raz, więc w oknie 4 tygodni unikalnych jest mniej niż 4 × tydzień — wartość „na tydzień” (okno / liczba tygodni) spada z długością okna. CR rośnie, bo użytkownik ma więcej czasu na zakup. Oba efekty działają w przeciwne strony, więc liczysz je na danych, w oknie tak długim jak test.

## Kalkulator Przed testem — pola

| Pole | Skąd | Co znaczy | Typowo / uwaga |
|---|---|---|---|
| Użytkownicy w tygodniu | `01` → `users_per_week` | unikalni użytkownicy, którzy weszli na stronę objętą testem, łącznie dla wszystkich wariantów | nie sesje — test losuje ludzi |
| Konwertujący w tygodniu | `01` → `converters_per_week` (ten sam wiersz) | ilu z nich kupiło po wejściu; osoby, nie zamówienia | CR liczy kalkulator z obu pól, żeby plan i ocena miały tę samą populację |
| Najmniejszy wzrost do wykrycia (MDE) | decyzja | najmniejszy względny wzrost CR, który ma znaczenie biznesowe — nie ten, którego się spodziewasz | +10–20%; 2× mniejsze MDE = ~4× więcej użytkowników |
| Liczba wariantów razem z kontrolą | decyzja | przy 3+ próg α dzielony przez k − 1 (korekta Bonferroniego) | 2 |
| Poziom ufności (1 − α) | decyzja | chroni przed fałszywym pozytywem: przy 95% w 1 teście na 20 ogłosisz wzrost, którego nie ma | 95% |
| Moc testu (1 − β) | decyzja | chroni przed fałszywym negatywem: przy 80% realny wzrost równy MDE wykryjesz w 4 testach na 5 | 80% |
| Rodzaj testu | decyzja | dwustronny sprawdza wzrost i spadek, jednostronny tylko wzrost | dwustronny; jednostronny skraca test o ~21%, ale szkodę pokaże jako „brak efektu” |
| Najdłużej możesz testować | decyzja | pełne tygodnie, w których strona, ceny i kampanie się nie zmienią | 2–6 tyg.; dłużej psują kasowanie cookies i sezonowość |

Wynik: użytkownicy na wariant i łącznie, czas w pełnych tygodniach, ocena planu (wykonalny / ryzykowny / niewykonalny) oraz tabela MDE wykrywalnego po każdym tygodniu. Gdy plan jest niewykonalny, kalkulator podaje MDE, które wykryjesz w swoim limicie tygodni.

## Kalkulator Po teście — pola

| Pole | Skąd | Co znaczy | Uwaga |
|---|---|---|---|
| Użytkownicy A / B | `02` → `users` | unikalni użytkownicy od pierwszego przypisania do wariantu | osoby przypisane do 2+ wariantów zapytanie wyklucza |
| Konwertujący A / B | `02` → `converters` | użytkownicy z `purchase` po pierwszym przypisaniu | zakup sprzed przypisania nie zależał od wariantu, więc się nie liczy |
| Liczba wariantów, poziom ufności, rodzaj testu | z planu | te same co w kalkulatorze Przed testem | zmiana po zobaczeniu wyniku to naginanie wyniku |
| Użytkownicy na wariant, MDE (opcjonalne) | kalkulator Przed testem | plan testu; przycisk „Wstaw z planu” przenosi go w tej samej karcie przeglądarki | włączają kontrolę: za mało / za dużo użytkowników względem planu, wzrost poniżej MDE |
| Miesięczny przychód ze strony testowej (opcjonalne) | `03` → `monthly_revenue` | przychód od użytkowników, którzy weszli na stronę objętą testem | kalkulator mnoży go przez zakres wzrostu — dostajesz przedział złotówek, nie jedną liczbę |

## Definicje metryk

| Metryka | Definicja | Kolumna |
|---|---|---|
| Użytkownicy | unikalni `user_pseudo_id` od pierwszego `view_item` w oknie (przed testem; na tydzień = okno / liczba tygodni) albo od pierwszego przypisania do wariantu (po teście). Nie sesje: sesje jednej osoby nie są niezależne | `users_per_week`, `users` |
| Konwertujący | użytkownicy z `purchase` po pierwszym wejściu; osoby, nie zamówienia | `converters_per_week`, `converters` |
| CR | konwertujący / użytkownicy | — (liczy kalkulator) |
| Przychód miesięczny | przychód z `purchase` po pierwszym `view_item`, `window_days` dni przed testem; w przykładzie `purchase_revenue_in_usd`, na własnym eksporcie `purchase_revenue` | `monthly_revenue` |
| Wielokrotnie przypisani | użytkownicy z 2+ wariantami (wyczyszczone cookies, błąd w tagu); wykluczeni z wyniku `02` | — |

## Jak czytać wynik po teście

| Pojęcie | Znaczenie |
|---|---|
| p-value | prawdopodobieństwo takiego lub bardziej skrajnego wyniku, gdyby wzrostu nie było; istotny, gdy < α. Nie jest prawdopodobieństwem, że wariant jest lepszy |
| Zakres wzrostu (przedział ufności) | wzrosty zgodne z danymi; obejmuje zero = wzrostu nie da się odróżnić od przypadku. Przy teście jednostronnym przedział 90% (dla 95% ufności), zgodny z werdyktem |
| SRM | nierówny podział użytkowników A/B; p-value < 0,001 = test zepsuty, wyniku nie interpretujesz |
| Winner's curse | istotny wynik przy wzroście mniejszym niż MDE zawyża wzrost — realny jest prawdopodobnie mniejszy |
| Analizuj raz | każde zerknięcie w trakcie z możliwością zatrzymania podnosi ryzyko fałszywego pozytywu |

## Ograniczenia

- `user_pseudo_id` to przeglądarka, nie osoba: ten sam człowiek na telefonie i laptopie to dwóch użytkowników.
- SRM zakłada podział 50/50; przy 3+ wariantach kalkulator ocenia jedną parę z kontrolą.
- Wariant w `02` pochodzi z `experience_impression` / `exp_variant_string` ([integracja GA4](https://developers.google.com/analytics/devguides/collection/ga4/integration)); inne narzędzie testowe = inny warunek w CTE `assignments`.
