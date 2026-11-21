// End-to-end checks of the built preview in Chromium (Playwright) with axe-core.
//   python3 tools/build_preview.py --hcg-repo /path/to/HCG-repo --out _preview
//   AXE_PATH=/path/to/axe.min.js node tests/e2e.mjs
// Writes docs/test-results/e2e.json and screenshots to docs/preview/. Exits non-zero on any failure.
import { createRequire } from "node:module";
import http from "node:http";
import { readFileSync, writeFileSync, mkdirSync, existsSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
const { chromium, devices } = createRequire(import.meta.url)("playwright"); // the preinstalled Playwright

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SITE = path.join(ROOT, "_preview");
const AXE = process.env.AXE_PATH;
if (!existsSync(path.join(SITE, "academy/jailbreak/index.html"))) { console.error("build _preview first"); process.exit(2); }
if (!AXE || !existsSync(AXE)) { console.error("set AXE_PATH to axe.min.js (npm i axe-core)"); process.exit(2); }
const axeSource = readFileSync(AXE, "utf8");
const SHOTS = path.join(ROOT, "docs/preview");
mkdirSync(SHOTS, { recursive: true });
mkdirSync(path.join(ROOT, "docs/test-results"), { recursive: true });

const TYPES = { ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".svg": "image/svg+xml",
  ".png": "image/png", ".jpg": "image/jpeg", ".webp": "image/webp", ".json": "application/json" };
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, "http://x").pathname);
  let f = path.join(SITE, p);
  if (!f.startsWith(SITE)) { res.writeHead(403); return res.end(); }
  if (existsSync(f) && statSync(f).isDirectory()) f = path.join(f, "index.html");
  if (!existsSync(f)) { res.writeHead(404); return res.end("not found"); }
  res.writeHead(200, { "content-type": TYPES[path.extname(f)] || "application/octet-stream" });
  res.end(readFileSync(f));
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const BASE = `http://127.0.0.1:${server.address().port}`;
const URL_ = `${BASE}/academy/jailbreak/`;

const results = [];
let failed = 0;
async function check(name, fn) {
  try { const detail = await fn(); results.push({ name, ok: true, detail: detail ?? "" }); console.log("ok  ", name, detail ?? ""); }
  catch (e) { failed++; results.push({ name, ok: false, detail: String(e.message || e) }); console.log("FAIL", name, e.message || e); }
}
function assert(c, msg) { if (!c) throw new Error(msg); }

async function axe(page) {
  await page.addScriptTag({ content: axeSource });
  return page.evaluate(async () => {
    const r = await window.axe.run(document, { runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa", "best-practice"] } });
    return { violations: r.violations.map((v) => ({ id: v.id, impact: v.impact, help: v.help, nodes: v.nodes.length,
      targets: v.nodes.slice(0, 3).map((n) => n.target.join(" ")) })), passes: r.passes.length };
  });
}

const browser = await chromium.launch();
const errors = [];
async function open(opts = {}) {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1, ...opts });
  const page = await ctx.newPage();
  page.on("pageerror", (e) => errors.push(String(e)));
  page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
  page.on("requestfailed", (r) => errors.push("request failed: " + r.url()));
  page.on("response", (r) => { if (r.status() >= 400) errors.push(`HTTP ${r.status()} ${r.url()}`); });
  await page.goto(URL_, { waitUntil: "networkidle" });
  return { ctx, page };
}

