/*
 Zmienna GTM → Custom JavaScript, nazwa np. „CJS - ab_variant”.
 Wstaw ją jako parametr ab_variant w tagach GA4 (view_item, purchase…),
 a obok parametr ab_test = stała z nazwą testu. Zwraca wariant z ciasteczka
 albo undefined — wtedy GA4 nie wysyła parametru, więc 'out', brak ciasteczka
 i śmieciowe wartości nie trafią do analizy w sql/02.
 Przy teście 3-wariantowym dopisz 'v2' do VALID i zmień TEST.
*/
function () {
  var TEST = 'ab_cta';
  var VALID = ['v0', 'v1'];
  var m = document.cookie.match(new RegExp('(?:^|; )' + TEST + '=([^;]*)'));
  var value = m ? decodeURIComponent(m[1]) : undefined;
  return VALID.indexOf(value) > -1 ? value : undefined;
}
