// Hosts Manager site: language picker, scroll reveal, latest release lookup. No dependencies.
(function () {
  "use strict";
  var root = document.documentElement;
  var KEY = "hm.lang";

  // ── Languages: the app's 12 (LanguageService.Language) — code, flag, native name, English name ──
  var LANGS = [
    ["en", "🇺🇸", "English", "English"], ["th", "🇹🇭", "ไทย", "Thai"],
    ["ja", "🇯🇵", "日本語", "Japanese"], ["ko", "🇰🇷", "한국어", "Korean"],
    ["vi", "🇻🇳", "Tiếng Việt", "Vietnamese"], ["id", "🇮🇩", "Bahasa Indonesia", "Indonesian"],
    ["ms", "🇲🇾", "Bahasa Melayu", "Malay"], ["tl", "🇵🇭", "Filipino", "Filipino"],
    ["zh-Hans", "🇨🇳", "简体中文", "Simplified Chinese"], ["zh-Hant", "🇹🇼", "繁體中文", "Traditional Chinese"],
    ["es", "🇪🇸", "Español", "Spanish"], ["ru", "🇷🇺", "Русский", "Russian"]
  ];
  // The picker's own words (title, search, no results — same as the app's Localizable.strings — and close)
  var UI = {
    en: ["Language", "Search languages", "No languages match “%@”", "Close"],
    th: ["ภาษา", "ค้นหาภาษา", "ไม่พบภาษาที่ตรงกับ “%@”", "ปิด"],
    ja: ["言語", "言語を検索", "「%@」に一致する言語はありません", "閉じる"],
    ko: ["언어", "언어 검색", "“%@”와(과) 일치하는 언어 없음", "닫기"],
    vi: ["Ngôn ngữ", "Tìm ngôn ngữ", "Không có ngôn ngữ nào khớp với “%@”", "Đóng"],
    id: ["Bahasa", "Cari bahasa", "Tidak ada bahasa yang cocok dengan “%@”", "Tutup"],
    ms: ["Bahasa", "Cari bahasa", "Tiada bahasa sepadan dengan “%@”", "Tutup"],
    tl: ["Wika", "Maghanap ng wika", "Walang wikang tumutugma sa “%@”", "Isara"],
    "zh-Hans": ["语言", "搜索语言", "没有与“%@”匹配的语言", "关闭"],
    "zh-Hant": ["語言", "搜尋語言", "沒有符合「%@」的語言", "關閉"],
    es: ["Idioma", "Buscar idiomas", "Ningún idioma coincide con “%@”", "Cerrar"],
    ru: ["Язык", "Поиск языков", "Нет языков, соответствующих «%@»", "Закрыть"]
  };
  function info(code) { return LANGS.filter(function (l) { return l[0] === code; })[0]; }
  // Short code on the header button (phones): zh-cn / zh-tw read better than zh-Hans / zh-Hant
  var SHORT = { "zh-Hans": "zh-cn", "zh-Hant": "zh-tw" };

  // ── Text: English and Thai are both in the page (.en / .th). Other languages replace the .en text with
  //    assets/i18n/<code>.json, keyed by the English HTML; a missing key stays English, like the app.
  //    <html data-i18n="…"> points a page that borrows this script (the gomin2013.github.io index) at its own files. ──
  var base = root.dataset.i18n || new URL("i18n/", document.currentScript.src).href;
  var texts = Array.prototype.map.call(document.querySelectorAll(".en"), function (el) { return [el, el.innerHTML]; });
  var dicts = {};
  function translate(lang) {
    var load = lang === "en" || lang === "th" ? Promise.resolve({}) : dicts[lang] || (dicts[lang] =
      fetch(base + lang + ".json").then(function (r) { return r.ok ? r.json() : {}; }).catch(function () { return {}; }));
    load.then(function (dict) {
      if (root.lang !== lang) return;  // another language was picked meanwhile
      texts.forEach(function (t) { t[0].innerHTML = dict[t[1].replace(/\s+/g, " ").trim()] || t[1]; });
      root.classList.remove("i18n-wait");
    });
  }

  // ── Picker: header button [data-lang-open] → modal <dialog> with search (built here, one copy for every page) ──
  var opener = document.querySelector("[data-lang-open]");
  var dialog, search, items = [], empty;
  // Search like the app: case- and accent-insensitive, over code, native, English and the name in the current language
  function fold(s) { return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase(); }
  function shown() { return items.filter(function (b) { return !b.parentNode.hidden; }); }
  function filter() {
    var q = fold(search.value.trim());
    items.forEach(function (b) { b.parentNode.hidden = Boolean(q) && b.dataset.search.indexOf(q) < 0; });
    empty.hidden = shown().length > 0;
    empty.textContent = UI[root.lang][2].replace("%@", search.value.trim());
  }
  if (opener) {
    dialog = document.createElement("dialog");
    dialog.className = "lang-dialog";
    dialog.setAttribute("aria-labelledby", "lang-title");
    dialog.innerHTML = '<div class="lang-panel"><div class="lang-head"><h2 id="lang-title"></h2>' +
      '<button type="button" class="lang-close"><i class="ph ph-x" aria-hidden="true"></i></button></div>' +
      '<label class="lang-search"><i class="ph ph-magnifying-glass" aria-hidden="true"></i>' +
      '<input type="search" autocomplete="off" spellcheck="false"></label><ul class="lang-options">' +
      LANGS.map(function (l) {
        return '<li><button type="button" data-lang="' + l[0] + '"><span class="flag" aria-hidden="true">' + l[1] +
          '</span><span lang="' + l[0] + '">' + l[2] + '</span><small></small></button></li>';
      }).join("") + '</ul><p class="lang-empty" role="status" hidden></p></div>';
    document.body.appendChild(dialog);
    search = dialog.querySelector("input");
    items = Array.prototype.slice.call(dialog.querySelectorAll("[data-lang]"));
    empty = dialog.querySelector(".lang-empty");

    search.addEventListener("input", filter);
    search.addEventListener("keydown", function (e) {
      // preventDefault: otherwise this Enter also presses the header button that gets focus back on close
      if (e.key === "Enter" && shown()[0]) { e.preventDefault(); shown()[0].click(); }
      if (e.key === "ArrowDown" && shown()[0]) { e.preventDefault(); shown()[0].focus(); }
    });
    dialog.querySelector(".lang-options").addEventListener("keydown", function (e) {
      if (e.key !== "ArrowDown" && e.key !== "ArrowUp") return;
      var list = shown(), i = list.indexOf(document.activeElement) + (e.key === "ArrowDown" ? 1 : -1);
      e.preventDefault();
      (i < 0 ? search : list[Math.min(i, list.length - 1)]).focus();
    });
    // Close: Esc (native), the × button, or a click on the backdrop (the dialog itself, outside .lang-panel)
    dialog.addEventListener("click", function (e) {
      if (e.target === dialog || e.target.closest(".lang-close")) dialog.close();
    });
    opener.addEventListener("click", function () {
      search.value = "";
      filter();
      dialog.showModal();
      var current = dialog.querySelector('[aria-current="true"]');
      if (current) current.scrollIntoView({ block: "nearest" });
      // Touch: don't pop the keyboard over the list; focus the current language instead
      (matchMedia("(pointer: fine)").matches ? search : current || search).focus();
    });
  }

  function setLang(lang) {
    var l = info(lang), ui = UI[lang], names;
    root.lang = lang;
    root.classList.toggle("th", lang === "th");
    // [data-lang]: the picker's languages, and the old EN/TH pill on pages that still have it
    document.querySelectorAll("[data-lang]").forEach(function (b) {
      b.setAttribute(b.closest(".lang") ? "aria-pressed" : "aria-current", String(b.dataset.lang === lang));
    });
    if (opener) {
      opener.querySelector(".lang-name").textContent = l[2];
      opener.querySelector(".lang-code").textContent = SHORT[lang] || lang;
      opener.setAttribute("aria-label", ui[0] + ": " + l[2]);
      dialog.querySelector("h2").textContent = ui[0];
      dialog.querySelector(".lang-close").setAttribute("aria-label", ui[3]);
      search.placeholder = ui[1];
      search.setAttribute("aria-label", ui[1]);
      try { names = new Intl.DisplayNames([lang], { type: "language" }); } catch (e) { /* old browser: no translated names */ }
      items.forEach(function (b) {
        var it = info(b.dataset.lang), name = names && names.of(it[0]);
        b.querySelector("small").textContent = name && name !== it[2] ? name : "";
        b.dataset.search = fold([it[0], SHORT[it[0]] || "", it[2], it[3], name || ""].join(" "));  // "zh-tw" finds it too
      });
    }
    translate(lang);
  }
  document.addEventListener("click", function (e) {
    var b = e.target.closest("[data-lang]");
    if (!b) return;
    setLang(b.dataset.lang);
    try { localStorage.setItem(KEY, b.dataset.lang); } catch (err) { /* private mode */ }
    if (dialog && dialog.open) dialog.close();
  });
  setLang(info(root.lang) ? root.lang : "en");  // the <head> snippet picked it before first paint

  // ── Reveal on scroll (IntersectionObserver, no scroll listeners) ──
  var reveal = document.querySelectorAll(".reveal");
  if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.12 });
    reveal.forEach(function (el) { io.observe(el); });
  } else {
    reveal.forEach(function (el) { el.classList.add("in"); });
  }

  // "v1.0.2" < "v1.1.1": compares the numbers, not the text
  function isOlder(a, b) {
    var x = (a.match(/\d+/g) || []).map(Number), y = (b.match(/\d+/g) || []).map(Number);
    for (var i = 0; i < Math.max(x.length, y.length); i++) {
      if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) < (y[i] || 0);
    }
    return false;
  }

  // ── Latest release: version + direct DMG link. Links already point at /releases/latest if this fails. ──
  var dl = document.querySelectorAll("[data-dmg]");
  var release = document.querySelectorAll("[data-release]");
  if (!dl.length && !release.length) return;
  fetch("https://api.github.com/repos/gomin2013/hosts-manager/releases/latest", {
    headers: { Accept: "application/vnd.github+json" }
  })
    .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
    .then(function (rel) {
      // Never step back: right after a merge this page already names the new version while its release may still be
      // a draft, so GitHub's "latest" is the previous one. Keep the page's own version, file and date then.
      var page = document.querySelector('[data-release="version"]');
      if (page && isOlder(rel.tag_name, page.textContent)) return;
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
      release.forEach(function (el) {
        var v = values[el.dataset.release];
        if (v) el.textContent = v;
      });
    })
    .catch(function () { /* offline or rate-limited: keep the static fallback text and links */ });
})();