// ---------------------------------------------------------------- accessibility in each appearance and layout
for (const [label, opts] of [["desktop dark", { colorScheme: "dark" }], ["desktop light", { colorScheme: "light" }],
                             ["mobile dark", { ...devices["iPhone 13"], colorScheme: "dark" }],
                             ["mobile light", { ...devices["iPhone 13"], colorScheme: "light" }]]) {
  await check(`axe WCAG 2.2 AA + best practice: ${label}`, async () => {
    const { ctx, page } = await open(opts);
    // open every collapsible so hidden content is checked too, and show a checker result
    await page.evaluate(() => document.querySelectorAll("details").forEach((d) => (d.open = true)));
    await page.selectOption("#cc-device", { label: "iPhone 12" });
    await page.fill("#cc-version", "17.4");
    await page.click('#checker button[type="submit"]');
    const r = await axe(page);
    await ctx.close();
    assert(r.violations.length === 0, JSON.stringify(r.violations));
    return `${r.passes} rules passed, 0 violations`;
  });
}

await check("no horizontal overflow at 320 px and on iPhone 13 (guide and HCG pages)", async () => {
  const pages = ["/academy/jailbreak/", "/", "/products/hcg-nexus/", "/repo/candidate/"];
  for (const vp of [{ width: 320, height: 640 }, devices["iPhone 13"].viewport]) {
    for (const u of pages) {
      const c = await browser.newContext({ viewport: vp });
      const p = await c.newPage();
      await p.goto(BASE + u, { waitUntil: "networkidle" });
      // body has overflow-x: hidden, so measure content that sticks out instead of scrollWidth
      const over = await p.evaluate(() => {
        let worst = 0;
        document.querySelectorAll("body *").forEach((e) => {
          const r = e.getBoundingClientRect();
          if (!r.width) return;
          for (let a = e.parentElement; a && a !== document.body; a = a.parentElement) {
            if (/(auto|scroll|hidden)/.test(getComputedStyle(a).overflowX)) return;
          }
          worst = Math.max(worst, r.right - window.innerWidth);
        });
        return Math.round(worst);
      });
      await c.close();
      assert(over <= 1, `${u} overflows by ${over}px at ${vp.width}px`);
    }
  }
  return `${pages.length} pages x 2 widths`;
});

// ---------------------------------------------------------------- behaviour
const { ctx, page } = await open({ colorScheme: "dark" });
await ctx.grantPermissions(["clipboard-read", "clipboard-write"], { origin: BASE });

await check("page loads all assets without errors", async () => {
  assert(await page.evaluate(() => !!window.HCGCompat && !!window.HCG_COMPAT_DATA), "scripts not loaded");
  return `${await page.evaluate(() => window.HCG_COMPAT_DATA.devices.length)} models loaded`;
});
await check("15 chapters, each with a completion button", async () => {
  const n = await page.locator("section.chapter[data-chapter]").count();
  const b = await page.locator("section.chapter[data-chapter] .mark-complete").count();
  assert(n === 15 && b === 15, `${n} chapters, ${b} buttons`);
  return "15/15";
});

async function runChecker(model, version, extra = {}) {
  await page.click('#checker button[type="reset"]');
  await page.fill("#cc-filter", "");
  await page.selectOption("#cc-device", { label: model });
  await page.fill("#cc-version", version);
  await page.dispatchEvent("#cc-version", "input");
  for (const [name, value] of Object.entries(extra)) await page.check(`input[name="${name}"][value="${value}"]`, { force: true });
  await page.click('#checker button[type="submit"]');
  return (await page.locator("#cc-result-h").textContent()).trim();
}
await check("checker: Supported (iPhone 12, 15.4.1, backup, TrollHelperOTA)", async () => {
  const t = await runChecker("iPhone 12", "15.4.1", { "cc-backup": "yes" });
  assert(/Supported$/.test(t) && !/requirements/i.test(t), t);
  assert((await page.locator("#cc-result").textContent()).includes("TrollHelperOTA"), "method missing");
  assert(await page.evaluate(() => document.activeElement.id === "cc-result-h"), "focus not moved to result");
  return t;
});
await check("checker: Supported with specific requirements (iPhone 15 Pro, 17.3.1)", async () => {
  const t = await runChecker("iPhone 15 Pro", "17.3.1", { "cc-backup": "yes" });
  assert(/specific requirements/.test(t), t);
  assert(await page.getAttribute("#tab-sideload", "aria-selected") === "true", "sideload tab not selected");
  return t;
});
await check("checker: Unsupported (iPhone 12, 17.4)", async () => {
  const t = await runChecker("iPhone 12", "17.4"); assert(/Unsupported/.test(t), t); return t;
});
await check("checker: cannot be verified (iPhone X, 17.0 never released for it)", async () => {
  const t = await runChecker("iPhone X", "17.0"); assert(/cannot yet be verified/.test(t), t); return t;
});
await check("checker: 16.7 asks for the build number", async () => {
  await page.click('#checker button[type="reset"]');
  await page.selectOption("#cc-device", { label: "iPhone 11" });
  await page.fill("#cc-version", "16.7");
  assert(await page.isVisible("#cc-build-row"), "build row hidden");
  return "build row shown";
});
await check("checker: search by model number A2161", async () => {
  await page.click('#checker button[type="reset"]');
  await page.fill("#cc-filter", "A2161");
  const v = await page.inputValue("#cc-device");
  assert(v === "iphone-11-pro-max", v);
  return v;
});

