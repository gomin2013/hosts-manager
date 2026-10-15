/* =============================================================
   shared.js — Mock data, i18n table, validation, persistence
   Keys here are the source of truth for Localizable.strings (en / th).
   ============================================================= */

const STORAGE_LANGUAGE = "prototype.language";
const STORAGE_THEME    = "prototype.theme";
const STORAGE_PANELS   = "prototype.panels";

// ── Mock /etc/hosts (line model mirrors Swift `HostsLine`) ──
// kind: "comment" (text after "#") | "entry" | "blank". Starts with the header macOS ships with.
const MOCK_LINES = [
  { kind: "comment", text: "#" },
  { kind: "comment", text: " Host Database" },
  { kind: "comment", text: "" },
  { kind: "comment", text: " localhost is used to configure the loopback interface" },
  { kind: "comment", text: " when the system is booting.  Do not change this entry." },
  { kind: "comment", text: "#" },
  { kind: "entry", ip: "127.0.0.1",       hostnames: ["localhost"],              comment: "", isEnabled: true },
  { kind: "entry", ip: "255.255.255.255", hostnames: ["broadcasthost"],          comment: "", isEnabled: true },
  { kind: "entry", ip: "::1",             hostnames: ["localhost"],              comment: "", isEnabled: true },
  { kind: "blank" },
  { kind: "comment", text: " Local dev" },
  { kind: "entry", ip: "127.0.0.1",       hostnames: ["api.test", "web.test"],   comment: "docker compose", isEnabled: true },
  { kind: "entry", ip: "127.0.0.1",       hostnames: ["admin.test"],             comment: "", isEnabled: false },
  { kind: "blank" },
  { kind: "comment", text: " Staging" },
  { kind: "entry", ip: "10.0.0.5",        hostnames: ["staging.example.com"],    comment: "VPN only", isEnabled: false },
  { kind: "entry", ip: "fd00::5",         hostnames: ["staging6.example.com"],   comment: "", isEnabled: false },
  { kind: "blank" },
  { kind: "comment", text: " Blocked" },
  { kind: "entry", ip: "0.0.0.0",         hostnames: ["ads.example.net", "tracker.example.net"], comment: "", isEnabled: true }
];

// Same rule as Swift `HostEntry.isSystem`
const SYSTEM_PAIRS = [
  ["127.0.0.1", "localhost"], ["255.255.255.255", "broadcasthost"],
  ["::1", "localhost"], ["fe80::1%lo0", "localhost"]
];

function isSystemEntry(e) {
  return SYSTEM_PAIRS.some(([ip, host]) => e.ip === ip && e.hostnames.includes(host));
}

// Same as Swift `HostEntry.line` / `HostsLine.text`
function lineText(l) {
  if (l.kind === "blank") return "";
  if (l.kind === "comment") return "#" + l.text;
  let s = `${l.ip}\t${l.hostnames.join(" ")}`;
  if (l.comment) s += `\t# ${l.comment}`;
  return l.isEnabled ? s : "# " + s;
}

