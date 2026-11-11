# ga4-ab-testing

Testy A/B na eksporcie GA4 w BigQuery: SQL i dbt liczą liczby do dwóch kalkulatorów na pmdata.pl, skrypty GTM losują wariant. Opis dla ludzi: `README.md` (kroki testu, mapa folderów), `sql/README.md` (zapytania, kalkulatory, zrzuty), `gtm/README.md` (tagi) i `dbt/README.md` (dbt, CI/CD, dane syntetyczne) — przeczytaj je przed zmianą.

## Mapa

| Ścieżka | Co to |
|---|---|
| `sql/01_przed_testem.sql` | ruch, konwertujący, przychód na użytkownika w oknach 1–8 tyg. → kalkulator „Przed testem” |
| `sql/02_przychod_tygodniowy.sql` | przychód tygodniowy (średnia i mediana) → pole przychodu w obu kalkulatorach |
| `sql/03_po_tescie_warianty.sql` | wynik jednego testu na wariant + kontrola jakości → kalkulator „Po teście” |
| `dbt/` | to samo co `sql/03` dla wszystkich testów z seeda `seeds/rejestr_testow.csv`; staging → intermediate → `fct_wyniki_testow_ab` |
| `dane_syntetyczne/generuj_eksport_ga4.sql` | skrypt BigQuery: syntetyczny eksport GA4 ze znanym efektem wariantów (prawda w `dbt/README.md`) |
| `gtm/` | tagi Custom HTML losujące wariant w slotach `ab1`–`ab10` |
| `.github/workflows/dbt-ci-cd.yml` | parse → unit testy → deploy zmienionych modeli (push na `main`) |
| `.github/workflows/dbt-schedule.yml` | codzienny `dbt build` na prod z ostatniego zielonego commita CI |
| `docs/img/` | zrzuty BigQuery i kalkulatorów do `sql/README.md` |

Nie ma dbt dla `sql/01` i `02`: plan testu to zapytanie jednorazowe z innymi parametrami za każdym razem, a staging trzyma tylko eventy z wariantem testu.

## Uruchomienie

```bash
cd dbt && uv sync && cp profiles.yml.example profiles.yml && uv run dbt deps
uv run dbt parse --profiles-dir .                        # bez połączenia z BigQuery
uv run dbt build --target sandbox --profiles-dir .        # vars w dbt_project.yml = ab-test-sandbox.ga4_syntetyczny
uvx sqlfluff parse --dialect bigquery sql/               # składnia zwykłego SQL (z katalogu głównego)
```

Projekt działa w darmowym BigQuery sandboxie (bez karty) w projekcie GCP `ab-test-sandbox`: zawsze `--target sandbox` (oauth przez `gcloud auth application-default login`, projekt wpisany w profilu). Sandbox nie ma DML (`MERGE`), usuwa tabele i partycje po 60 dniach, ma 10 GiB zapisu na całe konto. Lokalizacja danych: EU. Zmiana logiki `stg_ga4__zdarzenia` wymaga `--full-refresh`.

## Konwencje

- **Komentarze w SQL i dbt:** tylko nagłówek pliku (cel, kluczowe reguły) i przykładowa tabela wyniku na końcu. Zero komentarzy wewnątrz kodu. Wyjątek: w `sql/` blok `DECLARE` do uzupełnienia ma baner „DO UZUPEŁNIENIA” i jednozdaniowy komentarz przy każdej zmiennej; parametry nie powtarzają się w nagłówku. W dbt nagłówek i przykład w `{# #}`, pierwsza linia testu to `-- GENERIC` / `-- SINGULAR`.
- **Nazwy:** `sql/` po angielsku (`user_pseudo_id`, `revenue_per_user`), dbt po polsku (`id_uzytkownika`, `przychod_na_uzytkownika`). Komentarze i dokumentacja po polsku.
- **Ta sama logika w trzech miejscach:** `sql/03`, model dbt i kalkulator muszą liczyć tak samo (pierwsza ekspozycja, konwersja po niej, zamówienie raz na `transaction_id`, przychód osoby przycięty do 99,9 percentyla, `(not set)`/'' jako NULL). Zmiana w jednym = sprawdź pozostałe.
- **Poprawka = grep całego repo:** wartość, nazwa pliku albo parametr zwykle siedzi też w README, przykładach wyników, workflow i GTM. Każde trafienie popraw albo uzasadnij, czemu zostaje.
- **Symetria:** powiązane tabele i listy w dokumentach trzymają tę samą kolejność kategorii.
- **Prostota:** najprostsze działające rozwiązanie, bez opcji i abstrakcji „na później”. Nowa logika z rozgałęzieniem → test dbt.
- **Kalkulatory** leżą w innym repo: `~/Documents/dev/personal-page` (`src/pages/kalkulatory/`, `src/utils/ab-stats.ts`). Opis kalkulatora sprawdzaj w tym kodzie, nie z pamięci. Zmiany tam robi agent personal-page, a nie ta sesja.
- **GTM:** kroki konfiguracji opisują notatki elementów w kontenerze GTM, nie README. Model: tag Custom HTML per slot + zmienne „Własny plik cookie” `abN` + event `ab_assign`; bez sekwencji i Custom JS.
- **Zrzuty `docs/img/`:** z lokalnego dev servera personal-page (`localhost:4321/kalkulatory/`), Playwright, viewport 1280, `device_scale_factor=2`, wycinek `.abc__panel` ±20 px, dane w hashu URL; ukryte elementy fixed/sticky i pasek Astro.

