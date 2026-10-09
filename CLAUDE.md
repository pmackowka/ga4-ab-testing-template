# CLAUDE.md — ab-test-bigquery

SQL pod BigQuery (eksport GA4), który liczy dane wejściowe do dwóch kalkulatorów testów A/B na pmdata.pl. Ten plik mówi, jak działają kalkulatory, skąd biorą się wzory i jak każde zapytanie mapuje się na pola — żeby nowa sesja zaczynała od meritum.

## Kalkulatory — gdzie żyją

Kalkulatory są w innym repozytorium: `/Users/p/Documents/dev/personal-page` (Astro, GitHub `pmackowka/personal-page`).

| Co | Plik w personal-page |
|---|---|
| Statystyka (czysta, bez DOM) | `src/utils/ab-stats.ts` |
| Testy ze złotymi wartościami (`npm test`) | `tests/ab-stats.test.ts` |
| Formatowanie pl-PL, walidacja pól, spacje tysięcy | `src/utils/calc-ui.ts` |
| Plan przekazywany między stronami (`sessionStorage`, klucz `calc-ab-plan`: `{ n, mdeRel }`) | `src/utils/calc-plan.ts` |
| Przed testem — `/kalkulatory/wielkosc-proby-test-ab/` | `src/pages/kalkulatory/wielkosc-proby-test-ab.astro` |
| Po teście — `/kalkulatory/istotnosc-testu-ab/` | `src/pages/kalkulatory/istotnosc-testu-ab.astro` |
| Lista kalkulatorów, karty na landingu | `src/data/calculators.ts`, `src/pages/kalkulatory/index.astro` |

Liczenie odbywa się w przeglądarce. Wpisane liczby nie trafiają do eventów analitycznych ani do URL; panele mają klasę `ph-no-capture` (PostHog ich nie nagrywa).

## Wzory (`ab-stats.ts`)

| Element | Wzór / metoda |
|---|---|
| Φ (dystrybuanta) | Hart w wersji Westa — podwójna precyzja |
| Φ⁻¹ | Acklam + jeden krok Halleya |
| Korekta Bonferroniego | α_adj = α / (k − 1), k = liczba wariantów z kontrolą |
| z_α | Φ⁻¹(1 − α_adj / s), s = 2 dwustronny, 1 jednostronny |
| Próba na wariant (= R `power.prop.test`) | n = [z_α·√(2·p̄(1−p̄)) + z_β·√(p₁(1−p₁) + p₂(1−p₂))]² / (p₂ − p₁)², p₂ = p₁·(1 + MDE), p̄ = (p₁+p₂)/2, w górę do liczby całkowitej |
| Wykrywalne MDE dla danego n | bisekcja po MDE, aż ciągłe n(MDE) = n |
| Czas testu | dokładnie = n·k / użytkownicy w tygodniu; pełne tygodnie = max(1, ceil) |
| Ocena | test z dla dwóch proporcji, SE niepoolowany: SE = √(pA(1−pA)/nA + pB(1−pB)/nB), z = (pB − pA)/SE |
| p-value | dwustronne 2·Φ(−\|z\|), jednostronne Φ(−z) (hipoteza: B lepsze) |
| Przedział ufności różnicy | dwustronny: poziom 1 − α_adj; jednostronny: 1 − 2·α_adj (np. 90%), żeby zgadzał się z werdyktem. Względny = przedział bezwzględny / pA |
| SRM | χ² dla podziału 50/50, 1 st. swobody; alarm przy p < 0,001 |

Złote wartości w testach (tolerancja: n ±1, p ±0,0001, CI ±0,0001 pp): CR 2%, +10%, dwustronnie → 80 682 na wariant; jednostronnie → 63 553; +15% → 36 693 / 28 903; +5% → 315 206. Wykrywalne MDE przy 40 000: 14,35% / 12,68%. Moc przy 40 000, 2% vs 2,2% → 0,5051. Ocena A 80 000/1 600, B 80 100/1 715 → p = 0,0475, CI [+0,0016; +0,2806] pp; B 1 710 → p = 0,0580; B 80 000/1 696 → p 0,0911 dwustronnie, 0,0455 jednostronnie.

## Przed testem — pola, domyślne dane, stany

| Pole | Domyślnie | Źródło w tym repo |
|---|---|---|
| Użytkownicy w tygodniu | 20 000 | `01` → `users_weekly` (ŚREDNIA) albo `02` → `users_weekly_effective` |
| Konwertujący w tygodniu (CR liczony z obu pól) | 400 | `01` → `converters_weekly` albo `02` → `converters_weekly_effective` |
| Najmniejszy wzrost do wykrycia (MDE, %, względnie) | 15 | — |
| Liczba wariantów razem z kontrolą | 2 | — |
| Poziom ufności 90 / 95 / 99 | 95 | — |
| Moc 80 / 90 | 80 | — |
| Rodzaj testu | dwustronny | — |
| Najdłużej możesz testować (tygodnie) | 4 | — |

Wynik domyślny: 36 693 na wariant, 3,67 tyg. → 4 tygodnie, „Plan wykonalny”. Tabela „co wykryjesz” pokazuje MDE po każdym tygodniu, do limitu.

Wskaźnik stanu (kolejność sprawdzania): ✕ **Plan niewykonalny**, gdy pełne tygodnie > limit (podpowiada MDE wykrywalne w limicie) → ! **Plan ryzykowny**, gdy > 6 tygodni (cookies, ITP, sezonowość) → ✓ **Plan wykonalny** (gdy < 2 tygodnie i limit ≥ 2 — zalecenie pełnych 2 tygodni). Plan zapisuje się do `sessionStorage` dopiero po zmianie pola.

