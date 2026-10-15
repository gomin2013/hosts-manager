/* =============================================================
   main.js — Window behaviour (mock, in-memory only)
   ============================================================= */

const state = {
  lines: MOCK_LINES.map(l => (l.kind === "entry" ? { ...l, hostnames: [...l.hostnames] } : { ...l })),
  query: "",
  lang: loadStored(STORAGE_LANGUAGE, "en"),
  theme: loadStored(STORAGE_THEME, "system"),
  panels: JSON.parse(loadStored(STORAGE_PANELS, '{"chat":true,"help":false}')),
  editingIndex: null,   // null = add, number = index into state.lines
  deletingRow: null,
  dragIndex: null
};

const QUICK_KEYS = ["quick.explain", "quick.conflicts", "quick.block", "quick.localDev", "quick.organize"];
// Same order as Swift `HelpList.items`: setup → add → organize → whole file → helpers
const HELP_ITEMS = [
  ["🛡", "help.helper"], ["⊕", "help.add"], ["✓", "help.toggle"], ["⌕", "help.search"], ["☰", "help.sections"],
  ["≡", "help.reorder"], ["🔒", "help.system"], ["⤓", "help.import"], ["↶", "help.restore"], ["👁", "help.preview"],
  ["✨", "help.ai"]
];

const $ = id => document.getElementById(id);
const L = (key, ...args) => t(state.lang, key, ...args);
const el = (tag, cls, text) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
};

// ── Rows (same rule as Swift `HostsViewModel.rows`) ──────────
// Blank line = section break; exactly one comment line right after it = the section's heading.
// Any other run of comment lines = one verbatim comment block. The block above the first entry that
// mentions "Host Database" is the macOS header (not deletable).
function buildRows(lines) {
  const rows = [];
  let i = 0;
  let seenEntry = false;
  const isComment = l => l && l.kind === "comment";
  while (i < lines.length) {
    const line = lines[i];
    if (line.kind === "blank") {
      if (isComment(lines[i + 1]) && !isComment(lines[i + 2])) {
        rows.push({ kind: "section", index: i, span: 2, title: lines[i + 1].text.trim() });
        i += 2;
      } else {
        rows.push({ kind: "section", index: i, span: 1, title: "" });
        i += 1;
      }
    } else if (line.kind === "comment") {
      const start = i;
      const text = [];
      while (isComment(lines[i])) { text.push(lineText(lines[i])); i++; }
      const joined = text.join("\n");
      rows.push({ kind: "comment", index: start, span: i - start, text: joined,
                  isSystem: !seenEntry && joined.includes("Host Database") });
    } else {
      seenEntry = true;
      rows.push({ kind: "entry", index: i, span: 1, entry: line });
      i += 1;
    }
  }
  return rows;
}

function matches(entry, query) {
  if (!query) return true;
  const q = query.toLowerCase();
  return entry.ip.toLowerCase().includes(q) || entry.hostnames.some(h => h.toLowerCase().includes(q));
}

// ── Render list ────────────────────────────────────────────
function render() {
  const list = $("entryList");
  list.innerHTML = "";
  const searching = state.query.length > 0;
  let rows = buildRows(state.lines);
  if (searching) rows = rows.filter(r => r.kind === "entry" && matches(r.entry, state.query));

  if (rows.length === 0) list.append(el("div", "empty", L("empty.noResults", state.query)));

  rows.forEach(row => {
    const node = row.kind === "entry" ? entryRow(row) : row.kind === "section" ? sectionRow(row) : commentRow(row);
    if (!searching && !(row.kind === "comment" && row.isSystem) && !(row.kind === "entry" && isSystemEntry(row.entry))) {
      wireDrag(node, row);
    }
    list.append(node);
  });

  const entries = state.lines.filter(l => l.kind === "entry");
  $("statusText").textContent = L("status.entries", entries.length, entries.filter(e => e.isEnabled).length);
}

function trashButton(row, name) {
  const b = el("button", "trash", "🗑");
  b.title = L("btn.delete");
  b.setAttribute("aria-label", `${L("btn.delete")} ${name}`);
  b.addEventListener("click", () => openDelete(row, name));
  return b;
}

function entryRow(row) {
  const e = row.entry;
  const system = isSystemEntry(e);
  const name = e.hostnames.join(" ");
  const node = el("div", "row" + (e.isEnabled ? "" : " off"));

  const toggle = el("button", "toggle" + (e.isEnabled ? " on" : ""), e.isEnabled ? "●" : "○");
  toggle.disabled = system;
  toggle.title = system ? L("hint.system") : L("hint.toggle");
  toggle.setAttribute("aria-label", `${L(e.isEnabled ? "label.enabled" : "label.disabled")}: ${name}`);
  toggle.addEventListener("click", () => { e.isEnabled = !e.isEnabled; render(); });

  const text = el("div", "entry-text");
  const line = el("div", "entry-line");
  line.append(el("span", "ip", e.ip), el("span", "hosts", e.hostnames.join("  ")));
  text.append(line);
  if (e.comment) text.append(el("div", "entry-comment", e.comment));

  node.append(toggle, text);
  if (system) {
    const lock = el("span", "lock", "🔒");
    lock.title = L("hint.system");
    node.append(lock);
  } else {
    const actions = el("div", "row-actions");
    const edit = el("button", "", "✎");
    edit.title = L("btn.edit");
    edit.setAttribute("aria-label", `${L("btn.edit")} ${name}`);
    edit.addEventListener("click", () => openEditor(row.index));
    actions.append(edit, trashButton(row, name));
    node.append(actions);
    node.addEventListener("dblclick", () => openEditor(row.index));
  }
  return node;
}

