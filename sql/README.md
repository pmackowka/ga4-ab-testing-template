# SQL — dane do kalkulatorów testów A/B

Trzy zapytania BigQuery na eksporcie GA4 do kalkulatorów na pmdata.pl. Kolejność kroków i skrypty losujące wariant: [README główne](../README.md), [`gtm/`](../gtm/README.md). Wynik `03` dla wszystkich testów naraz, z testami danych: [projekt dbt](../dbt/README.md).

| Plik | Kiedy | Do kalkulatora |
|---|---|---|
| [`01_przed_testem.sql`](01_przed_testem.sql) | przed testem | Przed testem: Użytkownicy i Konwertujący w tygodniu (wiersz z planowaną liczbą tygodni), w trybie przychodu przychód na użytkownika i odchylenie |
| [`02_przychod_tygodniowy.sql`](02_przychod_tygodniowy.sql) | przed testem, opcjonalnie | oba: Tygodniowy przychód ze strony testowej (średnia albo mediana przy piku) |
| [`03_po_tescie_warianty.sql`](03_po_tescie_warianty.sql) | najwcześniej 3 dni po końcu testu | Po teście: Użytkownicy i Konwertujący A/B, w trybie przychodu przychód i odchylenie; plus kontrola jakości |

## Szybki start

1. Podmień `ab-test-sandbox.ga4_syntetyczny.events_*` (dane syntetyczne) na swój eksport GA4, np. `twoj-projekt.analytics_123456789.events_*` — w każdym pliku w dwóch miejscach.
2. Ustaw zmienne w bloku „DO UZUPEŁNIENIA” (opis przy każdej zmiennej); `ASSERT` zatrzyma zapytanie przy złej wartości albo brakujących dniach eksportu.
3. Uruchom i przepisz liczby do kalkulatora; przykładowy wynik jest na końcu każdego pliku.

Dlaczego okna, a nie tydzień: ludzie wracają, a każdy liczy się w oknie raz. Unikalnych „na tydzień” ubywa z długością okna, a CR rośnie, bo jest więcej czasu na zakup. Efekty się znoszą częściowo, więc liczysz je na danych, w oknie długości testu.

## Konwersja czy przychód na użytkownika

Oba kalkulatory mają przełącznik „Metryka”: wybierasz ją w planie i tę samą bierzesz do oceny.

- **Konwersja (CR)** = konwertujący / użytkownicy: czy więcej osób kupuje. Nie widzi koszyka — upsell z CR −2% i koszykiem +10% wyjdzie jako przegrana.
- **Przychód na użytkownika (RPU)** = przychód wariantu / jego użytkownicy = CR × przychód na kupującego. Łapie obie zmiany, bliżej mu do sprzedaży. Mianownik to wszyscy użytkownicy, także z 0 zł.
- **RPU potrzebuje więcej użytkowników**, bo przychód ma większy rozrzut niż „kupił / nie kupił”. Kohavi, Tang i Xu (*Trustworthy Online Controlled Experiments*) pokazują na kuponie, że wskaźnik zakupu (0/1) ma mniejszą wariancję niż przychód i szybciej wykrywa efekt; w rozdziale 18 (wariancja i czułość) zalecają przycinanie (capping) wartości skrajnych. Ile więcej, zależy od rozrzutu kwot: przy typowym nawet 2× przy tym samym MDE.
- **Przykład (test `ab2` na danych syntetycznych):** ta sama strona i MDE +10% to przy CR 49 807 użytkowników na wariant (2 tygodnie), przy RPU 87 600 (3 tygodnie). Wynik `03` po 2 tygodniach, który przy CR daje „Wdrażaj B”, przy RPU daje „Wstrzymaj decyzję”: 64 070 użytkowników to za mało dla planu RPU (zrzuty niżej).
- **Jedno duże zamówienie** potrafi przesądzić średnią, więc `01`, `03` i dbt przycinają przychód osoby do 99,9 percentyla kupujących, a zamówienie liczą raz na `transaction_id`. Metrykę ustalasz przed startem: wybór po wyniku tej, która wyszła istotna, to dwa testy zamiast jednego i większa szansa na fałszywego zwycięzcę.

## Kalkulator Przed testem

