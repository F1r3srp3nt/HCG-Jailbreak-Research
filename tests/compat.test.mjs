// Unit tests for academy/assets/compat.js. Run: node --test tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const root = new URL("../academy/", import.meta.url);
const ctx = { globalThis: {} };
ctx.window = ctx.globalThis;
vm.createContext(ctx);
vm.runInContext(readFileSync(new URL("assets/compat.js", root), "utf8"), ctx);
const C = ctx.globalThis.HCGCompat;
const DATA = JSON.parse(readFileSync(new URL("data/compat-data.json", root), "utf8"));

const key = (name) => {
  const d = DATA.devices.find((x) => x.name === name);
  assert.ok(d, `device ${name} in dataset`);
  return d.key;
};
const base = { jailbreak: "none", trollstore: "no", backup: "yes", firmware: "updated" };
const run = (name, version, extra = {}) => C.evaluate({ ...base, device: key(name), version, ...extra }, DATA);

test("version normalisation", () => {
  assert.equal(C.normalizeVersion("17"), "17.0");
  assert.equal(C.normalizeVersion("iOS 17.0.0"), "17.0");
  assert.equal(C.normalizeVersion("16.7 (20H18)"), "16.7 RC");
  assert.equal(C.normalizeVersion("16.7", "20H19"), "16.7");
  assert.equal(C.normalizeVersion("banana"), null);
  assert.ok(C.compare("16.7 RC", "16.6.1") > 0 && C.compare("16.7 RC", "16.7") < 0);
});

test("TrollStore range follows its README", () => {
  for (const v of ["15.0", "15.8.8", "16.6.1", "16.7 RC", "17.0"]) assert.equal(C.trollStoreCanRun(v), true, v);
  for (const v of ["16.7", "16.7.16", "17.0.1", "17.3.1", "18.0"]) assert.equal(C.trollStoreCanRun(v), false, v);
});

test("supported: TrollStore already installed, backup made", () => {
  const r = run("iPhone 13 Pro", "16.5", { trollstore: "yes" });
  assert.equal(r.verdict, "supported");
  assert.equal(r.route.id, "trollstore");
});

test("requirements: no backup turns supported into requirements", () => {
  const r = run("iPhone 13 Pro", "16.5", { trollstore: "yes", backup: "no" });
  assert.equal(r.verdict, "requirements");
  assert.match(r.requirements[0], /backup/i);
});

test("TrollHelperOTA needs no computer: supported outright", () => {
  const r = run("iPhone 12", "15.4.1");
  assert.equal(r.trollstoreMethod.id, "trollhelperota");
  assert.equal(r.verdict, "supported");
});

test("TrollStore installer selection per cfw.guide tabs", () => {
  const m = (name, v) => C.trollStoreMethod(DATA.devices.find((d) => d.name === name).soc, v).id;
  assert.equal(m("iPhone 8", "15.5"), "trollinstallerx");        // A11 15.5-15.6.1
  assert.equal(m("iPhone XR", "15.5"), "trollhelperota");        // A12+ 15.5-15.6.1
  assert.equal(m("iPad Air 2", "15.6"), "trollinstallermdc");    // A8X 15.5-15.7.1
  assert.equal(m("iPad Air 2", "15.7.1"), "trollinstallermdc");
  assert.equal(m("iPad Air 2", "15.7.2"), "trollrestore");       // A8X 15.7.2-15.8.6
  assert.equal(m("iPhone 7", "15.7.2"), "trollinstallerx");      // A9+ 15.7-15.8.6
  assert.equal(m("iPhone 7", "15.8.8"), "trollrestore");
  assert.equal(m("iPhone 14", "16.0"), "trollinstallerx");
  assert.equal(m("iPhone 11", "16.7 RC"), "trollrestore");
  assert.equal(m("iPhone 15", "17.0"), "trollrestore");
  const s = (name, v) => C.trollStoreMethod(DATA.devices.find((d) => d.name === name).soc, v).additionalSteps;
  assert.equal(s("iPhone XS", "16.6.1"), true);                  // A12+ 16.6-16.6.1
  assert.equal(s("iPhone 14 Pro", "16.5.1"), true);               // A16 16.5.1
  assert.equal(s("iPhone 12", "16.5.1"), false);                  // A14 16.5.1
  assert.equal(s("iPhone 8", "16.6.1"), false);                   // A11
});

test("16.7 needs the build number", () => {
  const r = run("iPhone 11", "16.7");
  assert.equal(r.verdict, "unverified");
  assert.equal(r.needsBuild, true);
  assert.equal(run("iPhone 11", "16.7", { build: "20H18" }).route.id, "trollstore");
  assert.equal(run("iPhone 11", "16.7", { build: "20H19" }).route.id, "sideload");
});