function sectionRow(row) {
  const node = el("div", "section-row");
  const grip = el("span", "grip", "≡");
  grip.title = L("hint.dragSection");
  const input = el("input");
  input.placeholder = L("section.placeholder");
  input.value = row.title;
  input.setAttribute("aria-label", L("section.placeholder"));
  input.addEventListener("change", () => renameSection(row, input.value.trim()));
  node.append(grip, input, el("span", "rule"), trashButton(row, row.title || L("btn.addSection")));
  return node;
}

function commentRow(row) {
  const node = el("div", "comment-row");
  node.append(el("pre", "", row.text));
  if (!row.isSystem) node.append(trashButton(row, row.text.split("\n")[0]));
  return node;
}

// Heading = the one comment line after the blank line; empty heading removes it.
function renameSection(row, title) {
  const replacement = title ? [{ kind: "blank" }, { kind: "comment", text: " " + title }] : [{ kind: "blank" }];
  state.lines.splice(row.index, row.span, ...replacement);
  render();
}

// ── Drag to reorder (moves the row's lines inside the flat line array) ──
function wireDrag(node, row) {
  node.draggable = true;
  node.addEventListener("dragstart", () => { state.dragIndex = row; node.classList.add("dragging"); });
  node.addEventListener("dragend", () => { state.dragIndex = null; render(); });
  node.addEventListener("dragover", e => { if (state.dragIndex) { e.preventDefault(); node.classList.add("drop-target"); } });
  node.addEventListener("dragleave", () => node.classList.remove("drop-target"));
  node.addEventListener("drop", e => {
    e.preventDefault();
    const from = state.dragIndex;
    if (!from || from.index === row.index) return;
    const moved = state.lines.splice(from.index, from.span);
    const to = from.index < row.index ? row.index - from.span : row.index;
    state.lines.splice(to, 0, ...moved);
    render();
  });
}

// ── Editor ─────────────────────────────────────────────────
function openEditor(index = null) {
  state.editingIndex = index;
  const entry = index === null ? { ip: "", hostnames: [], comment: "" } : state.lines[index];
  $("editorTitle").textContent = L(index === null ? "editor.addTitle" : "editor.editTitle");
  $("ipInput").value = entry.ip;
  $("hostnamesInput").value = entry.hostnames.join(" ");
  $("commentInput").value = entry.comment || "";
  validateEditor();
  $("editorSheet").hidden = false;
  $("ipInput").focus();
}

function validateEditor() {
  const ip = $("ipInput").value.trim();
  const hosts = $("hostnamesInput").value.trim().split(/\s+/).filter(Boolean);
  const badHost = hosts.find(h => !isValidHostname(h));
  const ipError = ip && !(isValidIPv4(ip) || isValidIPv6(ip)) ? L("err.invalidIP") : "";
  const hostError = badHost ? L("err.invalidHostname", badHost) : "";

  $("ipError").textContent = ipError;
  $("hostnamesError").textContent = hostError;
  $("ipInput").classList.toggle("invalid", !!ipError);
  $("hostnamesInput").classList.toggle("invalid", !!hostError);
  $("editorSave").disabled = !ip || hosts.length === 0 || !!ipError || !!hostError;
  return { ip, hosts };
}

function saveEditor(e) {
  e.preventDefault();
  if ($("editorSave").disabled) return;
  const { ip, hosts } = validateEditor();
  const comment = $("commentInput").value.trim();
  if (state.editingIndex === null) {
    state.lines.push({ kind: "entry", ip, hostnames: hosts, comment, isEnabled: true });
  } else {
    Object.assign(state.lines[state.editingIndex], { ip, hostnames: hosts, comment });
  }
  closeSheets();
  render();
}

// ── Delete ─────────────────────────────────────────────────
function openDelete(row, name) {
  state.deletingRow = row;
  $("deleteMessage").textContent = L("confirm.deleteMessage", name);
  $("deleteSheet").hidden = false;
  $("deleteConfirm").focus();
}

function confirmDelete() {
  state.lines.splice(state.deletingRow.index, state.deletingRow.span);
  closeSheets();
  render();
}

// ── Raw preview / About ────────────────────────────────────
function openRaw() {
  $("rawContent").textContent = state.lines.map(lineText).join("\n") + "\n";
  $("rawSheet").hidden = false;
}

