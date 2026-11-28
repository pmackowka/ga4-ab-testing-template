# SQL — dane do kalkulatorów testów A/B

Trzy zapytania BigQuery na eksporcie GA4 do kalkulatorów na pmdata.pl. Kolejność kroków i skrypty losujące wariant: [README główne](../README.md), [`gtm/`](../gtm/README.md). Wynik `03` dla wszystkich testów naraz, z testami danych: [projekt dbt](../dbt/README.md).

| Plik | Kiedy | Do kalkulatora |
|---|---|---|
| [`01_przed_testem.sql`](01_przed_testem.sql) | przed testem | Przed testem: Użytkownicy i Konwertujący w tygodniu (wiersz z planowaną liczbą tygodni), w trybie przychodu przychód na użytkownika i odchylenie |
| [`02_przychod_tygodniowy.sql`](02_przychod_tygodniowy.sql) | przed testem, opcjonalnie | oba: Tygodniowy przychód ze strony testowej (średnia albo mediana przy piku) |
| [`03_po_tescie_warianty.sql`](03_po_tescie_warianty.sql) | najwcześniej 3 dni po końcu testu | Po teście: Użytkownicy i Konwertujący A/B, w trybie przychodu przychód i odchylenie; plus kontrola jakości |

## Szybki start

1. Podmień `ab-test-sandbox.ga4_syntetyczny.events_*` (dane syntetyczne) na swój eksport GA4, np. `twoj-projekt.analytics_123456789.events_*` — w każdym pliku w dwóch miejscach.
2. Ustaw zmienne `DECLARE` na początku pliku (opis w tabeli niżej); `ASSERT` zatrzyma zapytanie przy złej wartości albo brakujących dniach eksportu.
3. Uruchom i przepisz liczby do kalkulatora; przykładowe wyniki są w sekcji „Przykładowe wyniki” niżej.

Dlaczego okna, a nie tydzień: ludzie wracają, a każdy liczy się w oknie raz. Unikalnych „na tydzień” ubywa z długością okna, a CR rośnie, bo jest więcej czasu na zakup. Efekty się znoszą częściowo, więc liczysz je na danych, w oknie długości testu.

## Zmienne `DECLARE`

Domyślne wartości liczą test `ab2` na danych syntetycznych. Kolumny rejestru to `dbt/seeds/rejestr_testow.csv`.

| Plik | Zmienna | Co wpisać |
|---|---|---|
| `01` | `window_start` | poniedziałek, od którego liczysz ruch: `start_testu` planowanego testu minus 7 × `max_weeks` dni |
| `01` | `max_weeks` | ile tygodni okna policzyć (1–8, tyle co limit w kalkulatorze); wynik ma wiersz dla 1…`max_weeks` |
| `01` | `test_start` | `start_testu`: poniedziałek, w którym ruszy test; okno musi się skończyć przed nim |
| `02` | `window_end` | niedziela tuż przed startem testu (`start_testu` minus 1 dzień), ostatni dzień okna |
| `02` | `window_weeks` | ile pełnych tygodni wstecz od `window_end`, tyle samo co `max_weeks` w `01` |
| `03` | `test_start` | `start_testu`: poniedziałek, w który opublikowano tag testu |
| `03` | `test_end` | `koniec_testu`: niedziela, ostatni dzień testu, co najmniej 3 dni temu |
| `03` | `test_name` | `slot`: `ab1`…`ab10`, `TEST` w tagu i nazwa parametru eventu |
| `03` | `control_variant` | `wariant_kontrolny`, jeden z `variants` |
| `03` | `variants` | `warianty`: wszystkie warianty jak `VARIANTS` w tagu; inny wariant w danych przerywa zapytanie |
| `03` | `conversion_event` | `zdarzenie_konwersji` |
| `03` | `exposure_events` | `zdarzenia_ekspozycji`: zdarzenia, na których użytkownik wchodzi do testu (pierwsze z wariantem) |

