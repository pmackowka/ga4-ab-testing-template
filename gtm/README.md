# GTM — losowanie wariantu

Tagi Custom HTML do Google Tag Managera: losują wariant raz, zapisują go w ciasteczku `abN` (60 dni) i wysyłają do dataLayer event `ab_assign` z `ab_test` i `ab_variant`. Wariant trafia też na pozostałe eventy GA4 jako parametr `abN` ze zmiennej „Własny plik cookie”. Z obu liczą [`sql/03`](../sql/03_po_tescie_warianty.sql) i [dbt](../dbt/README.md). Kroki konfiguracji w kontenerze opisują notatki jego elementów.

Tag publikujesz w poniedziałek, bo `03` liczy pełne tygodnie. Kolejność kroków testu: [README główne](../README.md).

| Plik | Slot | Co robi |
|---|---|---|
| [`01_dwa_warianty`](01_dwa_warianty.html) | `ab1` (A/A), `ab2`, `ab5` | `v0`/`v1` po 50% |
| [`02_trzy_warianty`](02_trzy_warianty.html) | `ab3` | `v0`/`v1`/`v2` po 1/3 |
| [`03_dwa_warianty_50_procent`](03_dwa_warianty_50_procent.html) | `ab4` | 50% ruchu w teście, reszta `out` |
| [`04_rozszerzenie_do_100_procent`](04_rozszerzenie_do_100_procent.html) | `ab4` | zamiast `03`: przydziały zostają, `out` dostaje wariant |

## Zasady tagów

- Tag odpala się na stronie testowej dopiero po zgodzie na ciasteczka. Losuje raz i zapisuje sam wariant (albo `out`) w ciasteczku; wartość spoza listy (ręczna edycja) = brak przydziału i nowe losowanie.
- `TEST` to slot `ab1`–`ab10`: nazwa ciasteczka, nazwa parametru GA4, `test_name` w `sql/03` i `slot` w seedzie. Slot wraca do użycia dopiero po wygaśnięciu ciasteczek poprzedniego testu — pilnuje tego `sprawdz_konfiguracje_testow`.
- Jeden tag na slot. Kolejny test na tej samej stronie to kopia tagu z nowym `TEST`. Nie przełączaj `v1` w tagu A/A (`ab1`): ciasteczka `ab1` (60 dni) przeniosłyby podział z A/A, a nowy test nie dostałby ekspozycji.
- `DAYS = 60`: dłużej niż najdłuższy test (8 tygodni) i tyle, ile minimalna przerwa slotu w dbt.
- `03`: połowa ruchu w teście (v0/v1 po 25% całego ruchu), reszta dostaje `out`, widzi obecną stronę i nie wchodzi do analizy. Mniejsze ryzyko, gdy wariant może szkodzić, kosztem ok. 2× dłuższego testu.
- `04` podmienia kod tagu `03` (ten sam tag, ten sam wyzwalacz) i musi mieć ten sam `TEST`, inaczej przydziały się zgubią. Osoby z v0/v1 zostają w wariancie, nowi dostają wariant 50/50. `INCLUDE_OUT = true`: dawni `out` też dostają wariant i wchodzą do analizy od dnia rozszerzenia, choć wcześniej widzieli starą stronę; `false`: zostają poza testem. To nie jest wdrożenie zwycięzcy — test trwa dalej na całym ruchu.

## Ograniczenia

- Najwyżej 10 testów naraz (sloty `ab1`–`ab10`, limit 25 parametrów na event w GA4). Równoległe testy losują niezależnie; problem to tylko silna interakcja, np. dwa testy zmieniają ten sam element.
- Safari (ITP) skraca ciasteczka z JavaScriptu do 7 dni, także `_ga`. Skutki liczą `reassigned`, `excluded_mixed` i `no_assignment`; utraty obu ciasteczek naraz żadna kolumna nie pokaże. Pomaga przedłużanie ciasteczek z serwera (np. Cookie Extender od Stape), ale tylko przy server-side GTM pod adresem strony (same-origin albo subdomena na IP strony); serwer z innego IP Safari też ogranicza do 7 dni.
