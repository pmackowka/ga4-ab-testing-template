# ab-test-bigquery

Testy A/B na eksporcie GA4 w BigQuery: SQL i dbt liczą liczby do dwóch kalkulatorów na pmdata.pl, skrypty GTM losują wariant. Opis dla ludzi: `README.md` (SQL, kalkulatory, GTM) i `dbt/README.md` (dbt, CI/CD, dane syntetyczne) — przeczytaj je przed zmianą.

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
| `docs/img/` | zrzuty kalkulatorów do README |

Nie ma dbt dla `sql/01` i `02`: plan testu to zapytanie jednorazowe z innymi parametrami za każdym razem, a staging trzyma tylko eventy z wariantem testu.

## Uruchomienie

```bash
cd dbt && uv sync && cp profiles.yml.example profiles.yml && uv run dbt deps
uv run dbt parse --profiles-dir .                        # bez BigQuery; target dev wymaga BIGQUERY_KEYFILE
uv run dbt build --target sandbox --profiles-dir . --vars '{ga4_projekt: <projekt>, ga4_zbior_danych: ga4_syntetyczny}'
uvx sqlfluff parse --dialect bigquery sql/*.sql          # składnia zwykłego SQL (z katalogu głównego)
```

Projekt działa w darmowym BigQuery sandboxie (bez karty): zawsze `--target sandbox` (oauth przez `gcloud auth application-default login`). Sandbox nie ma DML (`MERGE`), usuwa tabele i partycje po 60 dniach, ma 10 GiB zapisu na całe konto. Lokalizacja danych: EU. Zmiana logiki `stg_ga4__zdarzenia` wymaga `--full-refresh`.

## Konwencje

- **Komentarze w SQL i dbt:** tylko nagłówek pliku (cel, parametry, kluczowe reguły) i przykładowa tabela wyniku na końcu. Zero komentarzy wewnątrz kodu. W dbt nagłówek i przykład w `{# #}`, pierwsza linia testu to `-- GENERIC` / `-- SINGULAR`.
- **Nazwy:** `sql/` po angielsku (`user_pseudo_id`, `revenue_per_user`), dbt po polsku (`id_uzytkownika`, `przychod_na_uzytkownika`). Komentarze i dokumentacja po polsku.
- **Ta sama logika w trzech miejscach:** `sql/03`, model dbt i kalkulator muszą liczyć tak samo (pierwsza ekspozycja, konwersja po niej, zamówienie raz na `transaction_id`, przychód osoby przycięty do 99,9 percentyla, `(not set)`/'' jako NULL). Zmiana w jednym = sprawdź pozostałe.
- **Poprawka = grep całego repo:** wartość, nazwa pliku albo parametr zwykle siedzi też w README, przykładach wyników, workflow i GTM. Każde trafienie popraw albo uzasadnij, czemu zostaje.
- **Symetria:** powiązane tabele i listy w dokumentach trzymają tę samą kolejność kategorii.
- **Prostota:** najprostsze działające rozwiązanie, bez opcji i abstrakcji „na później”. Nowa logika z rozgałęzieniem → test dbt.
- **Kalkulatory** leżą w innym repo: `~/Documents/dev/personal-page` (`src/pages/kalkulatory/`, `src/utils/ab-stats.ts`). Opis kalkulatora sprawdzaj w tym kodzie, nie z pamięci. Zmiany tam robi agent personal-page, a nie ta sesja.
- **GTM:** kroki konfiguracji opisują notatki elementów w kontenerze GTM, nie README. Model: tag Custom HTML per slot + zmienne „Własny plik cookie” `abN` + event `ab_assign`; bez sekwencji i Custom JS.
- **Zrzuty `docs/img/`:** z lokalnego dev servera personal-page (`localhost:4321/kalkulatory/`), Playwright, viewport 1280, `device_scale_factor=2`, wycinek `.abc__panel` ±20 px, dane w hashu URL; ukryte elementy fixed/sticky i pasek Astro.

## Git

- Zmiany zrobione na prośbę Piotra: commit i push na `main` od razu, bez PR.
- Tytuł po polsku z prefiksem: `feat:`, `fix:`, `docs:`, `ci:`. Tylko zmiana techniczna, bez motywacji.
- Autor `pmackowka@gmail.com`. Bez stopek `Co-Authored-By` / `Claude-Session`.
- Przed commitem: `git diff --cached | grep -i -E -f ~/.config/git/forbidden-patterns.txt` musi być pusty. W przykładach placeholdery (`twoj-projekt`, `analytics_123456789`), nigdy prawdziwe ID projektów i klientów.
- Bez przepisywania historii i force pusha bez zgody.

## Stan

- Na BigQuery nic jeszcze nie biegło (tylko `dbt parse` i `sqlfluff`). Lista rzeczy do potwierdzenia: `dbt/README.md`, sekcja „Niesprawdzone”.
- CI `unit-tests` i deploy czekają na konfigurację Workload Identity Federation (sekrety w GitHub Actions).
- Domyślne okno w `sql/01` i `02` zaczyna się 2026-08-03, a dane syntetyczne od 2026-08-24: przy syntetycznych ustaw `window_start = '2026-08-24'`.
