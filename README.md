# ab-test-bigquery

SQL pod BigQuery (eksport GA4) do dwóch kalkulatorów testów A/B na pmdata.pl, plus [skrypty GTM](#skrypty-gtm), które losują wariant:

- [Przed testem](https://pmdata.pl/kalkulatory/wielkosc-proby-test-ab/) — ilu użytkowników potrzebujesz i ile tygodni potrwa test,
- [Po teście](https://pmdata.pl/kalkulatory/istotnosc-testu-ab/) — czy różnica jest istotna i jak duża może naprawdę być.

Scenariusz: e-commerce testuje kartę produktu. Wejście do testu to `view_item`, konwersja to `purchase`. Każde zapytanie zwraca tylko kolumny do wpisania w kalkulator; opis i przykład wyniku stoją tuż nad końcowym `SELECT`.

## Szybki start

1. Podmień tabelę `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` na swój eksport GA4 (`<projekt>.analytics_<id>.events_*`) we wszystkich trzech plikach — w `02` w dwóch miejscach.
2. Ustaw parametry `DECLARE` na górze pliku (lista niżej).
3. Uruchom zapytanie i przepisz liczby do pól kalkulatora według kroków.

Bez zmian zapytania liczą na publicznym przykładowym eksporcie GA4 (2020-11-01 – 2021-01-31) — wystarczy, żeby zobaczyć kształt wyniku.

- `01` · `window_start` — poniedziałek, od którego liczysz okna (zapytanie sprawdza dzień tygodnia)
- `01` · `max_weeks` — ile okien policzyć: 1, 2, … tygodni, najwyżej 8 (tyle co limit w kalkulatorze); okno nie może sięgać w okres testu (domyślnie 5 — przykładowy test startuje 2020-12-07)
- `01` · `test_start` — pierwszy dzień testu; zapytanie przerywa się, gdy okno w niego sięga
- `02` · `test_start`, `test_end` — pierwszy (poniedziałek) i ostatni (niedziela) dzień testu; zapytanie sprawdza oba
- `02` · `test_name` — wartość parametru `ab_test`, czyli klucz ciasteczka z tagu GTM: numer testu `ab1`, `ab2`, `ab3`… ([wariant z first-party cookie](https://pmdata.pl/artykuly/wlasne-testy-ab-gtm-firebase/))
- `02` · `control_variant` — wartość `ab_variant` grupy kontrolnej: `v0`, czyli wersja dotychczasowa; gdy nie ma jej w danych, zapytanie przerywa się błędem
- `02` · `exposure_events` — eventy, od których użytkownik wchodzi do testu (punkt ekspozycji), domyślnie `ab_assign` i `view_item`; `ab_assign` usuń, gdy losujesz wcześniej niż na stronie testowej
- `02` · `demo_mode` — `TRUE` tylko na danych przykładowych: nie mają testu, więc wariant symuluje hash `user_pseudo_id`; na własnych `FALSE` — wariant losuje GTM, a zapytanie czyta go z `ab_variant`. Gdy przy `TRUE` dane mają parametr `ab_variant`, zapytanie przerywa się błędem
- `03` · `window_end` — dzień przed startem testu
- `03` · `window_weeks` — ile pełnych tygodni przed testem uśrednić, domyślnie 4

## Kroki

```mermaid
flowchart LR
    A["01 + 03<br/>SQL"] --> B["Kalkulator<br/>Przed testem"] --> C["GTM<br/>start testu"] --> D["Test trwa<br/>nie zaglądasz"] --> E["02<br/>SQL"] --> F["Kalkulator<br/>Po teście"]
```

1. **Przed testem** · [`01`](sql/01_przed_testem.sql) — wiersz z planowaną liczbą tygodni wpisujesz w Przed testem: Użytkownicy w tygodniu, Konwertujący w tygodniu.
2. **Przed testem** · [`03`](sql/03_przychod_tygodniowy.sql) — wynik wpisujesz w Przed testem: Tygodniowy przychód ze strony testowej (opcjonalnie).
3. **Przed testem** · kalkulator — ustawiasz pozostałe pola ([opis](#kalkulator-przed-testem)); gdy kalkulator policzy inny czas testu, wracasz do wyniku `01` i bierzesz wiersz z tym czasem.
4. **W trakcie** — nie zaglądasz do wyniku.
5. **Po teście** · [`02`](sql/02_po_tescie_warianty.sql) — wynik wpisujesz w Po teście: Użytkownicy A/B, Konwertujący A/B.
6. **Po teście** · wynik `03` z kroku 2 — wpisujesz w Po teście: Tygodniowy przychód ze strony testowej. Ta sama liczba, bo okno kończy się przed startem testu.

Dlaczego okna, a nie jeden tydzień: test trwa kilka tygodni, a ludzie wracają. Każdy użytkownik liczy się w oknie raz, więc w oknie 4 tygodni unikalnych jest mniej niż 4 × tydzień — wartość „na tydzień” (okno / liczba tygodni) spada z długością okna. CR rośnie, bo użytkownik ma więcej czasu na zakup. Oba efekty działają w przeciwne strony, więc liczysz je na danych, w oknie tak długim jak test.

## Skrypty GTM

Folder [`gtm/`](gtm/) losuje wariant w przeglądarce, zapisuje go w first-party cookie i wysyła `ab_assign` ([metoda z artykułu](https://pmdata.pl/artykuly/wlasne-testy-ab-gtm-firebase/)). SQL niczego nie losuje — `02` czyta wariant z parametru `ab_variant`.

| Plik | Klucz | Co robi | Gdzie w GTM |
|---|---|---|---|
| [`01_dwa_warianty.html`](gtm/01_dwa_warianty.html) | `ab1` | `v0`/`v1` po 50%, cały ruch strony testowej | Tag → Custom HTML |
| [`02_trzy_warianty.html`](gtm/02_trzy_warianty.html) | `ab2` | `v0`/`v1`/`v2` po 1/3 | Tag → Custom HTML |
| [`03_dwa_warianty_50_procent.html`](gtm/03_dwa_warianty_50_procent.html) | `ab3` | 50% ruchu w teście (`v0`/`v1` po 25%), reszta `out` — poza analizą | Tag → Custom HTML |
| [`04_rozszerzenie_do_100_procent.html`](gtm/04_rozszerzenie_do_100_procent.html) | `ab3` | podmiana kodu tagu z `03`: przydziały zostają, `out` i nowi dostają wariant | ten sam tag co `03` |
| [`zmienna_ab_variant.js`](gtm/zmienna_ab_variant.js) | jedna kopia na klucz | wariant z ciasteczka albo `undefined` (dla `out` i śmieci) | Zmienna → Custom JavaScript |

Konfiguracja:

1. Tag Custom HTML z jednym ze skryptów; wyzwalacz: strona testowa (np. karta produktu). Ustawienia zgody tagu: wymagaj zgody — ciasteczko testu nie jest niezbędne, więc losujesz dopiero po zgodzie.
2. Tag GA4 Event `ab_assign` na zdarzeniu niestandardowym `ab_assign`, parametry `ab_test` i `ab_variant` z warstwy danych.
3. Zmienna Custom JavaScript z `zmienna_ab_variant.js`; w tagach GA4 `view_item` i `purchase` dodaj parametry `ab_test` (stała: klucz testu, np. `ab1`) i `ab_variant` (ta zmienna).
4. Tag `view_item`: Sekwencjonowanie tagów → najpierw tag z kroku 1. Bez tego pierwszy `view_item` może pójść, zanim ciasteczko powstanie — `02` złapie usera dopiero na `ab_assign`.
5. Klucz testu i wariant kontrolny w skrypcie = `test_name` i `control_variant` w `02`. Konwencja: klucz ciasteczka to kolejny numer testu małymi literami (`ab1` w `01`, `ab2` w `02`, `ab3` w `03` i `04` — jeden test, więc ten sam klucz), wartości `v0` — zawsze wersja dotychczasowa (kontrola) — oraz `v1`, `v2` — warianty testowe.

Rozszerzenie `03` → `04` zmienia skalę testu, nie jego przebieg: kto miał wariant, zostaje w nim. Dawni `out` wchodzą do analizy od dnia rozszerzenia, ale wcześniej widzieli obecną wersję strony — gdy to przeszkadza, `INCLUDE_OUT = false` wpuszcza tylko nowych. Plan z kalkulatora Przed testem liczyłeś dla 50% ruchu — po rozszerzeniu użytkownicy zbierają się 2× szybciej, więc kończysz po pierwszym pełnym tygodniu, w którym każdy wariant ma liczbę użytkowników z planu.

## Kalkulator Przed testem

[pmdata.pl/kalkulatory/wielkosc-proby-test-ab](https://pmdata.pl/kalkulatory/wielkosc-proby-test-ab/) — ilu użytkowników potrzebuje test i ile tygodni potrwa przy Twoim ruchu.

![Kalkulator Przed testem wypełniony przykładowymi danymi, z przychodem](docs/img/przed-testem.png)

- **MDE (najmniejszy wzrost do wykrycia)** — próg biznesowy, nie prognoza: najmniejszy wzrost wart czasu testu, a nie ten, którego się spodziewasz. Względny: +15% przy CR 2% to +0,30 pp (2% → 2,3%). Optymizm skraca test, a potem test nie wykrywa realnego, mniejszego wzrostu.
- **MDE rządzi długością testu** — liczba użytkowników rośnie z 1 / MDE²: przy CR 2% +15% → 36 693 na wariant, +10% → 80 682, +5% → 315 206. Słupki i tabela pokazują, jakie MDE wykryjesz po każdym tygodniu. Gdy w limicie wykryjesz najwyżej +25%, a zmiana realnie da +5%, test niczego nie rozstrzygnie.
- **Poziom ufności i moc** — ufność chroni przed fałszywym alarmem (α = 1 − ufność: przy 95% co 20. test bez efektu pokaże różnicę), moc przed przeoczeniem (przy 80% realny wzrost równy MDE wykryjesz w 4 testach na 5). Wyższe wartości = dłuższy test.
- **Liczba wariantów razem z kontrolą** — każde porównanie z kontrolą to kolejna szansa na fałszywy alarm, więc przy 3+ próg p-value to α / (k − 1) (korekta Bonferroniego): 3 warianty przy 95% → 0,025 i więcej użytkowników.
- **Rodzaj testu** — jednostronny wymaga ~21% mniej użytkowników, ale nie wykaże, że wariant szkodzi. Wybierasz przed testem: zmiana po wyniku robi z p = 0,09 wynik 0,045.
- **Limit tygodni i stan planu** — pełne tygodnie, najwyżej 8: dłużej kasowanie cookies miesza warianty, a sezonowość zmienia to, co mierzysz. Ponad 6 tygodni = „Plan ryzykowny”, ponad limit = „Plan niewykonalny” z MDE, które wykryjesz w limicie. „poza zasięgiem” w tabeli = przy tej liczbie użytkowników nie wykryjesz realistycznego wzrostu.
- **Przekazanie do „Po teście”** — „Użytkownicy na wariant” wpisujesz w „Wymagani użytkownicy na wariant”. Plan zapisuje się w karcie przeglądarki, więc „Po teście” otwarty w tej samej karcie wstawi go przyciskiem „Wstaw z planu”.

## Kalkulator Po teście

[pmdata.pl/kalkulatory/istotnosc-testu-ab](https://pmdata.pl/kalkulatory/istotnosc-testu-ab/) — co zrobić z wariantem B. Na górze decyzja i jej skutek w złotówkach, pod „Szczegóły obliczeń” liczby, z których wynika.

![Kalkulator Po teście wypełniony przykładowymi danymi, z danymi z planu i przychodem](docs/img/po-tescie.png)

- **Dane z planu (opcjonalne)** — „Wymagani użytkownicy na wariant” (na jeden wariant, nie tygodniowy ruch ani suma) i MDE z „Przed testem”. Bez nich werdykt zależy tylko od p-value, które najłatwiej oszukać zaglądaniem do wyniku w trakcie. Z nimi kalkulator wstrzymuje decyzję, gdy test zatrzymano przed 95% planu albo przedłużano ponad 125%.
- **p-value** — prawdopodobieństwo wyniku co najmniej tak skrajnego, gdyby wzrostu nie było; nie prawdopodobieństwo, że B jest lepsze. Kalkulator pokazuje dwu- i jednostronne, werdykt bierze rodzaj testu z planu.
- **Zakres możliwego wzrostu** — 95% przedział ufności. Obejmuje zero = realnie może być wzrost, brak zmiany albo spadek. Przy teście jednostronnym to przedział 1 − 2α (przy 95% ufności: 90%), zgodny z progiem testu.
- **Wpływ na przychód** — przychód tygodniowy × zakres wzrostu; do budżetu bierz dolną granicę. Zakłada niezmienioną wartość zamówienia, bo test mierzył CR, nie przychód.
- **Winner's curse (klątwa zwycięzcy)** — istotny wzrost mniejszy niż MDE z planu znaczy, że test miał słabą moc, a istotne wyniki takich testów zawyżają wzrost. Stąd stan „Wdrażaj B, ale licz na mniej, niż zmierzono”.
- **SRM (sample ratio mismatch)** — sprawdza, czy A i B dostały po równo (50/50). Alarm przy p < 0,001 = błąd w losowaniu albo w danych, np. B ładuje się wolniej i gubi użytkowników; wtedy wyniku nie interpretujesz.
- **Mniej niż 10 konwersji** (albo osób bez konwersji) w którymś wariancie — test z to przybliżenie, przy tak małych liczbach p-value i zakres są niewiarygodne.
- **Stany wyniku** — sprawdzane po kolei, pierwszy pasujący wygrywa: ✕ Test zepsuty (SRM) → ✕ Nie wdrażaj B (istotny spadek) → ! Wstrzymaj decyzję (< 10 konwersji, poza 95–125% planu albo test jednostronny i B gorsze) → ✓ Wdrażaj B, ale licz na mniej (wzrost < MDE albo dolna granica zakresu < 1%) → ✓ Wdrażaj B → – Nie wdrażaj B jako zwycięzcy (wynik nieistotny).

## Definicje metryk

- **Użytkownicy** — unikalni `user_pseudo_id` od pierwszego `view_item` w oknie (przed testem; na tydzień = okno / liczba tygodni) albo od pierwszej ekspozycji (`exposure_events` z parametrem `ab_variant`) w okresie testu (po teście). Nie sesje: sesje jednej osoby nie są niezależne. Kolumna: `users_per_week`, `users`.
- **Konwertujący** — użytkownicy z `purchase` po pierwszym wejściu; osoby, nie zamówienia. Kolumna: `converters_per_week`, `converters`.
- **CR** — konwertujący / użytkownicy; liczy kalkulator, nie zapytanie.
- **Przychód tygodniowy** — przychód z `purchase` po pierwszym `view_item` w `window_weeks` pełnych tygodniach przed testem, podzielony przez liczbę tygodni; zdublowane `purchase` z tym samym `transaction_id` liczą się raz (bez ID każdy event to osobne zamówienie); w przykładzie `purchase_revenue_in_usd`, na własnym eksporcie `purchase_revenue`. Kolumna: `weekly_revenue`.
- **Wielokrotnie przypisani** — użytkownicy z 2+ wartościami `ab_variant` na dowolnym evencie testu, np. Safari skasowało ciasteczko testu, a `_ga` przetrwało, więc ten sam użytkownik został wylosowany ponownie. Wykluczeni z `users` i `converters`; ich liczba stoi w kolumnie `excluded_mixed`, w wierszu wariantu pierwszej ekspozycji. To ok. połowa ponownie wylosowanych — reszta trafiła przypadkiem w ten sam wariant. Przy podobnych `users` różnica `excluded_mixed` między wariantem a kontrolą większa niż 2 × √(suma obu) jest podejrzana (410 vs 398: różnica 12, próg ≈ 57 — w normie). Przyczyną może być błąd w tagu albo efekt wariantu, który zmienia, jak często ludzie wracają; w obu przypadkach wynik jest obciążony, dopóki różnicy nie wyjaśnisz.

## Ograniczenia

- `user_pseudo_id` to przeglądarka, nie osoba: ten sam człowiek na telefonie i laptopie to dwóch użytkowników.
- SRM zakłada podział 50/50; przy 3+ wariantach kalkulator ocenia jedną parę z kontrolą.
- Ocena to test z (przybliżenie normalne): przy kilku konwersjach w wariancie wynik jest przybliżony, a granice zakresu są ucinane tak, żeby CR B mieścił się między 0 a 100% (spadek najwyżej −100%).
- Wariant w `02` pochodzi z parametrów `ab_test` i `ab_variant`, które tag GTM czyta z first-party cookie i dokleja do eventów ([artykuł](https://pmdata.pl/artykuly/wlasne-testy-ab-gtm-firebase/)). Konwersja liczy się z każdego `purchase` po ekspozycji, także bez parametru — wariant bierze się z przypisania użytkownika, nie z eventu zakupu.
- Jeden parametr `ab_test` = jeden test na event. Przy dwóch testach naraz na tej samej stronie para `ab_test`/`ab_variant` nie pomieści obu — potrzebny osobny parametr na test.
- Safari (ITP) skraca ciasteczka ustawione z JavaScriptu do 7 dni, także `_ga`. Gdy po tygodniu wygaśnie tylko ciasteczko testu, `excluded_mixed` to wyłapie. Gdy wygaśnie też `_ga`, ten sam człowiek wraca z nowym `user_pseudo_id` i nowym losowaniem, a zapytanie widzi dwóch użytkowników. Ciasteczka ustawiane z serwera (server-side GTM) usuwają ten problem.

## Rozbudowa: najpierw testy sekwencyjne, CUPED dopiero po pomiarze korelacji

Na anonimowym ruchu e-commerce testy sekwencyjne dają korzyść niezależnie od danych, a CUPED tylko wtedy, gdy zachowanie sprzed testu przewiduje wynik testu (korelacja ρ). Większość osób na karcie produktu nie ma historii pod tym samym `user_pseudo_id` — nowi, skasowane ciasteczka, inne urządzenie. Kolejność: zmierz ρ jednym zapytaniem → testy sekwencyjne → CUPED, jeśli ρ ≥ 0,3.

| | Testy sekwencyjne (podgląd co tydzień) | CUPED |
|---|---|---|
| Co daje | Wcześniejszy koniec, gdy efekt jest duży albo wariant szkodzi; podglądanie bez zawyżania fałszywych alarmów | Ta sama moc przy próbie mniejszej o ρ² (ρ = 0,3 → −9%, ρ = 0,5 → −25%) |
| Czy zysk jest pewny | Ochrona przed podglądaniem — zawsze; krótszy test — tylko przy dużym efekcie | Zależy od ρ; na ruchu anonimowym zwykle niskie |
| Dane | Te same co `02`, narastająco tydzień po tygodniu | Historia każdego użytkownika z 2–4 tygodni przed testem |
| Złożoność / praca | Statystyka 4/5, wdrożenie 3/5, ok. 4–6 dni | Statystyka 3/5, wdrożenie 3/5, ok. 3–4 dni |
