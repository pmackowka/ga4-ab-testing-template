# Demo wideo

Materiały do filmu z README (2:33, test `ab2` na danych syntetycznych). Wideo nie leży w repo: wersja 720p jest załącznikiem GitHuba podlinkowanym w README.

| Plik | Co to |
|---|---|
| [`scenariusz.md`](scenariusz.md) | tabela ujęć (obraz, napis na ekranie, źródło nagrania) i tekst lektora AI |
| [`demo.tape`](demo.tape) | nagranie terminala w [VHS](https://github.com/charmbracelet/vhs): rejestr testów i `dbt build` (ujęcie 4) |
| [`napisy.srt`](napisy.srt) | napisy z czasami lektora gotowego filmu |

## Ponowne nagranie terminala

Z katalogu głównego repo, z działającym `dbt build --target sandbox`:

```bash
vhs docs/demo/demo.tape -o ujecie4.mp4
```

`demo.tape` czeka stałe 90 s na koniec `dbt build`: `Wait` w VHS 0.12 nie widzi całego ekranu. Przy dłuższym buildzie zwiększ `Sleep`. Gdy `dbt` pisze ostrzeżenie o projekcie Google Cloud, ustaw przed komendą `GOOGLE_CLOUD_PROJECT=<projekt>`.

## Liczby w filmie

Pochodzą z `fct_wyniki_testow_ab` dla `ab2_20260907` i z kalkulatora „Po teście” z jego danymi przykładowymi: konwersja 3,17% → 3,61% (+13,8%), 95% przedział ufności +7,6% do +20,1%, „Wdrażaj B”, przy 572 968 zł tygodniowo od +43 522 zł do +115 084 zł. Zmiana generatora, seeda albo SQL rozjedzie je z filmem.