async function copyRaw() {
  try { await navigator.clipboard.writeText($("rawContent").textContent); } catch { /* no permission in file:// */ }
  $("rawCopy").textContent = "✓";
  $("rawCopy").classList.add("copied");
  setTimeout(() => { $("rawCopy").textContent = "⧉"; $("rawCopy").classList.remove("copied"); }, 1500);
}

function closeSheets() {
  ["editorSheet", "deleteSheet", "rawSheet", "aboutSheet"].forEach(id => { $(id).hidden = true; });
}

// ── Side panels ────────────────────────────────────────────
function renderPanels() {
  [["chat", "chatPanel"], ["help", "helpPanel"]].forEach(([key, id]) => {
    $(id).classList.toggle("open", !!state.panels[key]);
    $(id).querySelector(".collapse").setAttribute("aria-expanded", String(!!state.panels[key]));
  });

  const quick = $("quickMessages");
  quick.innerHTML = "";
  QUICK_KEYS.forEach(key => {
    const b = el("button", "", L(key));
    b.disabled = true;   // needs an AI provider (Phase 3)
    quick.append(b);
  });

  const help = $("helpList");
  help.innerHTML = "";
  HELP_ITEMS.forEach(([icon, key]) => {
    const li = el("li");
    const body = el("div");
    body.append(el("strong", "", L(key + ".title")), el("small", "", L(key + ".desc")));
    li.append(el("span", "help-icon", icon), body);
    help.append(li);
  });
}

// ── Language / theme ───────────────────────────────────────
function applyLanguage() {
  document.documentElement.lang = state.lang;
  document.querySelectorAll("[data-i18n]").forEach(e => { e.textContent = L(e.dataset.i18n); });
  document.querySelectorAll("[data-i18n-placeholder]").forEach(e => { e.placeholder = L(e.dataset.i18nPlaceholder); });
  document.querySelectorAll("[data-i18n-title]").forEach(e => {
    e.title = L(e.dataset.i18nTitle);
    e.setAttribute("aria-label", e.title);
  });
  document.querySelectorAll("button[data-lang]").forEach(e => e.classList.toggle("checked", e.dataset.lang === state.lang));
  $("aboutVersion").textContent = L("about.version", "0.1.0");
  if (!$("editorSheet").hidden) {
    $("editorTitle").textContent = L(state.editingIndex === null ? "editor.addTitle" : "editor.editTitle");
    validateEditor();
  }
  renderPanels();
  render();
}

function applyTheme() {
  if (state.theme === "system") document.documentElement.removeAttribute("data-theme");
  else document.documentElement.dataset.theme = state.theme;
  document.querySelectorAll("button[data-theme]").forEach(e => e.classList.toggle("checked", e.dataset.theme === state.theme));
}

// ── Wiring ─────────────────────────────────────────────────
$("searchInput").addEventListener("input", e => { state.query = e.target.value.trim(); render(); });
$("addButton").addEventListener("click", () => openEditor());
$("rawButton").addEventListener("click", openRaw);
$("rawCopy").addEventListener("click", copyRaw);
$("aboutItem").addEventListener("click", () => { $("aboutSheet").hidden = false; });
document.querySelectorAll(".sheet-close").forEach(b => b.addEventListener("click", closeSheets));
$("settingsButton").addEventListener("click", e => { e.stopPropagation(); $("settingsDropdown").classList.toggle("open"); });
document.addEventListener("click", () => $("settingsDropdown").classList.remove("open"));
document.querySelectorAll("button[data-lang]").forEach(b => b.addEventListener("click", () => {
  state.lang = b.dataset.lang; persist(STORAGE_LANGUAGE, state.lang); applyLanguage();
}));
document.querySelectorAll("button[data-theme]").forEach(b => b.addEventListener("click", () => {
  state.theme = b.dataset.theme; persist(STORAGE_THEME, state.theme); applyTheme();
}));
document.querySelectorAll(".collapse").forEach(b => b.addEventListener("click", () => {
  state.panels[b.dataset.panel] = !state.panels[b.dataset.panel];
  persist(STORAGE_PANELS, JSON.stringify(state.panels));
  renderPanels();
}));
$("editorForm").addEventListener("submit", saveEditor);
$("editorForm").addEventListener("input", validateEditor);
$("editorCancel").addEventListener("click", closeSheets);
$("deleteCancel").addEventListener("click", closeSheets);
$("deleteConfirm").addEventListener("click", confirmDelete);

// ⌘Q / ⌘W are the native app menu in SwiftUI — not mocked here.
document.addEventListener("keydown", e => {
  if (e.key === "Escape") closeSheets();
  if (!e.metaKey) return;
  if (e.key === "f") { e.preventDefault(); $("searchInput").focus(); }
  if (e.key === "n") { e.preventDefault(); openEditor(); }
});

applyTheme();
applyLanguage();
