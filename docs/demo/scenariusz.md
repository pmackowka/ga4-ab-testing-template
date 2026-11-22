# Demo ga4-ab-testing-template — scenariusz (wersja 3)

Maks. 3:00, lektor AI w Google Vids, obraz bez dźwięku. Dane syntetyczne, projekt `ab-test-sandbox`, test `ab2` (2026-09-07 – 2026-09-20), prawdziwy efekt B: +10% konwersji.

| # | Czas | Obraz | Napis na ekranie | Źródło nagrania |
|---|---|---|---|---|
| 1 | 0:00–0:25 | README szablonu na GitHubie, góra strony | — | QuickTime |
| 2 | 0:25–0:50 | `gtm/01_dwa_warianty.html` na GitHubie, przewinięcie do `ab_assign` | — | QuickTime |
| 3 | 0:50–1:10 | konsola BigQuery: tabela `events_*`, wynik zapytania z parametrem `ab2` | „Dane przykładowe (syntetyczne), efekt B: +10%” | QuickTime |
| 4 | 1:10–1:35 | terminal: `rejestr_testow.csv`, `dbt build`, „Completed successfully” | — | VHS |
| 5a | 1:35–2:00 | raport Data Studio, wiersze ab2 | „Przychód osoby przycięty do 99,9 percentyla” | QuickTime |
| 5b | 2:00–2:40 | kalkulator „Po teście”: werdykt „Wdrażaj B”, przedział, blok „Wpływ na przychód tygodniowo” | — | QuickTime |
| 6 | 2:40–2:55 | README szablonu, sekcja z linkami | — | QuickTime |

Liczby kalkulatora (przykład ab2, policzone z `ab-stats.ts`): +13,84%, 95% CI +7,60% do +20,09%, „Wdrażaj B”, przy 572 968 zł/tydz.: od +43 522 zł do +115 084 zł, najbardziej prawdopodobnie +79 303 zł.

## Lektor

**1. Problem**
Test A/B trwał dwa tygodnie i wariant B wygląda lepiej. Biznes pyta o dwie rzeczy: ile zarobimy po wdrożeniu i czy ten wynik to nie przypadek. Standardowe raporty GA4 nie odpowiedzą na żadną. To repo odpowiada na obie, na danych, które już masz: na eksporcie GA4 w BigQuery. Pokażę cały przepływ, od losowania wariantu po kwotę w złotówkach.

**2. Losowanie wariantu**
Zaczyna się w Google Tag Manager. Tag losuje wariant raz na użytkownika, zapisuje go w ciasteczku na sześćdziesiąt dni i wysyła do GA4 zdarzenie przydziału. Od tej chwili każde zdarzenie w lejku, od karty produktu po zakup, niesie numer wariantu. Tag odpala się dopiero po zgodzie na analitykę.

**3. Dane w BigQuery**
GA4 co dzień eksportuje surowe zdarzenia do BigQuery. Tu widzisz dane syntetyczne: wariant B dostał w nich konwersję wyższą o dziesięć procent. Jeśli liczenie jest poprawne, wynik musi wyjść w pobliżu tej liczby. Dla jednego testu wystarczy gotowe zapytanie SQL w konsoli.

**4. dbt**
Gdy testów jest więcej, wchodzi dbt. Testy wpisujesz w jeden plik CSV: slot, daty, warianty i zdarzenie konwersji. Jedna komenda buduje modele i odpala testy danych. Sprawdzają, czy warianty dostały podobny ruch i czy w eksporcie nie brakuje dnia. Unit testy pilnują logiki liczenia. Po konfiguracji GitHub Actions robi to codziennie, bez kluczy do Google Cloud.

**5a. Raport**
Model końcowy daje jeden wiersz na wariant. Konwersja liczy się dopiero po pierwszej ekspozycji, a przychód osoby jest przycięty do dziewięćdziesięciu dziewięciu i dziewięciu dziesiątych percentyla, żeby jeden duży koszyk nie rozstrzygnął testu. Raport w Data Studio mówi, które liczby wpisać do kalkulatora.

**5b. Kalkulator**
B konwertuje na poziomie trzech i sześciu dziesiątych procenta, kontrola trzech i dwóch dziesiątych. To prawie czternaście procent więcej. Przedział ufności sięga od siedmiu i pół do dwudziestu procent i obejmuje prawdziwe dziesięć, więc liczenie działa. Kalkulator mówi: wdrażaj B. W złotówkach to od czterdziestu trzech do stu piętnastu tysięcy więcej tygodniowo, najpewniej około osiemdziesięciu.

**6. CTA**
Szablon jest otwarty, na licencji MIT. README prowadzi krok po kroku: od połączenia GA4 z BigQuery, przez tag w GTM, po codzienny harmonogram. Link w opisie filmu.