test("sideload route always has requirements (computer, 7-day re-sign)", () => {
  const r = run("iPhone 15 Pro", "17.3.1");
  assert.equal(r.verdict, "requirements");
  assert.equal(r.route.id, "sideload");
  assert.ok(r.requirements.some((x) => /7 days/.test(x)));
});

test("A13 and earlier on 17.4-18.7.1 and 26.0-26.0.1", () => {
  assert.equal(run("iPhone 11 Pro Max", "17.4").verdict, "requirements");
  assert.equal(run("iPhone XR", "18.7.1").verdict, "requirements");
  assert.equal(run("iPhone SE (2nd generation)", "26.0.1").verdict, "requirements");
  assert.equal(run("iPad (7th generation)", "18.0").verdict, "requirements"); // A10
});

test("unsupported: A14+ above 17.3.1", () => {
  const r = run("iPhone 12", "17.4");
  assert.equal(r.verdict, "unsupported");
  assert.match(r.reasons[0], /A13 and earlier/);
  assert.equal(run("iPhone 15 Pro", "18.0").verdict, "unsupported");
});

test("unsupported: versions past the published ranges", () => {
  assert.equal(run("iPhone 11", "18.7.2").verdict, "unsupported");
  assert.equal(run("iPhone 11", "26.1").verdict, "unsupported");
  assert.equal(run("iPhone 11", "27.0").verdict, "unsupported");
});

test("unsupported: chips Dopamine does not name (A18, M4)", () => {
  assert.equal(run("iPhone 16", "18.0").verdict, "unsupported");
  assert.equal(run("iPad Pro 11-inch (M4)", "17.5").verdict, "unsupported");
});

test("unsupported: below 15.0", () => {
  assert.equal(run("iPhone 11", "14.8").verdict, "unsupported");
});

test("unverified: impossible model/version pair, unknown version, no model", () => {
  assert.equal(run("iPhone X", "17.0").verdict, "unverified");          // iPhone X stops at 16.x
  assert.equal(run("iPhone 11", "17.3.2").verdict, "unverified");       // no such release
  assert.equal(C.evaluate({ ...base, device: "", version: "16.5" }, DATA).verdict, "unverified");
  assert.equal(C.evaluate({ ...base, device: "nope", version: "16.5" }, DATA).verdict, "unverified");
});

test("unverified: factory firmware on a sideload-only version", () => {
  assert.equal(run("iPhone 15", "17.2", { firmware: "factory" }).verdict, "unverified");
  // factory firmware does not matter on the TrollStore route
  assert.notEqual(run("iPhone 15", "17.0", { firmware: "factory" }).verdict, "unverified");
});

test("existing jailbreaks", () => {
  assert.ok(run("iPhone 12", "15.4.1", { jailbreak: "palera1n-rootful" }).requirements.some((x) => /palera1n/.test(x)));
  assert.ok(run("iPhone 12", "15.4.1", { jailbreak: "other-rootless" }).requirements.some((x) => /nathanlr/.test(x)));
  assert.equal(run("iPhone 12", "15.4.1", { jailbreak: "palera1n-rootless" }).verdict, "supported");
  assert.equal(run("iPhone 12", "15.4.1", { jailbreak: "unsure" }).verdict, "requirements");
});

test("model search by name, chip, identifier and model number", () => {
  assert.ok(C.searchDevices(DATA, "A2161").some((d) => d.name === "iPhone 11 Pro Max"));
  assert.ok(C.searchDevices(DATA, "iPhone12,5").some((d) => d.name === "iPhone 11 Pro Max"));
  assert.ok(C.searchDevices(DATA, "a13").length >= 5);
});

test("cross-check every model x shipped release against AppleDB's own Dopamine list", () => {
  const groups = DATA.appledbDopamine.groups;
  const buildToVersion = {};
  for (const [v, bs] of Object.entries(DATA.builds)) for (const b of bs) buildToVersion[b] = v;
  const listed = new Set();
  for (const g of groups) for (const b of g.builds) {
    const v = buildToVersion[b];
    if (!v) continue; // betas are not in our release list
    for (const id of g.devices) listed.add(id + "|" + v);
  }
  const disagreements = [];
  let checked = 0;
  for (const d of DATA.devices) for (const vi of d.versions) {
    const v = DATA.versions[vi];
    const ours = run(d.name, v.replace(" RC", ""), v.endsWith(" RC") ? { build: "20H18" } : v === "16.7" ? { build: "20H19" } : {});
    const supported = ours.verdict === "supported" || ours.verdict === "requirements";
    const theirs = d.ids.some((id) => listed.has(id + "|" + v));
    checked++;
    if (supported !== theirs) disagreements.push(`${d.name} ${v}: ours=${ours.verdict} appledb=${theirs}`);
  }
  assert.ok(checked > 3000, `checked ${checked} pairs`);
  assert.deepEqual(disagreements, []);
});
