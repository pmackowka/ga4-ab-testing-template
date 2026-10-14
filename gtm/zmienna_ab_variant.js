/*
 Zmienna GTM → Custom JavaScript, nazwa np. „CJS - ab1” — jedna kopia na test.
 Wstaw ją jako parametr ab_variant w tagach GA4 (view_item, purchase…),
 a obok parametr ab_test = stała z kluczem testu (ab1). Zwraca wariant z ciasteczka
 albo undefined — wtedy GA4 nie wysyła parametru, więc 'out', brak ciasteczka
 i śmieciowe wartości nie trafią do analizy w sql/02.
 Przy teście 3-wariantowym (ab2) ustaw TEST = 'ab2' i dopisz 'v2' do VALID.
*/
function () {
  var TEST = 'ab1';             // klucz ciasteczka: ab1, ab2, ab3… — jedna zmienna na test
  var VALID = ['v0', 'v1'];
  var m = document.cookie.match(new RegExp('(?:^|; )' + TEST + '=([^;]*)'));
  var value = m ? decodeURIComponent(m[1]) : undefined;
  return VALID.indexOf(value) > -1 ? value : undefined;
}