## Po teście — pola, domyślne dane, stany

| Pole | Domyślnie | Źródło w tym repo |
|---|---|---|
| Użytkownicy A / B | 36 700 / 36 750 | `03` → `users` |
| Konwertujący A / B | 734 / 846 | `03` → `converters` |
| Liczba wariantów, poziom ufności, rodzaj testu | jak w planie | — |
| Dane z planu: użytkownicy na wariant, MDE (opcjonalne) | puste; przycisk „Wstaw z planu” | kalkulator Przed testem |
| Miesięczny przychód ze strony testowej (opcjonalny) | puste | `04` → `monthly_revenue` |

Wynik domyślny: „Wdrażaj B”, p-value 0,0048, wzrost +4,61% … +25,59%, SRM p = 0,85. Przychód 500 000 zł → od +23 055 do +127 965 zł, najbardziej prawdopodobnie +75 510 zł.

Wskaźnik odpowiada na pytanie „co zrobić z B” (kolejność sprawdzania):

| Stan | Warunek |
|---|---|
| ✕ Test zepsuty — powtórz test | SRM p < 0,001 (przychód wtedy ukryty) |
| ✕ Nie wdrażaj B | istotny spadek |
| ! Wstrzymaj decyzję | dane z planu wpisane ręcznie i niespójne (n z planu odbiega > 25% od n liczonego z MDE przy CR kontroli i mocy 80%); użytkowników < 95% planu; > 125% planu (test przedłużany „aż wyjdzie”); test jednostronny i B gorsze |
| ✓ Wdrażaj B, ale licz na mniej | istotny wzrost poniżej MDE z planu (winner's curse) albo dolna granica zakresu < 1% |
| ✓ Wdrażaj B | istotny wzrost bez zastrzeżeń |
| – Nie wdrażaj B jako zwycięzcy | wynik nieistotny; podaje zakres zmiany CR jako najgorszy scenariusz |

Plan wstawiony przyciskiem jest z definicji spójny, więc kontrola spójności działa tylko dla liczb wpisanych ręcznie. Przychód = przychód miesięczny × zakres wzrostu (nigdy jedna liczba); zakłada niezmienioną wartość zamówienia.

## SQL w tym repo

Scenariusz: e-commerce testuje kartę produktu. Wejście = `view_item`, konwersja = `purchase` (zdarzenia rekomendowane GA4, wpisane na stałe).

| Plik | Liczy | Kluczowa logika |
|---|---|---|
| `sql/01_przed_testem_tygodniowo.sql` | użytkownicy i konwertujący w kilku pełnych tygodniach + ŚREDNIA | pierwszy `view_item` w tygodniu → `purchase` po nim w tym samym tygodniu; `ASSERT` na poniedziałek |
| `sql/02_przed_testem_okno_testu.sql` | to samo w oknie o długości testu | powracający użytkownicy: `overlap_factor`; wartości `_effective` = okno / tygodnie |
| `sql/03_po_tescie_warianty.sql` | użytkownicy i konwertujący na wariant | pierwsze przypisanie; `purchase` po nim; wykluczenie przypisanych do 2+ wariantów. Wariant z `experience_impression` / `exp_variant_string` w formacie NARZĘDZIE-TEST-WARIANT (dokumentacja integracji GA4). `demo_mode = TRUE` — wariant z hasha `user_pseudo_id`, bo przykładowy eksport nie ma testu |
| `sql/04_po_tescie_przychod_miesieczny.sql` | przychód 30 dni przed testem | `purchase` po pierwszym `view_item`; w przykładowym eksporcie `purchase_revenue_in_usd`, we własnym `purchase_revenue` |

Wszystkie zapytania domyślnie czytają `bigquery-public-data.ga4_obfuscated_sample_ecommerce` (2020-11-01 – 2021-01-31).

## Stan

- **Zapytania nie zostały jeszcze uruchomione.** Konto GCP Piotra nie ma projektu z włączonym BigQuery (`eastern-fact-zw106` bez API). Po włączeniu: uruchom wszystkie cztery, popraw błędy, podmień przykładowe tabele na prawdziwe wyniki.
- Przykładowe tabele wyniku na dole każdego SQL mają liczby poglądowe, celowo zgodne z domyślnymi danymi kalkulatorów.

## Konwencje

- Kod i nazwy po angielsku, komentarze po polsku.
- Podział wiedzy: **SQL** — krótki nagłówek (scenariusz, co liczy, kolumna → pole kalkulatora), jednolinijkowe komentarze przy CTE, przykładowa tabela wyniku na dole. **README** — kroki, definicje metryk, słownik pól w tabelach. Nie rozbudowuj komentarzy w SQL ponad to — decyzja Piotra.
- Nazwy pól i komunikatów kalkulatora cytuj dokładnie tak, jak są na stronie.
- Opis repozytorium i tematy na GitHubie po angielsku; reszta (README, commity) po polsku.
- Repozytorium prywatne.

## Git — pod odznaki GitHub

Każda zmiana: gałąź → atomowe commity z `Co-Authored-By` → push gałęzi → `gh pr create` → `gh pr merge --merge --delete-branch`. Daje Pull Shark, YOLO i Pair Extraordinaire. To repo nie ma deployu, więc PR nic nie kosztuje. Commit i push tylko na polecenie Piotra.

## Ograniczenia, o których wiesz

- Przedział względny = przedział bezwzględny / CR kontroli (bez niepewności CR kontroli).
- Przy 3+ wariantach ocena obejmuje jedną parę z kontrolą; SRM zakłada podział 50/50.
- Progi porównania z planem (5%, 25%) i moc 80% w kontroli spójności są umowne.
- `user_pseudo_id` to przeglądarka, nie osoba.
