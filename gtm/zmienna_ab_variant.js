/*
 Zmienna GTM → Custom JavaScript, nazwa np. „CJS - ab1” — jedna kopia na slot
 (ab1–ab10). W zmiennej „Ustawienia zdarzeń Google tag” dodaj wiersz:
 parametr ab1 = {{CJS - ab1}} (i tak dla każdego slotu) — wtedy każdy event GA4
 niesie wariant każdego testu, w którym jest użytkownik, pod nazwą slotu.
 Zwraca wariant z ciasteczka albo undefined — wtedy GA4 nie wysyła parametru,
 więc 'out', brak ciasteczka i śmieciowe wartości nie trafią do analizy.
 Konfigurujesz raz: kopie różnią się tylko TEST. VALID obejmuje wszystkie warianty,
 jakich używają tagi, więc nowy test w slocie nie wymaga zmiany zmiennej.
*/
function () {
  var TEST = 'ab1';                 // slot = nazwa ciasteczka i parametru GA4
  var VALID = ['v0', 'v1', 'v2'];   // wszystkie warianty z tagów gtm/; wariant spoza seeda łapie dbt
  var m = document.cookie.match(new RegExp('(?:^|; )' + TEST + '=([^;]*)'));
  var v = m ? decodeURIComponent(m[1]) : undefined;
  return VALID.indexOf(v) > -1 ? v : undefined;
}
