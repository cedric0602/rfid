// Ajoute sous l'en-tete un bandeau LCARS :
//   date stellaire (style 24e siecle, purement decoratif)
//   + date UEE de Star Citizen (annee reelle + 930)
//   + code du vaisseau.
// Charge automatiquement par Homepage (/app/config/custom.js).
(function () {
  "use strict";

  // Annee reelle + 373 -> on se place fin 24e siecle (2399 en 2026)
  function stardate(d) {
    var start = new Date(d.getFullYear(), 0, 1);
    var end = new Date(d.getFullYear() + 1, 0, 1);
    var frac = (d - start) / (end - start);
    var year = d.getFullYear() + 373;
    return ((year - 2323) * 1000 + frac * 1000).toFixed(1);
  }

  function ueeDate(d) {
    var mois = ["JAN", "FEV", "MAR", "AVR", "MAI", "JUN",
                "JUL", "AOU", "SEP", "OCT", "NOV", "DEC"];
    return d.getDate() + " " + mois[d.getMonth()] + " " + (d.getFullYear() + 930);
  }

  function render(el) {
    var now = new Date();
    el.innerHTML =
      '<span class="lc-pill lc-code">NCC-1248</span>' +
      '<span class="lc-pill lc-sd">Date stellaire ' + stardate(now) + "</span>" +
      '<span class="lc-pill lc-uee">UEE ' + ueeDate(now) + "</span>";
  }

  function mount() {
    var header = document.getElementById("information-widgets");
    if (!header) return false;
    var el = document.getElementById("lcars-chrono");
    if (!el) {
      el = document.createElement("div");
      el.id = "lcars-chrono";
      header.insertAdjacentElement("afterend", el);
    }
    render(el);
    return true;
  }

  // Homepage est une appli React : on attend que l'en-tete existe,
  // et on remonte le bandeau s'il est supprime par un re-rendu.
  var tries = 0;
  var wait = setInterval(function () {
    if (mount() || ++tries > 50) clearInterval(wait);
  }, 200);
  setInterval(mount, 60000);
  new MutationObserver(function () {
    if (!document.getElementById("lcars-chrono")) mount();
  }).observe(document.body, { childList: true, subtree: true });
})();
