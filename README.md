# ab-test-bigquery

SQL pod BigQuery (eksport GA4), który krok po kroku liczy dane do dwóch kalkulatorów testów A/B:

- **[Przed testem A/B](https://pmdata.pl/kalkulatory/wielkosc-proby-test-ab/)** — ilu użytkowników potrzebujesz i ile tygodni potrwa test,
- **[Po teście A/B](https://pmdata.pl/kalkulatory/istotnosc-testu-ab/)** — czy wzrost jest istotny, jak duży może być i co zrobić z wariantem.

Każde zapytanie zaczyna się opisem pól kalkulatora, które wypełnia — tymi samymi nazwami, które widzisz na stronie. Ten plik tłumaczy pola, których z danych policzyć się nie da (MDE, poziom ufności, moc, rodzaj testu), i pojęcia z wyniku (p-value, przedział ufności, SRM).

Projekt jest jednocześnie materiałem do nauki: czytasz SQL i od razu widzisz, która kolumna trafia do którego pola i dlaczego liczy się ją właśnie tak.

## Kolejność pracy

| Krok | Zapytanie | Co dostajesz | Gdzie wpisujesz |
|---|---|---|---|
| 1 | `sql/01_przed_testem_tygodniowo.sql` | użytkownicy i konwertujący w tygodniu, kilka tygodni + średnia | Przed testem: „Użytkownicy w tygodniu”, „Konwertujący w tygodniu” |
| 2 | `sql/02_przed_testem_okno_testu.sql` | to samo dla okna o długości testu (powracający użytkownicy) | Przed testem — zamiast wartości z kroku 1, gdy test trwa 2+ tygodnie |
| 3 | — | ustawiasz MDE, ufność, moc, rodzaj testu, warianty, maks. czas | Przed testem — opis w „Słowniku” niżej |
| 4 | — | test trwa; nie zaglądasz do wyniku przed końcem | — |
| 5 | `sql/03_po_tescie_warianty.sql` | użytkownicy i konwertujący na wariant, kontrola przypisań | Po teście: „Użytkownicy A/B”, „Konwertujący A/B” |
| 6 | `sql/04_po_tescie_przychod_miesieczny.sql` | przychód z 30 dni od użytkowników strony testowej | Po teście: „Miesięczny przychód ze strony testowej” |

## Jak uruchomić

Domyślnie wszystkie zapytania działają na publicznym przykładowym eksporcie GA4 (`bigquery-public-data.ga4_obfuscated_sample_ecommerce`, sklep Google Merchandise Store, 2020-11-01 – 2021-01-31). Możesz je uruchomić bez własnych danych — potrzebujesz tylko projektu GCP z włączonym BigQuery (darmowy sandbox wystarczy).

- **Konsola BigQuery:** wklej cały plik (razem z `DECLARE`) i uruchom jako skrypt.
- **Terminal:**
  ```bash
  bq query --use_legacy_sql=false --project_id=TWOJ_PROJEKT < sql/01_przed_testem_tygodniowo.sql
  ```

Na własnych danych:

1. Podmień nazwę tabeli `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` na `projekt.analytics_XXXXXX.events_*`.
2. Ustaw parametry w sekcji `DECLARE` na górze pliku: daty, zdarzenie wejścia na stronę testową, zdarzenie konwersji.
3. W `03` ustaw `demo_mode = FALSE` i nazwę testu w `test_name`.
4. W `04` zmień `ecommerce.purchase_revenue_in_usd` na `ecommerce.purchase_revenue`.

Filtr `_TABLE_SUFFIX` w każdym zapytaniu ogranicza skanowane dane do wybranych dni — bez niego BigQuery czyta cały eksport i płacisz za wszystko. Tabele `events_intraday_*` wypadają z zakresu same, bo ich sufiks zaczyna się od litery.

## Mapa: pole kalkulatora → skąd wziąć wartość

### Przed testem

| Pole | Skąd |
|---|---|
| Użytkownicy w tygodniu | `01` → `users_weekly` (wiersz ŚREDNIA) albo `02` → `users_weekly_effective` |
| Konwertujący w tygodniu | `01` → `converters_weekly` (wiersz ŚREDNIA) albo `02` → `converters_weekly_effective` |
| Najmniejszy wzrost do wykrycia (MDE, %) | ustawiasz sam — [MDE](#mde--najmniejszy-wzrost-do-wykrycia) |
| Liczba wariantów razem z kontrolą | z projektu testu — [warianty](#liczba-wariantów-i-korekta-bonferroniego) |
| Poziom ufności | zwykle 95% — [poziom ufności](#poziom-ufności-i-błąd-i-rodzaju) |
| Moc testu | zwykle 80% — [moc](#moc-testu-i-błąd-ii-rodzaju) |
| Rodzaj testu | zwykle dwustronny — [rodzaj testu](#rodzaj-testu-dwustronny-czy-jednostronny) |
| Najdłużej możesz testować (tygodnie) | z kalendarza — [czas testu](#najdłużej-możesz-testować) |

### Po teście

| Pole | Skąd |
|---|---|
| Użytkownicy A (kontrola), Konwertujący A | `03` → wiersz „A (kontrola)”: `users`, `converters` |
| Użytkownicy B (wariant), Konwertujący B | `03` → wiersz „B (wariant …)”: `users`, `converters` |
| Liczba wariantów razem z kontrolą | ta sama co w planie |
| Poziom ufności, Rodzaj testu | te same co w planie — zmiana po zobaczeniu wyniku to naginanie wyniku |
| Dane z planu: użytkownicy na wariant, MDE | z kalkulatora Przed testem (przycisk „Wstaw z planu”, jeśli liczyłeś plan w tej samej karcie przeglądarki) |
| Miesięczny przychód ze strony testowej | `04` → `monthly_revenue` |

## Słownik

### Użytkownicy, nie sesje

Narzędzie do testów losuje ludzi (przez cookie), nie wizyty. Jedna osoba robi kilka sesji, a jej sesje są do siebie podobne — nie są niezależnymi obserwacjami. Kalkulator liczony na sesjach zaniża błąd standardowy, więc częściej ogłasza wzrost, którego nie ma. Dlatego wszędzie liczymy `COUNT(DISTINCT user_pseudo_id)`.

`user_pseudo_id` to przeglądarka, nie człowiek: telefon i laptop tej samej osoby to dwóch użytkowników. Narzędzie do testów myli się tak samo, więc plan i wynik zostają spójne.

### Konwertujący i CR

**Konwertujący** to użytkownik z co najmniej jedną konwersją po wejściu do testu — osoba, nie zamówienie. **CR (conversion rate)** = konwertujący / użytkownicy. Konwersja to dowolne zdarzenie, które mierzysz: zakup, telefon, wysłany formularz.

„Po wejściu” jest ważne: konwersja sprzed wejścia na stronę testową nie mogła zależeć od wariantu.

### MDE — najmniejszy wzrost do wykrycia

**MDE (minimum detectable effect)** to najmniejszy wzrost CR, który ma dla Ciebie znaczenie biznesowe — **nie wzrost, którego się spodziewasz**. Wpisywany w procentach względnych: +15% przy CR 2% oznacza CR wariantu 2,3%, czyli +0,3 punktu procentowego.

MDE najmocniej wpływa na długość testu: próba rośnie z kwadratem odwrotności efektu. Dwa razy mniejsze MDE = cztery razy więcej użytkowników.

Jak je wybrać, gdy biznes nie zna odpowiedzi:

1. **Od tego, co wykryjesz w dostępnym czasie** (najpraktyczniejsze). Kalkulator pokazuje tabelę „jakie MDE wykryjesz po każdym tygodniu”. Pytanie do biznesu brzmi wtedy: „czy ta zmiana realnie może dać +14%?”. Jeśli nie — test nie ma sensu w tym ruchu.
2. **Od progu opłacalności.** MDE = koszt zmiany / (przychód ze strony w okresie zwrotu). Przykład: zmiana za 60 000 zł, 2 mln zł przychodu miesięcznie, zwrot w 6 miesięcy → MDE = 0,5%.
3. **Od historii testów.** Jeśli wygrane testy w firmie dawały typowo +3–5%, MDE +20% oznacza, że takiego testu prawie nigdy nie wygrasz.

### Liczba wariantów i korekta Bonferroniego

Każde porównanie wariantu z kontrolą to osobna szansa na fałszywy alarm. Przy trzech wariantach (kontrola + 2) robisz dwa porównania, więc ryzyko, że któreś da fałszywy pozytyw, rośnie. **Korekta Bonferroniego** dzieli próg α przez liczbę porównań (k − 1): przy α = 0,05 i trzech wariantach próg dla każdego porównania to 0,025. Koszt: każdy wariant potrzebuje więcej użytkowników.

### Poziom ufności i błąd I rodzaju

**Poziom ufności = 1 − α.** Przy 95% (α = 0,05) w 1 teście na 20, w którym wariant naprawdę nic nie zmienia, ogłosisz wzrost, którego nie ma. To **fałszywy pozytyw**, czyli **błąd I rodzaju**. Wyższy poziom ufności (99%) chroni lepiej, ale wymaga więcej użytkowników.

### Moc testu i błąd II rodzaju

**Moc = 1 − β.** Przy 80% realny wzrost równy MDE wykryjesz w 4 testach na 5, a w piątym go przeoczysz. To **fałszywy negatyw**, czyli **błąd II rodzaju**. Wyższa moc (90%) rzadziej przeocza, ale wymaga więcej użytkowników.

Obie liczby razem — macierz błędów:

| | Wdrażasz wariant | Nie wdrażasz |
|---|---|---|
| **W rzeczywistości brak różnicy** | fałszywy pozytyw — błąd I rodzaju (α); chroni poziom ufności | trafna decyzja |
| **W rzeczywistości wariant lepszy** | trafna decyzja | fałszywy negatyw — błąd II rodzaju (β); chroni moc |

### Rodzaj testu: dwustronny czy jednostronny

- **Dwustronny** sprawdza wzrost i spadek. Domyślny i zalecany.
- **Jednostronny** sprawdza tylko wzrost. Potrzebuje ok. 21% mniej użytkowników, ale **nie wykryje, że wariant szkodzi** — spadek nigdy nie wyjdzie jako istotny.

Rodzaj testu wybierasz przed startem i nie zmieniasz po zobaczeniu wyniku. Te same dane (A 80 000 / 1 600, B 80 000 / 1 696) dają p-value 0,0911 dwustronnie (nieistotny) i 0,0455 jednostronnie („istotny”).

### Najdłużej możesz testować

Ile tygodni strona, ceny i kampanie mogą zostać bez zmian. Test zawsze trwa **pełne tygodnie**, bo w poniedziałek i w sobotę kupują inni ludzie. Testy dłuższe niż ~6 tygodni psuje kasowanie cookies (ITP w Safari, czyszczenie przeglądarki — powracający użytkownik staje się nowym i może trafić do drugiego wariantu) i sezonowość.

### p-value

Prawdopodobieństwo uzyskania takiego lub bardziej skrajnego wyniku **przy założeniu, że wzrostu nie ma** (H0). Wynik jest istotny statystycznie, gdy p-value jest poniżej progu α (zwykle 0,05).

p-value **nie jest** prawdopodobieństwem, że wariant jest lepszy. Zdanie „na 95% to zasługa zmiany” jest błędne.

### Przedział ufności — zakres możliwego wzrostu

Zakres wzrostów zgodnych z danymi. Jeśli obejmuje zero, test nie odróżnił wzrostu od jego braku. Ważniejszy niż sam werdykt: dwa wyniki „istotny” i „nieistotny” mogą mieć prawie ten sam zakres — wtedy oba mówią to samo: wzrost może być bliski zera.

### SRM — niezgodny podział użytkowników

**Sample ratio mismatch.** Przy podziale 50/50 grupy A i B powinny mieć prawie tyle samo użytkowników. Kalkulator sprawdza to testem χ²; przy p-value < 0,001 taka różnica prawie nie zdarza się przypadkiem — test jest zepsuty (błąd w losowaniu, przekierowaniach albo zbieraniu danych) i jego wyniku nie da się interpretować. Zapytanie `03` dodatkowo liczy użytkowników przypisanych do więcej niż jednego wariantu.

### Winner's curse

Jeśli test wyszedł istotny, ale zmierzony wzrost jest mniejszy niż MDE z planu, test miał przy takim wzroście słabą moc. Istotne wyniki takich testów systematycznie zawyżają wzrost — realny jest prawdopodobnie mniejszy niż zmierzony.

### Analizuj raz

Każde zerknięcie na wynik w trakcie testu z możliwością zatrzymania podnosi ryzyko fałszywego pozytywu ponad wybrane α. Wynik czytasz raz, po zebraniu zaplanowanej liczby użytkowników.

## Ograniczenia

- Konwersja w `01` jest liczona w obrębie tego samego tygodnia co wejście; w `03` — w całym okresie testu.
- `03` zakłada, że wariant jest zapisany w parametrze zdarzenia przypisania (`ab_variant`). Inne narzędzia (Optimizely, VWO, Firebase A/B Testing) zapisują go inaczej — dostosuj CTE `assignments`.
- Przeliczenie wzrostu na przychód zakłada, że wartość zamówienia się nie zmienia.

## Stan

Zapytania napisane, **jeszcze nie uruchomione** — w chwili pisania nie było dostępnego projektu GCP z włączonym BigQuery. Pierwsze uruchomienie na przykładowym eksporcie GA4 sprawdzi składnię i wyniki.