`01` liczy każdą osobę raz w oknie k tygodni, od pierwszego `view_item`, z zakupami do końca okna — tak jak wynik testu. `03` wymaga w GTM eventu `ab_assign` z `ab_test` i `ab_variant` oraz parametru slotu na wszystkich eventach. Pierwszy test to A/A w `ab1`: wynik ma być nieistotny i bez SRM, inaczej konfiguracja jest zła.

## Przykładowe wyniki

Test `ab2` na danych syntetycznych, domyślne parametry; prawdziwy efekt v1 to +10%. To te same liczby co przykłady w kalkulatorach na pmdata.pl.

`01`, okno 2026-08-24 – 2026-09-06:

| weeks | users_per_week | converters_per_week | revenue_per_user | revenue_sd |
|---|---|---|---|---|
| 1 | 67 182 | 2 098 | 8.56 | 64.24 |
| 2 | 64 287 | 2 056 | 8.89 | 66.41 |

`revenue_per_user` i `revenue_sd` dotyczą całego okna, nie tygodnia.

`02`, to samo okno: `weekly_revenue` 572 968, `weekly_revenue_median` 572 968. Przy 2 tygodniach mediana równa się średniej; pik (np. 4 tygodnie po 100 000 i Black Friday 225 000 → 125 000 vs 100 000) widać dopiero od 3 tygodni okna.

`03`, test 2026-09-07 – 2026-09-20:

| calculator_field | users | converters | revenue | revenue_per_user | revenue_sd | excluded_mixed | reassigned | no_assignment |
|---|---|---|---|---|---|---|---|---|
| A (kontrola) | 64 266 | 2 038 | 564 521.87 | 8.78 | 67.30 | 68 | 143 | 148 |
| B (wariant v1) | 64 070 | 2 313 | 638 626.47 | 9.97 | 70.79 | 85 | 161 | 143 |

Kontrola jakości nie idzie do kalkulatora. `excluded_mixed` to osoby z 2+ wariantami, wyjęte z `users`; różnica między wierszami większa niż 2 × √(suma obu) jest podejrzana (tu 17 < 25, w normie). `reassigned` to 2+ `ab_assign` (ciasteczko testu zniknęło, tag losował ponownie), `no_assignment` to wariant bez `ab_assign` (nowe `_ga` albo zgubiony hit).

## Kontrola `02`: pierwsza niepusta kwota

[`check_02_null_revenue.sql`](check_02_null_revenue.sql) tworzy zbiór `check_sql02` z siedmioma dziennymi tabelami (2026-08-31 – 2026-09-06): jeden użytkownik, `view_item`, a po nim zamówienie `T1` wysłane dwa razy, najpierw bez kwoty, potem ze 100 zł. Kontrola puszcza na nim plik `02` z repo, z podmienionym zbiorem i `window_weeks = 1`. W katalogu głównym repo, w swojej kopii z własnym projektem w miejscu `ab-test-sandbox`:

```bash
bq --project_id=ab-test-sandbox --location=EU query --use_legacy_sql=false < sql/check_02_null_revenue.sql
sed -e 's/ga4_syntetyczny/check_sql02/g' -e 's/window_weeks INT64 DEFAULT 2/window_weeks INT64 DEFAULT 1/' sql/02_przychod_tygodniowy.sql |
  bq --project_id=ab-test-sandbox --location=EU query --use_legacy_sql=false --format=csv
bq --project_id=ab-test-sandbox rm -r -f -d check_sql02
```

Oczekiwany wynik: `weekly_revenue` 100, `weekly_revenue_median` 100. Zera oznaczają, że `02` zgubiło kwotę z drugiego zgłoszenia. Jeśli w `02` masz już swoją tabelę zamiast `ga4_syntetyczny`, `sed` jej nie podmieni.

Kontrola jest ręczna: uruchamiaj ją po każdej zmianie `02`. Zmiana samego `sql/` nie odpala [`dbt-ci-cd.yml`](../.github/workflows/dbt-ci-cd.yml).

## Konwersja czy przychód na użytkownika