// ── i18n ───────────────────────────────────────────────────
const i18n = {
  en: {
    "app.title":               "Hosts Manager",
    "btn.add":                 "Add",
    "btn.addSection":          "Section",
    "btn.edit":                "Edit",
    "btn.delete":              "Delete",
    "btn.cancel":              "Cancel",
    "btn.save":                "Save",
    "btn.close":               "Close",
    "btn.copy":                "Copy",
    "btn.send":                "Send",
    "btn.import":              "Import",
    "btn.export":              "Export",
    "btn.restore":             "Restore Previous",
    "btn.previewRaw":          "Preview Raw",
    "btn.merge":               "Merge",
    "btn.replace":             "Replace",
    "btn.generateComment":     "Generate Comment",
    "hint.generateComment":    "Suggest a comment with AI — only this entry is sent",
    "hint.noBackup":           "No previous version yet — one is kept after the first save.",
    "dialog.importTitle":      "Import hosts file",
    "dialog.importConfirm":    "%ld entries found. Merge adds only new entries; Replace swaps all of yours (system entries stay).",
    "btn.settings":            "Settings",
    "placeholder.search":      "Search IP or hostname...",
    "placeholder.ip":          "127.0.0.1 or ::1",
    "placeholder.hostnames":   "example.test www.example.test",
    "placeholder.comment":     "Optional comment",
    "label.ip":                "IP Address",
    "label.hostnames":         "Hostnames",
    "label.comment":           "Comment",
    "label.enabled":           "Enabled",
    "label.disabled":          "Disabled",
    "editor.addTitle":         "Add Entry",
    "editor.editTitle":        "Edit Entry",
    "editor.hostnamesHint":    "Separate multiple hostnames with spaces",
    "err.invalidIP":           "Enter a valid IPv4 or IPv6 address",
    "err.invalidHostname":     "Invalid hostname: %@",
    "err.noHostnames":         "Enter at least one hostname",
    "settings.language":       "Language",
    "settings.appearance":     "Appearance",
    "appearance.system":       "System",
    "appearance.light":        "Light",
    "appearance.dark":         "Dark",
    "menu.about":              "About Hosts Manager",
    "menu.help":               "Help",
    "about.version":           "Version %@",
    "about.desc":              "Edit /etc/hosts safely — every change is validated, backed up and written by a privileged helper.",
    "helper.notInstalled":     "Helper not installed",
    "helper.ready":            "Helper ready",
    "helper.needsApproval":    "Helper needs approval",
    "helper.unavailable":      "Helper unavailable — run the .app built by scripts/build-app.sh",
    "helper.openSettings":     "Open Login Items…",
    "btn.ok":                  "OK",
    "err.title":               "Couldn't update /etc/hosts",
    "err.readFailed":          "Couldn't read %@.",
    "status.entries":          "%ld entries (%ld enabled)",
    "section.placeholder":     "Add heading...",
    "hint.addSection":         "Add a blank-line section break. Drag it into place and type a heading (saved as # heading).",
    "hint.dragSection":        "Drag to move this section",
    "hint.restore":            "Revert /etc/hosts to the version before the last save. Click again to undo the restore.",
    "hint.system":             "System entry — read-only",
    "hint.toggle":             "Enable or disable this entry",
    "empty.noResults":         "No entries match “%@”",
    "confirm.deleteTitle":     "Delete this entry?",
    "confirm.deleteMessage":   "%@ will be removed from /etc/hosts. A backup is kept.",
    "raw.title":               "Raw File Preview",
    "raw.copied":              "Copied!",
    "chat.title":              "AI Agent",
    "chat.placeholder":        "Ask AI...",
    "chat.welcome":            "👋 Hi! I'm your AI assistant. Ask me about your hosts entries.",
    "chat.noApiKey":           "⚠️ Please configure AI API in Settings first.",
    "ai.notConfigured":        "Not Set",
    "settings.title":          "AI API Settings",
    "settings.provider":       "Provider",
    "settings.apiKey":         "API Key",
    "settings.model":          "Model",
    "settings.loadModels":     "Load models",
    "settings.noModels":       "No models found.",
    "settings.appleNote":      "Runs on-device with Apple Intelligence (macOS 26+). No API key or model needed.",
    "settings.keychainNote":   "The API key is stored in your macOS Keychain.",
    "settings.privacyNote":    "Your questions include the contents of /etc/hosts, which is sent to this provider.",
    "quick.explain":           "Explain what my current entries do",
    "quick.conflicts":         "Are any entries duplicated or conflicting?",
    "quick.block":             "How do I block a domain?",
    "quick.localDev":          "Map a local dev domain to 127.0.0.1",
    "quick.organize":          "Group my entries into sections with headings",
    "a11y.collapsed":          "Collapsed",
    "a11y.expanded":           "Expanded",
    "a11y.toggleHint":         "Shows or hides this panel",
    "help.helper.title":       "Allow the Helper",
    "help.helper.desc":        "/etc/hosts belongs to root, so a small helper saves your changes. Allow it once in System Settings → General → Login Items & Extensions (or click Open Login Items… next to the status). A green dot means it's ready.",
    "help.add.title":          "Add an Entry",
    "help.add.desc":           "Click Add (⌘N), enter an IP address and one or more hostnames separated by spaces, e.g. 127.0.0.1 api.test. ✨ Generate Comment suggests a comment — only that entry is sent to the AI.",
    "help.toggle.title":       "Enable / Disable",
    "help.toggle.desc":        "Click the circle on a row to disable an entry without deleting it. It is saved as # 127.0.0.1 api.test. Double-click a row or ✎ to edit.",
    "help.search.title":       "Search",
    "help.search.desc":        "⌘F filters by IP or hostname. Only matching entries are shown while you search.",
    "help.sections.title":     "Sections",
    "help.sections.desc":      "Click Section to add a blank-line break, then type its heading (Return saves it as # heading). Clear the heading to remove it.",
    "help.reorder.title":      "Reorder",
    "help.reorder.desc":       "Drag rows to reorder — a section moves together with its heading. Dragging is off while searching; system rows stay put.",
    "help.system.title":       "System Entries",
    "help.system.desc":        "localhost and broadcasthost come with macOS and are locked 🔒 so the system keeps working. The helper refuses any file without 127.0.0.1 localhost.",
    "help.import.title":       "Import / Export",
    "help.import.desc":        "Import any hosts file — Merge adds only new entries, Replace swaps yours (this Mac's system entries stay). Export saves exactly what Preview Raw shows.",
    "help.restore.title":      "Restore Previous",
    "help.restore.desc":       "Every save keeps a backup (the last 20, in /Library/Application Support/HostsManager/Backups). Restore Previous reverts the last save; click again to undo.",
    "help.preview.title":      "Preview Raw",
    "help.preview.desc":       "See exactly what will be written to /etc/hosts, including your comment lines. Copy with ⇧⌘C.",
    "help.ai.title":           "AI Agent",
    "help.ai.desc":            "Ask about your entries or tap a Quick Message. Questions include your /etc/hosts; Apple Foundation Models and Ollama keep it on this Mac. Click the model name to switch models, ⚙ to change provider."
  },
  th: {
    "app.title":               "Hosts Manager",
    "btn.add":                 "เพิ่ม",
    "btn.addSection":          "หมวด",
    "btn.edit":                "แก้ไข",
    "btn.delete":              "ลบ",
    "btn.cancel":              "ยกเลิก",
    "btn.save":                "บันทึก",
    "btn.close":               "ปิด",
    "btn.copy":                "คัดลอก",
    "btn.send":                "ส่ง",
    "btn.import":              "นำเข้า",
    "btn.export":              "ส่งออก",
    "btn.restore":             "คืนค่าก่อนหน้า",
    "btn.previewRaw":          "ดูไฟล์จริง",
    "btn.merge":               "รวม",
    "btn.replace":             "แทนที่",
    "btn.generateComment":     "สร้างหมายเหตุ",
    "hint.generateComment":    "ให้ AI แนะนำหมายเหตุ — ส่งไปเฉพาะรายการนี้",
    "hint.noBackup":           "ยังไม่มีเวอร์ชันก่อนหน้า — จะมีหลังบันทึกครั้งแรก",
    "dialog.importTitle":      "นำเข้าไฟล์ hosts",
    "dialog.importConfirm":    "พบ %ld รายการ รวม จะเพิ่มเฉพาะรายการใหม่ แทนที่ จะแทนรายการของคุณทั้งหมด (รายการระบบยังอยู่)",
    "btn.settings":            "ตั้งค่า",
    "placeholder.search":      "ค้นหา IP หรือชื่อโฮสต์...",
    "placeholder.ip":          "127.0.0.1 หรือ ::1",
    "placeholder.hostnames":   "example.test www.example.test",
    "placeholder.comment":     "หมายเหตุ (ไม่บังคับ)",
    "label.ip":                "IP Address",
    "label.hostnames":         "ชื่อโฮสต์",
    "label.comment":           "หมายเหตุ",
    "label.enabled":           "เปิดใช้",
    "label.disabled":          "ปิดใช้",
    "editor.addTitle":         "เพิ่มรายการ",
    "editor.editTitle":        "แก้ไขรายการ",
    "editor.hostnamesHint":    "คั่นหลายชื่อด้วยช่องว่าง",
    "err.invalidIP":           "กรุณาใส่ IPv4 หรือ IPv6 ที่ถูกต้อง",
    "err.invalidHostname":     "ชื่อโฮสต์ไม่ถูกต้อง: %@",
    "err.noHostnames":         "กรุณาใส่ชื่อโฮสต์อย่างน้อยหนึ่งชื่อ",
    "settings.language":       "ภาษา",
    "settings.appearance":     "ธีม",
    "appearance.system":       "ตามระบบ",
    "appearance.light":        "สว่าง",
    "appearance.dark":         "มืด",
    "menu.about":              "เกี่ยวกับ Hosts Manager",
    "menu.help":               "วิธีใช้",
    "about.version":           "เวอร์ชัน %@",
    "about.desc":              "แก้ไข /etc/hosts อย่างปลอดภัย — ทุกการเปลี่ยนแปลงถูกตรวจสอบ สำรอง และเขียนโดย helper ที่มีสิทธิ์",
    "helper.notInstalled":     "ยังไม่ได้ติดตั้ง Helper",
    "helper.ready":            "Helper พร้อมใช้งาน",
    "helper.needsApproval":    "Helper รอการอนุญาต",
    "helper.unavailable":      "ใช้ Helper ไม่ได้ — ให้เปิดแอปที่สร้างจาก scripts/build-app.sh",
    "helper.openSettings":     "เปิด Login Items…",
    "btn.ok":                  "ตกลง",
    "err.title":               "แก้ไข /etc/hosts ไม่สำเร็จ",
    "err.readFailed":          "อ่าน %@ ไม่ได้",
    "status.entries":          "%ld รายการ (เปิดใช้ %ld)",
    "section.placeholder":     "เพิ่มหัวข้อ...",
    "hint.addSection":         "เพิ่มบรรทัดว่างคั่นหมวด ลากไปวางแล้วพิมพ์หัวข้อ (บันทึกเป็น # หัวข้อ)",
    "hint.dragSection":        "ลากเพื่อย้ายหมวดนี้",
    "hint.restore":            "คืน /etc/hosts เป็นเวอร์ชันก่อนการบันทึกครั้งล่าสุด กดอีกครั้งเพื่อยกเลิกการคืนค่า",
    "hint.system":             "รายการของระบบ — แก้ไขไม่ได้",
    "hint.toggle":             "เปิดหรือปิดรายการนี้",
    "empty.noResults":         "ไม่พบรายการที่ตรงกับ “%@”",
    "confirm.deleteTitle":     "ลบรายการนี้?",
    "confirm.deleteMessage":   "%@ จะถูกลบออกจาก /etc/hosts (มีสำเนาสำรองไว้)",
    "raw.title":               "ตัวอย่างไฟล์จริง",
    "raw.copied":              "คัดลอกแล้ว!",
    "chat.title":              "AI Agent",
    "chat.placeholder":        "ถาม AI...",
    "chat.welcome":            "👋 สวัสดีครับ! ผมคือผู้ช่วย AI ถามเรื่องรายการใน hosts ได้เลย",
    "chat.noApiKey":           "⚠️ กรุณาตั้งค่า AI API ใน Settings ก่อน",
    "ai.notConfigured":        "ยังไม่ตั้งค่า",
    "settings.title":          "ตั้งค่า AI API",
    "settings.provider":       "ผู้ให้บริการ",
    "settings.apiKey":         "API Key",
    "settings.model":          "โมเดล",
    "settings.loadModels":     "โหลดรายชื่อโมเดล",
    "settings.noModels":       "ไม่พบโมเดล",
    "settings.appleNote":      "ทำงานบนเครื่องด้วย Apple Intelligence (macOS 26 ขึ้นไป) ไม่ต้องใช้ API key หรือเลือกโมเดล",
    "settings.keychainNote":   "API key ถูกเก็บไว้ใน Keychain ของ macOS",
    "settings.privacyNote":    "คำถามของคุณจะแนบเนื้อหา /etc/hosts ไปยังผู้ให้บริการนี้ด้วย",
    "quick.explain":           "อธิบายว่ารายการตอนนี้ทำอะไรบ้าง",
    "quick.conflicts":         "มีรายการซ้ำหรือขัดกันไหม?",
    "quick.block":             "บล็อกโดเมนต้องทำอย่างไร?",
    "quick.localDev":          "ชี้โดเมน local dev ไปที่ 127.0.0.1",
    "quick.organize":          "จัดรายการเป็นหมวดพร้อมหัวข้อ",
    "a11y.collapsed":          "ย่ออยู่",
    "a11y.expanded":           "ขยายอยู่",
    "a11y.toggleHint":         "แสดงหรือซ่อนแผงนี้",
    "help.helper.title":       "อนุญาต Helper",
    "help.helper.desc":        "/etc/hosts เป็นของ root จึงใช้ helper ตัวเล็กบันทึกการเปลี่ยนแปลง อนุญาตครั้งเดียวที่ System Settings → General → Login Items & Extensions (หรือกด เปิด Login Items… ข้างสถานะ) จุดสีเขียว = พร้อมใช้งาน",
    "help.add.title":          "เพิ่มรายการ",
    "help.add.desc":           "กด เพิ่ม (⌘N) ใส่ IP และชื่อโฮสต์อย่างน้อยหนึ่งชื่อ คั่นด้วยช่องว่าง เช่น 127.0.0.1 api.test ✨ สร้างหมายเหตุ ให้ AI ช่วยเขียนหมายเหตุ — ส่งไปเฉพาะรายการนั้น",
    "help.toggle.title":       "เปิด / ปิดใช้",
    "help.toggle.desc":        "กดวงกลมหน้ารายการเพื่อปิดใช้โดยไม่ต้องลบ จะบันทึกเป็น # 127.0.0.1 api.test ดับเบิลคลิกแถวหรือ ✎ เพื่อแก้ไข",
    "help.search.title":       "ค้นหา",
    "help.search.desc":        "⌘F กรองตาม IP หรือชื่อโฮสต์ ระหว่างค้นหาจะแสดงเฉพาะรายการที่ตรงกัน",
    "help.sections.title":     "หมวด",
    "help.sections.desc":      "กด หมวด เพื่อเพิ่มบรรทัดว่างคั่น แล้วพิมพ์หัวข้อ (กด Return บันทึกเป็น # หัวข้อ) ลบข้อความหัวข้อออกเพื่อเอาหัวข้อออก",
    "help.reorder.title":      "จัดลำดับ",
    "help.reorder.desc":       "ลากแถวเพื่อจัดลำดับ — หมวดจะย้ายไปพร้อมหัวข้อ ระหว่างค้นหาลากไม่ได้ และรายการระบบจะอยู่ที่เดิม",
    "help.system.title":       "รายการของระบบ",
    "help.system.desc":        "localhost และ broadcasthost มากับ macOS และถูกล็อก 🔒 ไว้เพื่อให้ระบบทำงานปกติ helper จะไม่ยอมบันทึกไฟล์ที่ไม่มี 127.0.0.1 localhost",
    "help.import.title":       "นำเข้า / ส่งออก",
    "help.import.desc":        "นำเข้าไฟล์ hosts ใดก็ได้ — รวม จะเพิ่มเฉพาะรายการใหม่ แทนที่ จะแทนรายการของคุณ (รายการระบบของเครื่องนี้ยังอยู่) ส่งออกจะบันทึกตรงกับที่เห็นใน ดูไฟล์จริง",
    "help.restore.title":      "คืนค่าก่อนหน้า",
    "help.restore.desc":       "ทุกการบันทึกมีสำเนาสำรอง (เก็บ 20 ชุดล่าสุดใน /Library/Application Support/HostsManager/Backups) กด คืนค่าก่อนหน้า เพื่อย้อนการบันทึกล่าสุด กดอีกครั้งเพื่อยกเลิก",
    "help.preview.title":      "ดูไฟล์จริง",
    "help.preview.desc":       "ดูเนื้อหาที่จะถูกเขียนลง /etc/hosts จริง รวมบรรทัด comment ของคุณ คัดลอกด้วย ⇧⌘C",
    "help.ai.title":           "AI Agent",
    "help.ai.desc":            "ถามเรื่องรายการของคุณหรือกด Quick Message คำถามจะแนบ /etc/hosts ไปด้วย ถ้าใช้ Apple Foundation Models หรือ Ollama ข้อมูลจะอยู่ในเครื่องนี้ กดชื่อโมเดลเพื่อสลับโมเดล ⚙ เพื่อเปลี่ยนผู้ให้บริการ"
  }
};

