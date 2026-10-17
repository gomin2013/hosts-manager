// Hosts Manager site: language toggle, scroll reveal, latest release lookup. No dependencies.
(function () {
  "use strict";
  var root = document.documentElement;

  // ── Language (the <head> snippet already applied it before first paint) ──
  function setLang(lang) {
    root.classList.toggle("th", lang === "th");
    root.lang = lang;
    try { localStorage.setItem("hm.lang", lang); } catch (e) { /* private mode */ }
    document.querySelectorAll(".lang button").forEach(function (b) {
      b.setAttribute("aria-pressed", String(b.dataset.lang === lang));
    });
  }
  document.querySelectorAll(".lang button").forEach(function (b) {
    b.addEventListener("click", function () { setLang(b.dataset.lang); });
  });
  setLang(root.classList.contains("th") ? "th" : "en");

  // ── Reveal on scroll (IntersectionObserver, no scroll listeners) ──
  var items = document.querySelectorAll(".reveal");
  if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.12 });
    items.forEach(function (el) { io.observe(el); });
  } else {
    items.forEach(function (el) { el.classList.add("in"); });
  }

  // ── Latest release: version + direct DMG link. Links already point at /releases/latest if this fails. ──
  var dl = document.querySelectorAll("[data-dmg]");
  var info = document.querySelectorAll("[data-release]");
  if (!dl.length && !info.length) return;
  fetch("https://api.github.com/repos/gomin2013/hosts-manager/releases/latest", {
    headers: { Accept: "application/vnd.github+json" }
  })
    .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
    .then(function (rel) {
      var dmg = (rel.assets || []).filter(function (a) { return /\.dmg$/.test(a.name); })[0];
      var sums = (rel.assets || []).filter(function (a) { return a.name === "SHA256SUMS.txt"; })[0];
      var values = {
        version: rel.tag_name,
        date: (rel.published_at || "").slice(0, 10),
        size: dmg ? (dmg.size / 1048576).toFixed(1) + " MB" : "",
        file: dmg ? dmg.name : ""
      };
      if (dmg) dl.forEach(function (a) { a.href = dmg.browser_download_url; });
      if (sums) document.querySelectorAll("[data-sums]").forEach(function (a) { a.href = sums.browser_download_url; });
      info.forEach(function (el) {
        var v = values[el.dataset.release];
        if (v) el.textContent = v;
      });
    })
    .catch(function () { /* offline or rate-limited: keep the static fallback text and links */ });
})();