Oba kalkulatory mają przełącznik „Metryka”: wybierasz ją w planie i tę samą bierzesz do oceny.

- **Konwersja (CR)** = konwertujący / użytkownicy: czy więcej osób kupuje. Nie widzi koszyka — upsell z CR −2% i koszykiem +10% wyjdzie jako przegrana.
- **Przychód na użytkownika (RPU)** = przychód wariantu / jego użytkownicy = CR × przychód na kupującego. Łapie obie zmiany, bliżej mu do sprzedaży. Mianownik to wszyscy użytkownicy, także z 0 zł.
- **RPU potrzebuje więcej użytkowników**, bo przychód ma większy rozrzut niż „kupił / nie kupił”. Kohavi, Tang i Xu (*Trustworthy Online Controlled Experiments*) pokazują na kuponie, że wskaźnik zakupu (0/1) ma mniejszą wariancję niż przychód i szybciej wykrywa efekt; w rozdziale 18 (wariancja i czułość) zalecają przycinanie (capping) wartości skrajnych. Ile więcej, zależy od rozrzutu kwot: przy typowym nawet 2× przy tym samym MDE.
- **Przykład (test `ab2` na danych syntetycznych):** ta sama strona i MDE +10% to przy CR 49 807 użytkowników na wariant (2 tygodnie), przy RPU 87 600 (3 tygodnie). Wynik `03` po 2 tygodniach, który przy CR daje „Wdrażaj B”, przy RPU daje „Wstrzymaj decyzję”: 64 070 użytkowników to za mało dla planu RPU.
- **Jedno duże zamówienie** potrafi przesądzić średnią, więc `01`, `03` i dbt przycinają przychód osoby do 99,9 percentyla kupujących, a zamówienie liczą raz na `transaction_id`. `02` też liczy zamówienie raz, z pierwszą niepustą kwotą po pierwszym `view_item`, ale niczego nie przycina. Metrykę ustalasz przed startem: wybór po wyniku tej, która wyszła istotna, to dwa testy zamiast jednego i większa szansa na fałszywego zwycięzcę.

## Kalkulator Przed testem