## Git

- Zmiany zostawiaj niezacommitowane, żeby Piotr przejrzał je w Cursorze; commit i push na `main` (bez PR) dopiero na jego prośbę.
- Tytuł po polsku z prefiksem: `feat:`, `fix:`, `docs:`, `ci:`. Tylko zmiana techniczna, bez motywacji.
- Autor `pmackowka@gmail.com`. Bez stopek `Co-Authored-By` / `Claude-Session`.
- Przed commitem: `git diff --cached | grep -i -E -f ~/.config/git/forbidden-patterns.txt` musi być pusty. Repo jest prywatne: prawdziwe ID własnego projektu `ab-test-sandbox` i komentarze z przebiegu wolno wpisywać; publiczny jest tylko oczyszczony szablon. ID klientów nigdy.
- Bez przepisywania historii i force pusha bez zgody.

## Stan

- Generator, `sql/01`–`03` i `dbt build` biegły w sandboxie; lista rzeczy do potwierdzenia: `dbt/README.md`, sekcja „Niesprawdzone”.
- GitHub Actions działa w `ab-test-sandbox` przez Workload Identity Federation (konto `dbt-prod`, bez kluczy): CI/CD buduje `dbt_ci_testy_ab` i `dbt_prod_testy_ab`, harmonogram (3:17 Europe/Warsaw) najpierw generuje wczorajszy dzień. Staging w sandboxie: `vars.sandbox: true`.
- Raport Data Studio (do kwietnia 2026 Looker Studio) `https://datastudio.google.com/reporting/c45c9272-2566-4ebf-a257-d2ed7ba516c0`, link w README: rejestr testów i `fct_wyniki_testow_ab` ze źródeł w Arkuszach Google (zrzut z 2026-11-09, nie odświeża się sam), teksty opisujące tabele i kolumny kontroli jakości, linki do kalkulatorów z UTM. Zmiana logiki albo nazw kolumn w dbt = sprawdź teksty w raporcie.
- Publiczna kopia: `pmackowka/ga4-ab-testing-template` (szablon GitHub, MIT, portfolio) — bez komentarzy, bez danych syntetycznych i sandboxa, z opisami kolumn i dbt docs na GitHub Pages (`dbt docs generate --static --empty-catalog --no-compile`, bez poświadczeń GCP). Pracujesz tutaj; szablon nie synchronizuje się sam, zmiany przenosi się ręcznie na prośbę Piotra. `dbt schedule` i `dbt CI/CD` są tam wyłączone (brak sekretów).
- Opisy z `.yml` trafiają do BigQuery przez `persist_docs`; strona startowa dbt docs to `dbt/models/overview.md` (jak czytać dane, bez kroków wdrożenia — te są w README). Zmiana kolumn = popraw opis w `.yml` i tabelę w overview.
- Otwarte sprawy i pułapki z uruchomienia: lokalny `NOTATKI_AGENTA.md` (poza gitem).
- Domyślne okna w `sql/01` i `02` (`window_start = '2026-08-24'`, 2 tygodnie) i tabela `ab-test-sandbox.ga4_syntetyczny.events_*` pasują do danych syntetycznych; przy prawdziwym eksporcie ustaw własne.