[pmdata.pl/kalkulatory/wielkosc-proby-test-ab](https://pmdata.pl/kalkulatory/wielkosc-proby-test-ab/) — ilu użytkowników potrzebuje test i ile tygodni potrwa przy Twoim ruchu.

Zrzuty w tej i następnej sekcji: test `ab2` (2026-09-07 – 2026-09-20) z danych syntetycznych, liczby z `01`, `02` i `03`.

Wyniki z BigQuery, z których pochodzą liczby w kalkulatorze niżej — [`01`](01_przed_testem.sql) (wiersz `weeks = 2`) i [`02`](02_przychod_tygodniowy.sql):

![Wynik zapytania 01 w BigQuery dla testu ab2: okna 1 i 2 tygodnie, 64 287 użytkowników i 2 056 konwertujących w tygodniu przy 2 tygodniach](../docs/img/bigquery-01-przed-testem.png)

![Wynik zapytania 02 w BigQuery dla testu ab2: tygodniowy przychód 572 968 zł, średnia i mediana](../docs/img/bigquery-02-przychod-tygodniowy.png)

![Kalkulator Przed testem dla testu ab2 w trybie konwersji: 49 807 użytkowników na wariant, test potrwa 2 tygodnie](../docs/img/przed-testem.png)

![Kalkulator Przed testem dla testu ab2 w trybie przychodu na użytkownika: 87 600 użytkowników na wariant, test potrwa 3 tygodnie](../docs/img/przed-testem-przychod.png)

- **MDE** — próg biznesowy, nie prognoza: najmniejszy wzrost wart czasu testu. Względny: +15% przy CR 2% to +0,30 pp. Optymizm skraca test, który przeoczy realny, mniejszy wzrost.
- **Poziom ufności i moc** — ufność chroni przed fałszywym alarmem (α = 1 − ufność: przy 95% co 20. test bez efektu pokaże różnicę), moc przed przeoczeniem (przy 80% wzrost równy MDE wykryjesz w 4 testach na 5). Wyższe = dłuższy test.
- **Liczba wariantów z kontrolą** — każde porównanie to kolejna szansa na fałszywy alarm, więc przy 3+ próg p-value to α / (k − 1) (Bonferroni): 3 warianty przy 95% → 0,025 i więcej użytkowników.
- **Rodzaj testu** — jednostronny wymaga ~21% mniej użytkowników, ale nie wykaże, że wariant szkodzi. Wybierasz przed testem: zmiana po wyniku robi z p = 0,09 wynik 0,045.
- **Limit tygodni i stan planu** — pełne tygodnie, najwyżej 8: dłużej kasowanie cookies miesza warianty, a sezonowość zmienia mierzone zachowanie. Ponad 6 tygodni = „Plan ryzykowny”, ponad limit = „Plan niewykonalny” z MDE wykrywalnym w limicie. „poza zasięgiem” w tabeli = realistycznego wzrostu nie wykryjesz.
- **RPU** — „Przychód na użytkownika (zł)” i „Odchylenie przychodu na użytkownika (zł)” z `01` (`revenue_per_user`, `revenue_sd`), już przycięte; kalkulator niczego nie przycina. Większy rozrzut wydłuża test, więc częściej wyjdzie „Plan ryzykowny” albo „niewykonalny”.
- **Przekazanie do „Po teście”** — „Użytkownicy na wariant” idą do „Wymagani użytkownicy na wariant”. W tej samej karcie przeglądarki „Po teście” wstawi plan przyciskiem „Wstaw z planu”.

## Kalkulator Po teście

[pmdata.pl/kalkulatory/istotnosc-testu-ab](https://pmdata.pl/kalkulatory/istotnosc-testu-ab/) — co zrobić z wariantem B. Na górze decyzja i skutek w złotówkach, w „Szczegóły obliczeń” liczby.

Wynik z BigQuery, z którego pochodzą liczby w kalkulatorze niżej — [`03`](03_po_tescie_warianty.sql):

![Wynik zapytania 03 w BigQuery dla testu ab2: kontrola 64 266 użytkowników i 2 038 konwertujących, wariant v1 64 070 i 2 313](../docs/img/bigquery-03-po-tescie.png)

![Kalkulator Po teście dla testu ab2 w trybie konwersji: Wdrażaj B, wzrost +13,84%](../docs/img/po-tescie.png)

![Kalkulator Po teście dla testu ab2 w trybie przychodu na użytkownika: wzrost istotny, ale decyzja wstrzymana, bo 2 tygodnie dały mniej użytkowników niż plan RPU](../docs/img/po-tescie-przychod.png)

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
