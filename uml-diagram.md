# Diagram sekwencji UML: test A/B od planu do decyzji

Kto co robi przed testem, w trakcie i po nim. W tym repo kroki 5–9 zastępuje `dane_syntetyczne/generuj_eksport_ga4.sql`: syntetyczny eksport GA4 ze znanym efektem wariantów, więc wynik modelu da się porównać z prawdą (`dbt/README.md`). Kroki testu: [README](README.md).

```mermaid
sequenceDiagram
    autonumber
    actor AN as Analityk
    participant KAL as Kalkulatory pmdata.pl
    participant GH as GitHub Actions
    participant DBT as dbt
    actor U as Użytkownik
    participant GTM as GTM: tag abN
    participant CK as Cookie abN
    participant GA as GA4
    participant BQ as BigQuery

    AN->>BQ: sql/01 i 02: ruch, konwersje, przychód tygodniowy
    AN->>KAL: „Przed testem”: ilu użytkowników i ile tygodni
    AN->>GH: wiersz w seeds/rejestr_testow.csv (push na main)
    GH->>DBT: CI/CD: parse → unit testy → deploy zmienionych modeli i zależnych od nich
    U->>GTM: wejście na stronę testową
    Note over GTM,CK: tylko przy zgodzie analytics_storage
    GTM->>CK: losowanie wariantu raz, zapis na 60 dni
    GTM->>GA: ab_assign (ab_test, ab_variant)
    GTM->>GA: view_item, purchase z parametrem abN
    GA->>BQ: eksport dzienny events_YYYYMMDD
    GH->>DBT: harmonogram: codzienny dbt build na prod z ostatniego zielonego commita
    DBT->>BQ: staging → intermediate → fct_wyniki_testow_ab (+ testy danych)
    AN->>BQ: po teście: fct_wyniki_testow_ab albo sql/03
    AN->>KAL: „Po teście”: czy różnica jest istotna i czy wdrażać B
```

| Krok | Kto | Po co |
|---|---|---|
| 1–2 | analityk | długość testu znana przed startem — bez zaglądania do wyniku w trakcie |
| 3–4 | analytics engineer | test dopisany do rejestru trafia do modelu przez CI/CD, nie ręcznie |
| 5–8 | tag GTM | wariant raz na użytkownika, widoczny na każdym zdarzeniu lejka |
| 9–11 | GA4, GitHub Actions, dbt | wynik przeliczany codziennie dla wszystkich testów z rejestru |
| 12–13 | analityk | decyzja na liczbach liczonych tak samo jak w kalkulatorze |