await check("progress: mark complete, persists across reload, reset", async () => {
  await page.click("#ch-1 .mark-complete");
  assert((await page.textContent("#progress-text")).startsWith("1 of 15"), await page.textContent("#progress-text"));
  assert(await page.getAttribute("#ch-1 .mark-complete", "aria-pressed") === "true", "aria-pressed");
  await page.reload({ waitUntil: "networkidle" });
  assert((await page.textContent("#progress-text")).startsWith("1 of 15"), "not persisted");
  await page.click("#progress-reset");
  assert((await page.textContent("#progress-text")).startsWith("0 of 15"), "not reset");
  return "ok";
});
await check("preparation checklist updates status and install gate", async () => {
  const boxes = page.locator(".checklist input");
  const n = await boxes.count();
  for (let i = 0; i < n; i++) await boxes.nth(i).check();
  assert(await page.isHidden("#install-gate"), "gate still visible");
  await boxes.nth(0).uncheck();
  assert(await page.isVisible("#install-gate"), "gate hidden");
  return `${n} items`;
});
await check("tabs: keyboard arrows switch the route panel", async () => {
  await page.click("#tab-trollstore");
  await page.focus("#tab-trollstore");
  await page.keyboard.press("ArrowRight");
  assert(await page.getAttribute("#tab-sideload", "aria-selected") === "true", "not switched");
  assert(await page.isVisible("#panel-sideload") && await page.isHidden("#panel-trollstore"), "panels");
  assert(await page.evaluate(() => document.activeElement.id) === "tab-sideload", "focus");
  return "ok";
});
await check("glossary search filters terms", async () => {
  await page.fill("#glossary-q", "respring");
  const shown = await page.locator("#glossary > div:not([hidden])").count();
  assert(shown >= 1 && shown < 36, `${shown} shown`);
  await page.fill("#glossary-q", "");
  return `${shown} match “respring”`;
});
await check("troubleshooting expand all / collapse all", async () => {
  await page.click('[data-details-all="open"]');
  const open = await page.locator("#trouble-list details[open]").count();
  const all = await page.locator("#trouble-list details").count();
  await page.click('[data-details-all="close"]');
  const closed = await page.locator("#trouble-list details[open]").count();
  assert(open === all && closed === 0, `${open}/${all}, ${closed}`);
  return `${all} items`;
});
await check("copy button copies the command", async () => {
  await page.click('[data-details-all="open"]');
  await page.click('[data-copy-from="cmd-uicache"]');
  await page.waitForFunction(() => document.querySelector('[data-copy-from="cmd-uicache"]').textContent === "Copied");
  const clip = await page.evaluate(() => navigator.clipboard.readText());
  assert(clip === "uicache -a", clip);
  return clip;
});
await check("theme toggle: auto → light → dark → auto", async () => {
  const seq = [];
  for (let i = 0; i < 3; i++) { await page.click("#theme-toggle"); seq.push(await page.getAttribute("html", "data-theme")); }
  assert(JSON.stringify(seq) === JSON.stringify(["light", "dark", null]), JSON.stringify(seq));
  return "light, dark, auto";
});
await check("keyboard: skip link moves focus to main", async () => {
  await page.goto(URL_, { waitUntil: "networkidle" });
  await page.keyboard.press("Tab");
  assert((await page.evaluate(() => document.activeElement.textContent)).includes("Skip"), "skip link not first");
  await page.keyboard.press("Enter");
  assert(await page.evaluate(() => document.activeElement.id) === "main", "focus not on main");
  return "ok";
});
await check("no console errors, failed requests or HTTP errors", async () => {
  assert(errors.length === 0, errors.join("\n")); return "none";
});
await ctx.close();