// printf-style subset used by Localizable.strings: %@ and %ld
function t(lang, key, ...args) {
  let s = (i18n[lang] && i18n[lang][key]) || key;
  args.forEach(a => { s = s.replace(/%(@|ld)/, String(a)); });
  return s;
}

// ── Validation (reference for Swift `Validation`, Phase 2) ──
function isValidIPv4(s) {
  const parts = s.split(".");
  return parts.length === 4 && parts.every(p => /^\d{1,3}$/.test(p) && Number(p) <= 255);
}

function isValidIPv6(s) {
  // ponytail: loose check; Swift uses inet_pton
  return s.includes(":") && /^[0-9a-fA-F:.%a-z0-9]+$/.test(s) && (s.match(/::/g) || []).length <= 1;
}

function isValidHostname(s) {
  if (s.length < 1 || s.length > 253) return false;
  return s.split(".").every(l => /^[A-Za-z0-9-]{1,63}$/.test(l) && !l.startsWith("-") && !l.endsWith("-"));
}

// ── Persistence ────────────────────────────────────────────
function loadStored(key, fallback) {
  try { return window.localStorage.getItem(key) || fallback; } catch { return fallback; }
}

function persist(key, value) {
  try { window.localStorage.setItem(key, value); } catch { /* private mode */ }
}
