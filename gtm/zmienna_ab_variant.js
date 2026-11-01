/*
 Zmienna GTM → Custom JavaScript, nazwa np. „CJS - ab1” — jedna kopia na slot
 (ab1–ab10). W zmiennej „Ustawienia zdarzeń Google tag” dodaj wiersz:
 parametr ab1 = {{CJS - ab1}} (i tak dla każdego slotu) — wtedy każdy event GA4
 niesie wariant każdego testu, w którym jest użytkownik, pod nazwą slotu.
 Zwraca wariant z ciasteczka albo undefined — wtedy GA4 nie wysyła parametru,
 więc 'out', ciasteczko poprzedniego testu w slocie (inny RUN), brak ciasteczka
 i śmieciowe wartości nie trafią do analizy.
 Nowy test w slocie: zmień RUN i VALID tu i w tagu losującym.
*/
function () {
  var TEST = 'ab1';             // slot = nazwa ciasteczka i parametru GA4
  var RUN = '20260907';         // = RUN w tagu losującym tego slotu
  var VALID = ['v0', 'v1'];     // = VARIANTS w tagu
  var m = document.cookie.match(new RegExp('(?:^|; )' + TEST + '=([^;]*)'));
  var parts = m ? decodeURIComponent(m[1]).split('.') : [];
  return parts[1] === RUN && VALID.indexOf(parts[0]) > -1 ? parts[0] : undefined;
}