// ---------------------------------------------------------------- screenshots for review (2x)
async function shot(file, opts, fn) {
  // reduced motion turns off site.css's smooth scrolling, so the capture is not taken mid-scroll
  const c = await browser.newContext({ viewport: { width: 1280, height: 860 }, deviceScaleFactor: 2, reducedMotion: "reduce", ...opts });
  const p = await c.newPage();
  await p.goto(URL_, { waitUntil: "networkidle" });
  if (fn) await fn(p);
  await p.waitForTimeout(400);
  await p.screenshot({ path: path.join(SHOTS, file) });
  await c.close();
}
const toChecker = async (p) => {
  await p.selectOption("#cc-device", { label: "iPhone 11 Pro Max" });
  await p.fill("#cc-version", "17.4");
  await p.check('input[name="cc-backup"][value="yes"]', { force: true });
  await p.click('#checker button[type="submit"]');
  await p.locator("#cc-result").scrollIntoViewIfNeeded();
  await p.evaluate(() => document.querySelector("#checker-h").scrollIntoView());
};
await shot("desktop-dark-hero.png", { colorScheme: "dark" });
await shot("desktop-light-hero.png", { colorScheme: "light" });
await shot("desktop-dark-checker.png", { colorScheme: "dark" }, toChecker);
await shot("desktop-light-checker-result.png", { colorScheme: "light" }, async (p) => { await toChecker(p); await p.evaluate(() => document.querySelector("#cc-result").scrollIntoView({ block: "center" })); });
await shot("desktop-dark-install.png", { colorScheme: "dark" }, async (p) => p.evaluate(() => document.querySelector("#ch-9 .tabs").scrollIntoView()));
await shot("desktop-dark-ecosystem.png", { colorScheme: "dark" }, async (p) => p.evaluate(() => document.querySelector("#ch-15").scrollIntoView()));
await shot("mobile-dark-hero.png", { ...devices["iPhone 13"], colorScheme: "dark" });
await shot("mobile-light-running.png", { ...devices["iPhone 13"], colorScheme: "light" }, async (p) => p.evaluate(() => document.querySelector("#ch-10 .phones").scrollIntoView()));
await shot("mobile-dark-troubleshooting.png", { ...devices["iPhone 13"], colorScheme: "dark" }, async (p) => {
  await p.evaluate(() => { document.querySelectorAll("#trouble-list details")[2].open = true; document.querySelector("#trouble-h").scrollIntoView(); });
});
await shot("site-home-with-academy-link.png", { colorScheme: "dark", viewport: { width: 1280, height: 500 } }, async (p) => p.goto(`${BASE}/`, { waitUntil: "networkidle" }));

await browser.close();
server.close();
writeFileSync(path.join(ROOT, "docs/test-results/e2e.json"),
  JSON.stringify({ date: new Date().toISOString(), chromium: true, passed: results.length - failed, failed, results }, null, 2) + "\n");
console.log(`\n${results.length - failed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
