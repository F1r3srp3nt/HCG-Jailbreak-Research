/* HCG Jailbreak Academy: page behaviour. No dependencies, no network requests, no tracking.
 * Stores only per-viewer conveniences in localStorage (theme, completed chapters, checklist ticks); the page works
 * fully without storage. Compatibility answers are never stored or sent anywhere. */
(function () {
  "use strict";
  var doc = document, root = doc.documentElement;
  var STORE = "hcg-academy-jailbreak-v1", THEME = "hcg-academy-theme";
  var live = doc.getElementById("live");

  function announce(msg) { if (live) { live.textContent = ""; setTimeout(function () { live.textContent = msg; }, 30); } }
  function read(k, fallback) { try { var v = localStorage.getItem(k); return v ? JSON.parse(v) : fallback; } catch (e) { return fallback; } }
  function write(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* storage unavailable: fine */ } }
  function $(sel, ctx) { return (ctx || doc).querySelector(sel); }
  function $$(sel, ctx) { return Array.prototype.slice.call((ctx || doc).querySelectorAll(sel)); }
  function esc(s) { return String(s).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }

  /* ---------------------------------------------------------- theme: auto -> light -> dark */
  var themeBtn = $("#theme-toggle");
  function applyTheme(mode) {
    if (mode === "light" || mode === "dark") root.setAttribute("data-theme", mode); else root.removeAttribute("data-theme");
    if (themeBtn) {
      var lbl = mode === "light" ? "Light" : mode === "dark" ? "Dark" : "Auto";
      $(".theme-label", themeBtn).textContent = "Appearance: " + lbl;
      themeBtn.setAttribute("aria-label", "Appearance: " + lbl + ". Change appearance");
    }
    var meta = $('meta[name="theme-color"]');
    var dark = mode === "dark" || (mode !== "light" && !(window.matchMedia && matchMedia("(prefers-color-scheme: light)").matches));
    if (meta) meta.setAttribute("content", dark ? "#05080b" : "#eef3f6");
  }
  var theme = read(THEME, "auto");
  applyTheme(theme);
  if (themeBtn) themeBtn.addEventListener("click", function () {
    theme = theme === "auto" ? "light" : theme === "light" ? "dark" : "auto";
    write(THEME, theme); applyTheme(theme); announce("Appearance set to " + theme);
  });

  /* ---------------------------------------------------------- progress */
  var state = read(STORE, { done: [], checklist: {} });
  if (!state || !Array.isArray(state.done)) state = { done: [], checklist: {} };
  state.checklist = state.checklist || {};
  var chapters = $$("section.chapter[data-chapter]");
  function save() { write(STORE, state); }
  function renderProgress() {
    var n = chapters.length, d = chapters.filter(function (c) { return state.done.indexOf(c.id) !== -1; }).length;
    var pct = n ? Math.round((d / n) * 100) : 0;
    var bar = $("#progress-bar");
    if (bar) { $("span", bar).style.width = pct + "%"; bar.setAttribute("aria-valuenow", String(d)); bar.setAttribute("aria-valuetext", d + " of " + n + " chapters completed"); }
    var t = $("#progress-text"); if (t) t.textContent = d + " of " + n + " chapters completed";
    chapters.forEach(function (c) {
      var done = state.done.indexOf(c.id) !== -1;
      $$('[data-toc="' + c.id + '"]').forEach(function (li) {
        li.classList.toggle("done", done);
        var sr = $(".sr-done", li); if (sr) sr.textContent = done ? " (completed)" : "";
      });
      var b = $(".mark-complete", c);
      if (b) { b.setAttribute("aria-pressed", done ? "true" : "false"); b.textContent = done ? "Completed ✓" : "Mark chapter complete"; }
    });
  }
  chapters.forEach(function (c) {
    var b = $(".mark-complete", c);
    if (!b) return;
    b.addEventListener("click", function () {
      var i = state.done.indexOf(c.id);
      if (i === -1) state.done.push(c.id); else state.done.splice(i, 1);
      save(); renderProgress();
      announce((i === -1 ? "Marked complete: " : "Marked not complete: ") + $("h2", c).textContent);
    });
  });
  var reset = $("#progress-reset");
  if (reset) reset.addEventListener("click", function () {
    state = { done: [], checklist: {} }; save(); renderProgress(); renderChecklist();
    $$(".checklist input").forEach(function (i) { i.checked = false; });
    announce("Progress and checklist reset");
  });
  renderProgress();

  /* current chapter in the table of contents */
  if ("IntersectionObserver" in window) {
    var current = null;
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { if (e.isIntersecting) current = e.target.id; });
      $$(".toc a, .toc-mobile a").forEach(function (a) {
        if (a.getAttribute("href") === "#" + current) a.setAttribute("aria-current", "true"); else a.removeAttribute("aria-current");
      });
    }, { rootMargin: "-20% 0px -70% 0px" });
    $$("section.chapter, section.extra").forEach(function (s) { io.observe(s); });
  }
  /* close the mobile chapter menu after choosing a chapter */
  $$(".toc-mobile a").forEach(function (a) { a.addEventListener("click", function () { var d = a.closest("details"); if (d) d.open = false; }); });

  /* ---------------------------------------------------------- preparation checklist */
  var boxes = $$(".checklist input[type=checkbox]");
  function renderChecklist() {
    var n = boxes.length, d = boxes.filter(function (b) { return b.checked; }).length;
    $$(".checklist-status").forEach(function (s) {
      s.textContent = d === n ? "All " + n + " preparation items done." : d + " of " + n + " preparation items done.";
    });
    var gate = $("#install-gate");
    if (gate) gate.hidden = d === n;
  }
  boxes.forEach(function (b) {
    b.checked = !!state.checklist[b.id];
    b.addEventListener("change", function () { state.checklist[b.id] = b.checked; save(); renderChecklist(); });
  });
  renderChecklist();

  /* ---------------------------------------------------------- copy buttons */
  function copyText(text, btn) {
    var label = btn.textContent;
    function done(ok) {
      btn.textContent = ok ? "Copied" : "Select and copy";
      announce(ok ? "Copied to clipboard" : "Copy failed; select the text and copy it manually");
      setTimeout(function () { btn.textContent = label; }, 2000);
    }
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(function () { done(true); }, function () { done(false); });
    } else {
      var ta = doc.createElement("textarea"); ta.value = text; ta.setAttribute("readonly", ""); ta.style.position = "absolute"; ta.style.left = "-9999px";
      doc.body.appendChild(ta); ta.select(); var ok = false; try { ok = doc.execCommand("copy"); } catch (e) { ok = false; }
      doc.body.removeChild(ta); done(ok);
    }
  }
  $$("[data-copy-from]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var el = doc.getElementById(btn.getAttribute("data-copy-from"));
      if (el) copyText(el.textContent.trim(), btn);
    });
  });

  /* ---------------------------------------------------------- tabs (ARIA tabs pattern) */
  function selectTab(tab, focus) {
    var list = tab.closest('[role="tablist"]');
    $$('[role="tab"]', list).forEach(function (t) {
      var on = t === tab;
      t.setAttribute("aria-selected", on ? "true" : "false");
      t.tabIndex = on ? 0 : -1;
      var p = doc.getElementById(t.getAttribute("aria-controls"));
      if (p) p.hidden = !on;
    });
    if (focus) tab.focus();
  }
  $$('[role="tablist"]').forEach(function (list) {
    var tabs = $$('[role="tab"]', list);
    tabs.forEach(function (t, i) {
      t.addEventListener("click", function () { selectTab(t, false); });
      t.addEventListener("keydown", function (e) {
        var k = e.key, j = null;
        if (k === "ArrowRight") j = (i + 1) % tabs.length;
        else if (k === "ArrowLeft") j = (i - 1 + tabs.length) % tabs.length;
        else if (k === "Home") j = 0; else if (k === "End") j = tabs.length - 1;
        if (j !== null) { e.preventDefault(); selectTab(tabs[j], true); }
      });
    });
  });
  $$("[data-show-route]").forEach(function (a) {
    a.addEventListener("click", function () { var t = doc.getElementById("tab-" + a.getAttribute("data-show-route")); if (t) selectTab(t, false); });
  });

  /* ---------------------------------------------------------- troubleshooting expand / collapse */
  $$("[data-details-all]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var open = btn.getAttribute("data-details-all") === "open";
      $$("details", doc.getElementById(btn.getAttribute("aria-controls"))).forEach(function (d) { d.open = open; });
      announce(open ? "All answers expanded" : "All answers collapsed");
    });
  });

  /* ---------------------------------------------------------- glossary search */
  var gq = $("#glossary-q"), gl = $("#glossary");
  if (gq && gl) {
    var items = $$("div", gl).map(function (div) {
      var dt = $("dt", div), dd = $("dd", div);
      return { div: div, dt: dt, dd: dd, t: dt.textContent, d: dd.innerHTML, text: (dt.textContent + " " + dd.textContent).toLowerCase() };
    });
    var gcount = $("#glossary-count");
    gq.addEventListener("input", function () {
      var q = gq.value.trim().toLowerCase(), shown = 0;
      items.forEach(function (it) {
        var hit = !q || it.text.indexOf(q) !== -1;
        it.div.hidden = !hit;
        if (hit) shown++;
        it.dt.innerHTML = q && hit ? esc(it.t).replace(new RegExp("(" + q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + ")", "ig"), "<mark>$1</mark>") : esc(it.t);
      });
      gcount.textContent = q ? shown + " of " + items.length + " terms match “" + gq.value.trim() + "”" : items.length + " terms";
    });
  }

  /* ---------------------------------------------------------- compatibility checker */
  var C = window.HCGCompat, DATA = window.HCG_COMPAT_DATA, form = $("#checker");
  if (C && DATA && form) {
    var sel = $("#cc-device"), filter = $("#cc-filter"), facts = $("#cc-facts"), ver = $("#cc-version"),
        vlist = $("#cc-versions"), buildRow = $("#cc-build-row"), out = $("#cc-result");
    function fillDevices(q) {
      var keep = sel.value, list = C.searchDevices(DATA, q), groups = {};
      list.forEach(function (d) { (groups[d.family] = groups[d.family] || []).push(d); });
      sel.innerHTML = '<option value="">' + (list.length ? "Choose your model…" : "No model matches that search") + "</option>";
      ["iPhone", "iPad"].forEach(function (fam) {
        if (!groups[fam]) return;
        var og = doc.createElement("optgroup"); og.label = fam;
        groups[fam].slice().sort(function (a, b) { return a.released < b.released ? -1 : a.released > b.released ? 1 : 0; })
          .forEach(function (d) { var o = doc.createElement("option"); o.value = d.key; o.textContent = d.name; og.appendChild(o); });
        sel.appendChild(og);
      });
      if (keep && list.some(function (d) { return d.key === keep; })) sel.value = keep;
      else if (list.length === 1) sel.value = list[0].key;
      onDevice();
    }
    function onDevice() {
      var d = null;
      for (var i = 0; i < DATA.devices.length; i++) if (DATA.devices[i].key === sel.value) d = DATA.devices[i];
      vlist.innerHTML = "";
      if (!d) { facts.textContent = ""; return; }
      facts.textContent = d.name + " · " + d.soc + " chip (" + d.arch + ") · model numbers " + d.models.join(", ");
      d.versions.forEach(function (i) { var o = doc.createElement("option"); o.value = DATA.versions[i].replace(" RC", ""); vlist.appendChild(o); });
    }
    function onVersion() {
      var v = C.normalizeVersion(ver.value);
      buildRow.hidden = !(v === "16.7" || v === "16.7 RC");
    }
    filter.addEventListener("input", function () { fillDevices(filter.value); });
    sel.addEventListener("change", onDevice);
    ver.addEventListener("input", onVersion);
    fillDevices("");
    onVersion();

    function radio(name) { var r = $('input[name="' + name + '"]:checked', form); return r ? r.value : ""; }
    var BADGE = { supported: "badge-ok", requirements: "badge-warn", unsupported: "badge-danger", unverified: "badge-info" };
    var LABEL = { supported: "Supported", requirements: "Requirements", unsupported: "Unsupported", unverified: "Not verified" };
    function list(items) { return "<ul>" + items.map(function (x) { return "<li>" + esc(x) + "</li>"; }).join("") + "</ul>"; }

    form.addEventListener("submit", function (e) {
      e.preventDefault();
      var input = {
        device: sel.value, version: ver.value, build: buildRow.hidden ? "" : radio("cc-build"),
        jailbreak: radio("cc-jb") || "unsure", trollstore: radio("cc-ts") || "unsure",
        backup: radio("cc-backup") || "no", firmware: radio("cc-fw") || "unsure"
      };
      if (input.build === "unsure") input.build = "";
      var r = C.evaluate(input, DATA);
      var h = '<h3 tabindex="-1" id="cc-result-h"><span class="badge ' + BADGE[r.verdict] + '">' + LABEL[r.verdict] + "</span> " + esc(r.title) + "</h3>";
      if (r.facts.device) h += '<p class="small muted">' + esc(r.facts.device) + (r.facts.chip ? " · " + esc(r.facts.chip) : "") + (r.facts.version ? " · iOS/iPadOS " + esc(r.facts.version) : "") + "</p>";
      h += list(r.reasons);
      if (r.route) {
        h += "<h4>Verified installation route</h4><p><strong>" + esc(r.route.name) + '</strong>. Follow <a href="#ch-9" data-show-route="' + r.route.id + '">Chapter 9</a> here, and the official guide: <a href="' + esc(r.route.source.url) + '" rel="noopener" target="_blank">' + esc(r.route.source.label) + "</a>.</p>";
      }
      if (r.trollstoreMethod) {
        h += "<h4>Installing TrollStore on your device</h4><p>The official guide's tab <strong>“" + esc(r.trollstoreMethod.tab) + "”</strong> applies to you (" +
             esc(r.trollstoreMethod.name) + (r.trollstoreMethod.computer === false ? ", no computer needed" : "") + ").</p>";
      }
      if (r.requirements.length) h += "<h4>Before you start</h4>" + list(r.requirements);
      if (r.notes.length) h += "<h4>Good to know</h4>" + list(r.notes);
      if (r.sources.length) h += '<h4>Sources</h4><ul class="small">' + r.sources.map(function (s) { return '<li><a href="' + esc(s.url) + '" rel="noopener" target="_blank">' + esc(s.label) + "</a></li>"; }).join("") + "</ul>";
      h += '<p class="small muted">Based on official statements reviewed ' + esc(r.lastReviewed) + ' and AppleDB device data (' + esc(DATA.source.commit.slice(0, 7)) + ", " + esc(DATA.source.date) +
           "). This checker never installs or runs anything. If Dopamine's official pages say something different, they win.</p>";
      out.className = "verdict verdict-" + r.verdict;
      out.innerHTML = h;
      $$("[data-show-route]", out).forEach(function (a) {
        a.addEventListener("click", function () { var t = doc.getElementById("tab-" + a.getAttribute("data-show-route")); if (t) selectTab(t, false); });
      });
      if (r.route) { var t = doc.getElementById("tab-" + r.route.id); if (t) selectTab(t, false); }
      $("#cc-result-h").focus();
    });
    form.addEventListener("reset", function () {
      setTimeout(function () { out.className = "verdict"; out.innerHTML = ""; fillDevices(""); onVersion(); announce("Checker cleared"); }, 0);
    });
  }
})();