[pmdata.pl/kalkulatory/wielkosc-proby-test-ab](https://pmdata.pl/kalkulatory/wielkosc-proby-test-ab/) — ilu użytkowników potrzebuje test i ile tygodni potrwa przy Twoim ruchu.

- **MDE** — próg biznesowy, nie prognoza: najmniejszy wzrost wart czasu testu. Względny: +15% przy CR 2% to +0,30 pp. Optymizm skraca test, który przeoczy realny, mniejszy wzrost.
- **Poziom ufności i moc** — ufność chroni przed fałszywym alarmem (α = 1 − ufność: przy 95% co 20. test bez efektu pokaże różnicę), moc przed przeoczeniem (przy 80% wzrost równy MDE wykryjesz w 4 testach na 5). Wyższe = dłuższy test.
- **Liczba wariantów z kontrolą** — każde porównanie to kolejna szansa na fałszywy alarm, więc przy 3+ próg p-value to α / (k − 1) (Bonferroni): 3 warianty przy 95% → 0,025 i więcej użytkowników.
- **Rodzaj testu** — jednostronny wymaga ~21% mniej użytkowników, ale nie wykaże, że wariant szkodzi. Wybierasz przed testem: zmiana po wyniku robi z p = 0,09 wynik 0,045.
- **Limit tygodni i stan planu** — pełne tygodnie, najwyżej 8: dłużej kasowanie cookies miesza warianty, a sezonowość zmienia mierzone zachowanie. Ponad 6 tygodni = „Plan ryzykowny”, ponad limit = „Plan niewykonalny” z MDE wykrywalnym w limicie. „poza zasięgiem” w tabeli = realistycznego wzrostu nie wykryjesz.
- **RPU** — „Przychód na użytkownika (zł)” i „Odchylenie przychodu na użytkownika (zł)” z `01` (`revenue_per_user`, `revenue_sd`), już przycięte; kalkulator niczego nie przycina. Większy rozrzut wydłuża test, więc częściej wyjdzie „Plan ryzykowny” albo „niewykonalny”.
- **Przekazanie do „Po teście”** — „Użytkownicy na wariant” idą do „Wymagani użytkownicy na wariant”. W tej samej karcie przeglądarki „Po teście” wstawi plan przyciskiem „Wstaw z planu”.

## Kalkulator Po teście

[pmdata.pl/kalkulatory/istotnosc-testu-ab](https://pmdata.pl/kalkulatory/istotnosc-testu-ab/) — co zrobić z wariantem B. Na górze decyzja i skutek w złotówkach, w „Szczegóły obliczeń” liczby.

- **Dane z planu (opcjonalne)** — wymagani użytkownicy na jeden wariant (nie tygodniowy ruch ani suma) i MDE z „Przed testem”. Bez nich werdykt zależy tylko od p-value, łatwego do oszukania zaglądaniem w trakcie; z nimi kalkulator wstrzymuje decyzję, gdy test zatrzymano przed 95% planu albo przedłużono ponad 125%, a ręcznie wpisane liczby sprawdza z MDE przy mocy 80% (rozjazd > 25% = ostrzeżenie).
- **p-value** — prawdopodobieństwo wyniku co najmniej tak skrajnego, gdyby wzrostu nie było, a nie tego, że B jest lepsze. Kalkulator pokazuje dwu- i jednostronne, werdykt bierze rodzaj testu z planu.
- **Zakres możliwego wzrostu** — przedział ufności z planu (przy 3+ wariantach po Bonferronim: 95% → 97,5%; jednostronny: 1 − 2α, czyli 90%). Obejmuje zero = może być wzrost, brak zmiany albo spadek.
- **Wpływ na przychód** — przychód tygodniowy × zakres wzrostu; do budżetu dolna granica. Przy alarmie SRM bez złotówek. Tryb konwersji zakłada niezmienioną wartość zamówienia, tryb RPU obejmuje zmianę koszyka.
- **RPU** — „Przychód na użytkownika A / B (zł)” i „Odchylenie przychodu A / B (zł)” z `03` (`revenue_per_user`, `revenue_sd`), już przycięte. Ocena to test z dla różnicy średnich; werdykt, zakres i SRM czytasz tak samo, zakres jest szerszy niż przy CR.
- **Winner's curse** — istotny wzrost mniejszy niż MDE = słaba moc, a istotne wyniki takich testów zawyżają wzrost. Stąd „Wdrażaj B, ale licz na mniej, niż zmierzono”.
- **SRM (sample ratio mismatch)** — czy A i B dostały po równo (50/50). Alarm przy p < 0,001 = błąd losowania albo danych (np. B ładuje się wolniej i gubi użytkowników); wyniku nie interpretujesz.
- **Mniej niż 10 konwersji** (albo osób bez konwersji) w wariancie, tryb konwersji — test z jest wtedy niewiarygodnym przybliżeniem. Istotny wynik → Wstrzymaj decyzję, nieistotny → ostrzeżenie.
- **Stany wyniku** — pierwszy pasujący wygrywa: ✕ Test zepsuty (SRM) → ✕ Nie wdrażaj B (istotny spadek) → ! Wstrzymaj decyzję (< 10 konwersji przy istotnym wyniku, niespójny plan, poza 95–125% planu albo jednostronny i B gorsze) → ✓ Wdrażaj B, ale licz na mniej (wzrost < MDE albo dolna granica < 1%) → ✓ Wdrażaj B → – Nie wdrażaj B jako zwycięzcy (nieistotny).

## Ograniczenia

- `user_pseudo_id` to przeglądarka, nie osoba (telefon i laptop to dwóch użytkowników). Test obejmuje tylko osoby ze zgodą na ciasteczka.
- Ocena to test z (przybliżenie normalne). SRM zakłada 50/50, przy 3+ wariantach kalkulator ocenia jedną parę z kontrolą.
