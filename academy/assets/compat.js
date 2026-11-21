/* HCG Jailbreak Academy: Dopamine compatibility logic.
 *
 * Pure functions, no network, no storage, no device access. Works in the browser (globalThis.HCGCompat) and in Node
 * (tests/compat.test.mjs). Hardware and release facts come from compat-data.js (generated from AppleDB); the
 * supported ranges below are copied by hand from Dopamine's own statements. Every rule names its source.
 *
 * Result verdicts:
 *   "supported"      a documented route exists and nothing else is needed first
 *   "requirements"   supported, but the user must do or confirm specific things first (listed)
 *   "unsupported"    Dopamine's published ranges exclude this chip / version
 *   "unverified"     we cannot match the answers to a known model + shipped release, or no documented route fits
 * Never guess: anything that is not covered by a rule falls through to "unverified".
 */
(function (root) {
  "use strict";

  var LAST_REVIEWED = "2026-11-21";

  var SOURCES = {
    readme: { label: "Dopamine README (3.x branch, release 3.0.13, 3 Nov 2026)", url: "https://github.com/opa334/Dopamine" },
    site: { label: "Official Dopamine website", url: "https://ellekit.space/dopamine/" },
    guideSideload: { label: "ios.cfw.guide: Installing Dopamine", url: "https://ios.cfw.guide/installing-dopamine/" },
    guideTroll: { label: "ios.cfw.guide: Installing Dopamine (TrollStore)", url: "https://ios.cfw.guide/installing-dopamine-trollstore/" },
    trollstore: { label: "TrollStore README (supported versions)", url: "https://github.com/opa334/TrollStore" },
    removePalera1n: { label: "ios.cfw.guide: Removing palera1n", url: "https://ios.cfw.guide/removing-palera1n/" },
    removeNathanlr: { label: "ios.cfw.guide: Removing nathanlr", url: "https://ios.cfw.guide/removing-nathanlr/" },
    removeDopamine: { label: "ios.cfw.guide: Removing Dopamine", url: "https://ios.cfw.guide/removing-dopamine/" },
    getStarted: { label: "ios.cfw.guide: Get Started (other jailbreaks)", url: "https://ios.cfw.guide/get-started/" }
  };

  // Chips Dopamine names. Website: "A jailbreak for arm64 (A8 - A11) and arm64e (A12 - A17, M1 - M2)".
  var CHIPS_ALL = ["A8", "A8X", "A9", "A9X", "A10", "A10X", "A11", "A12", "A12X", "A12Z", "A13",
                   "A14", "A15", "A16", "A17 Pro", "M1", "M2"];
  // README: "iOS 15.0 - 18.7.1, 26.0 - 26.0.1 (A12/A13) and iOS 15.0 - 18.7.1 (arm64)".
  // Website: "Supported on iOS 15.0 - 18.7.1 and 26.0 - 26.0.1 (A8 - A13)". cfw.guide: "A13 and earlier devices".
  var CHIPS_A13_AND_EARLIER = ["A8", "A8X", "A9", "A9X", "A10", "A10X", "A11", "A12", "A12X", "A12Z", "A13"];
  var ARM64E_A12_PLUS = ["A12", "A12X", "A12Z", "A13", "A14", "A15", "A16", "A17 Pro", "M1", "M2"];

  var RANGES = [
    { id: "all", from: "15.0", to: "17.3.1", chips: CHIPS_ALL,
      text: "all supported devices (A8–A17, M1–M2) on iOS/iPadOS 15.0 – 17.3.1", src: "site" },
    { id: "a13-17-18", from: "17.4", to: "18.7.1", chips: CHIPS_A13_AND_EARLIER,
      text: "A13 and earlier on iOS/iPadOS 17.4 – 18.7.1", src: "readme" },
    { id: "a13-26", from: "26.0", to: "26.0.1", chips: CHIPS_A13_AND_EARLIER,
      text: "A13 and earlier on iOS/iPadOS 26.0 – 26.0.1", src: "readme" }
  ];

  // ---------------------------------------------------------------- versions

  function parseVersion(v) {
    var m = /^(\d+)(?:\.(\d+))?(?:\.(\d+))?( RC)?$/.exec(String(v).trim());
    if (!m) return null;
    return { major: +m[1], minor: +(m[2] || 0), patch: +(m[3] || 0), rc: !!m[4] };
  }
  function cmp(a, b) {
    var x = typeof a === "string" ? parseVersion(a) : a, y = typeof b === "string" ? parseVersion(b) : b;
    return (x.major - y.major) || (x.minor - y.minor) || (x.patch - y.patch) || ((x.rc ? 0 : 1) - (y.rc ? 0 : 1));
  }
  function between(v, lo, hi) {
    // RC builds sort just below their release: 16.7 RC is >= 16.6.1 and < 16.7.
    return cmp(v, lo) >= 0 && cmp(v, hi) <= 0;
  }
  function label(p) {
    return p.major + "." + p.minor + (p.patch ? "." + p.patch : "") + (p.rc ? " RC" : "");
  }
  /** Normalise what a person types ("17", "17.0.0", "iOS 16.7", "16.7 (20H18)") into a release label. */
  function normalizeVersion(raw, build) {
    var s = String(raw || "").trim().replace(/^(ios|ipados)\s*/i, "");
    var bm = /\(([0-9A-Za-z]+)\)\s*$/.exec(s);
    if (bm) { build = build || bm[1]; s = s.replace(/\s*\([^)]*\)\s*$/, ""); }
    var p = parseVersion(s);
    if (!p) return null;
    if (p.major === 16 && p.minor === 7 && p.patch === 0 && !p.rc && String(build || "").toUpperCase() === "20H18") p.rc = true;
    return label(p);
  }

  // ---------------------------------------------------------------- TrollStore

  // TrollStore README: "Supported versions: 14.0 beta 2 - 16.6.1, 16.7 RC (20H18), 17.0".
  function trollStoreCanRun(v) {
    return between(v, "15.0", "16.6.1") || v === "16.7 RC" || v === "17.0";
  }

  /** Which TrollStore installer the cfw.guide TrollStore page assigns to this chip + version (its tab titles). */
  function trollStoreMethod(chip, v) {
    var a8 = chip === "A8" || chip === "A8X";
    var a12plus = ARM64E_A12_PLUS.indexOf(chip) !== -1;
    var M = {
      ota: { id: "trollhelperota", name: "TrollHelperOTA", computer: false,
             tab: "TrollHelperOTA (15.0 to 15.4.1 / A12 and later 15.5 to 15.6.1)" },
      tix: { id: "trollinstallerx", name: "TrollInstallerX", computer: "unless-signed",
             tab: "TrollInstallerX (16.0 to 16.6.1 / A9(X) and later 15.7 to 15.8.6 / A9(X) to A11 15.5 to 15.6.1)" },
      restore: { id: "trollrestore", name: "TrollRestore", computer: true, findMy: true,
                 tab: "TrollRestore (15.8.7 to 15.8.8 / 16.7 RC (20H18) / 17.0 / A8(X) 15.7.2 to 15.8.6)" },
      mdc: { id: "trollinstallermdc", name: "TrollInstallerMDC", computer: true,
             tab: "TrollInstallerMDC (A8(X) 15.5 to 15.7.1)" }
    };
    if (between(v, "15.0", "15.4.1")) return M.ota;
    if (between(v, "15.5", "15.6.1")) return a12plus ? M.ota : (a8 ? M.mdc : M.tix);
    if (between(v, "15.7", "15.7.1")) return a8 ? M.mdc : M.tix;
    if (between(v, "15.7.2", "15.8.6")) return a8 ? M.restore : M.tix;
    if (between(v, "15.8.7", "15.8.8")) return M.restore;
    if (between(v, "16.0", "16.6.1")) {
      var extra = (a12plus && between(v, "16.6", "16.6.1")) ||
                  ((chip === "A15" || chip === "A16" || chip === "M2") && v === "16.5.1");
      return Object.assign({}, M.tix, { additionalSteps: extra });
    }
    if (v === "16.7 RC" || v === "17.0") return M.restore;
    return null;
  }

  // ---------------------------------------------------------------- main

  function findDevice(data, key) {
    for (var i = 0; i < data.devices.length; i++) if (data.devices[i].key === key) return data.devices[i];
    return null;
  }

  /**
   * @param {object} input  { device, version, build, jailbreak, trollstore, backup, firmware }
   *   jailbreak:  none | dopamine | palera1n-rootless | palera1n-rootful | other-rootless | older | unsure
   *   trollstore: yes | no | unsure
   *   backup:     yes | no
   *   firmware:   updated | factory | unsure   (has the device ever installed an iOS update?)
   * @param {object} data   window.HCG_COMPAT_DATA
   */
  function evaluate(input, data) {
    var r = { verdict: "unverified", title: "", reasons: [], requirements: [], notes: [], route: null,
              trollstoreMethod: null, sources: [], facts: {}, lastReviewed: LAST_REVIEWED };
    function src(k) { if (r.sources.indexOf(SOURCES[k]) === -1) r.sources.push(SOURCES[k]); }
    function done(verdict, title) { r.verdict = verdict; r.title = title; return r; }

    var dev = input.device ? findDevice(data, input.device) : null;
    if (!dev) {
      r.reasons.push("Choose your exact model from the list. If it is not listed, we cannot verify it.");
      return done("unverified", "Compatibility cannot yet be verified");
    }
    r.facts.device = dev.name; r.facts.chip = dev.soc; r.facts.arch = dev.arch;

    var v = normalizeVersion(input.version, input.build);
    if (!v) {
      r.reasons.push("Enter the version exactly as shown in Settings › General › About › iOS Version (for example 16.6.1).");
      return done("unverified", "Compatibility cannot yet be verified");
    }
    r.facts.version = v;
    var pv = parseVersion(v);

    if (pv.major < 15) {
      r.reasons.push("Dopamine starts at iOS/iPadOS 15.0. Your version " + v + " is older.");
      r.notes.push("Other jailbreaks cover older versions; this guide does not. See the ios.cfw.guide Get Started page.");
      src("readme"); src("getStarted");
      return done("unsupported", "Unsupported by Dopamine");
    }
    if (v === "16.7" && !input.build) {
      r.reasons.push("For 16.7 the build number decides the route: 16.7 RC (20H18) can use TrollStore, 16.7 (20H19) cannot. " +
                     "Tap iOS Version in Settings › General › About to see the build in parentheses, then choose it.");
      r.needsBuild = true;
      return done("unverified", "Compatibility cannot yet be verified");
    }

    var vi = data.versions.indexOf(v);
    if (vi === -1) {
      r.reasons.push("“" + v + "” is not a shipped iOS/iPadOS release in our dataset. Betas and mistyped versions cannot be verified. " +
                     "Re-check Settings › General › About.");
      return done("unverified", "Compatibility cannot yet be verified");
    }
    if (dev.versions.indexOf(vi) === -1) {
      r.reasons.push("Apple never released " + v + " for the " + dev.name + " (AppleDB). Re-check the model and the version; one of them is probably different.");
      return done("unverified", "Compatibility cannot yet be verified");
    }

    // Published ranges.
    if (CHIPS_ALL.indexOf(dev.soc) === -1) {
      r.reasons.push("Dopamine supports A8–A17 and M1–M2 chips. The " + dev.name + " has the " + dev.soc + " chip, which is not supported on any version.");
      src("site"); src("readme");
      return done("unsupported", "Unsupported by Dopamine");
    }
    var match = null;
    for (var i = 0; i < RANGES.length; i++) {
      if (between(v, RANGES[i].from, RANGES[i].to) && RANGES[i].chips.indexOf(dev.soc) !== -1) { match = RANGES[i]; break; }
    }
    if (!match) {
      if (CHIPS_A13_AND_EARLIER.indexOf(dev.soc) === -1 && (between(v, "17.4", "18.7.1") || between(v, "26.0", "26.0.1"))) {
        r.reasons.push("On " + v + " Dopamine supports only A13 and earlier chips. The " + dev.soc + " is supported up to 17.3.1.");
      } else {
        r.reasons.push("Dopamine's published ranges do not include " + v + " for the " + dev.soc + " chip. " +
                       "Supported: 15.0 – 17.3.1 (A8–A17, M1–M2); 17.4 – 18.7.1 and 26.0 – 26.0.1 (A13 and earlier).");
      }
      r.notes.push("Do not update in the hope of support: newer versions are not supported, and Apple does not let you return to an older version once it stops signing it.");
      src("readme"); src("site");
      return done("unsupported", "Unsupported by Dopamine");
    }
    r.reasons.push("Dopamine supports " + match.text + ".");
    src(match.src);

    // Installation route (cfw.guide). TrollStore route for versions where TrollStore can run; sideloading otherwise.
    var trollOK = trollStoreCanRun(v);
    if (trollOK) {
      r.route = { id: "trollstore", name: "Install with TrollStore", source: SOURCES.guideTroll };
      src("guideTroll"); src("trollstore");
      if (input.trollstore === "yes") {
        r.notes.push("TrollStore is already installed, so you can skip “Installing TrollStore”; no computer is needed for the rest.");
      } else {
        var m = trollStoreMethod(dev.soc, v);
        if (!m) { r.reasons.push("No documented TrollStore installer matches this version."); return done("unverified", "Compatibility cannot yet be verified"); }
        r.trollstoreMethod = m;
        if (input.trollstore === "unsure") r.requirements.push("Check whether TrollStore is installed (look for the TrollStore app). If it is, you can skip installing it.");
        if (m.computer === true) r.requirements.push("A computer (Windows, macOS or Linux) to install TrollStore with " + m.name + ".");
        if (m.computer === "unless-signed") r.requirements.push("A computer to sideload " + m.name + ", unless jailbreaks.app currently signs it.");
        if (m.findMy) r.requirements.push("Turn off Find My before TrollRestore (it restores a modified backup). You can turn it back on afterwards.");
        if (m.additionalSteps) r.requirements.push("After TrollInstallerX, finish installing TrollStore from the persistence helper app (the guide's “Additional Steps”).");
      }
    } else {
      r.route = { id: "sideload", name: "Install by sideloading (no TrollStore)", source: SOURCES.guideSideload };
      src("guideSideload");
      if (input.trollstore === "yes") {
        r.notes.push("TrollStore's README says it cannot run on " + v + " (only up to 16.6.1, 16.7 RC and 17.0). Check that what you have is really TrollStore; this route does not need it.");
      }
      r.requirements.push("A computer and an Apple Account to sideload the Dopamine .ipa (PlumeImpactor), unless jailbreaks.app currently signs Dopamine.");
      r.requirements.push("Re-sign the Dopamine app every 7 days (iOS/iPadOS 16.7 and later, except 17.0).");
      if (pv.major >= 16) r.requirements.push("Turn on Developer Mode (Settings › Privacy & Security) if you did not install through jailbreaks.app.");
      if (input.firmware === "factory") {
        r.reasons.push("The sideloading guide does not work on the iOS version a device shipped with, and TrollStore cannot run on " + v + ". No documented route fits.");
        return done("unverified", "Compatibility cannot yet be verified");
      }
      if (input.firmware === "unsure") {
        r.requirements.push("Confirm the device has installed at least one iOS update since it was new: the sideloading guide does not work on the factory version.");
      }
    }

    // Existing jailbreak.
    switch (input.jailbreak) {
      case "palera1n-rootful":
        r.requirements.push("Remove rootful palera1n first (ios.cfw.guide: Removing palera1n)."); src("removePalera1n"); break;
      case "other-rootless":
        r.requirements.push("Fully remove nathanlr, Relaxin, Serotonin or Bootstrap first."); src("removeNathanlr"); break;
      case "palera1n-rootless":
        r.notes.push("ios.cfw.guide says Dopamine and rootless palera1n are intercompatible and can both be used."); src("removeDopamine"); break;
      case "dopamine":
        r.notes.push("Dopamine is already installed. After a reboot, open the Dopamine app and tap Jailbreak again; update from inside the app when it offers an update."); break;
      case "older":
        r.requirements.push("Identify the earlier jailbreak and follow its removal guide before installing Dopamine."); break;
      case "unsure":
        r.requirements.push("Find out whether a jailbreak is installed (look for Sileo, Zebra, Cydia, TrollStore or a jailbreak app on the Home Screen)."); break;
      default: break;
    }

    if (input.backup !== "yes") r.requirements.unshift("Make a full backup (iCloud, or encrypted Finder/iTunes) before you start.");

    // Device notes from the official guides.
    if ((dev.soc === "A12" || dev.soc === "A12X" || dev.soc === "A12Z" || dev.soc === "A13") && cmp(v, "16.6") >= 0) {
      r.notes.push("On A12/A13 devices on 16.6 or later the screen briefly turns off and on during the jailbreak. That is expected.");
    }
    if (between(v, "15.8.7", "15.8.8") || cmp(v, "16.7") >= 0) {
      r.notes.push("Some 2 GB RAM devices on this version need a one-time respring workaround first; the Dopamine app tells you (“Apply Workaround”).");
    }

    return r.requirements.length
      ? done("requirements", "Supported with specific requirements")
      : done("supported", "Supported");
  }

  /** Model search: name, chip, identifier (iPhone12,5) or model number (A2161). */
  function searchDevices(data, q) {
    q = String(q || "").trim().toLowerCase();
    if (!q) return data.devices.slice();
    return data.devices.filter(function (d) {
      return d.name.toLowerCase().indexOf(q) !== -1 || String(d.soc).toLowerCase() === q ||
        d.ids.some(function (x) { return x.toLowerCase() === q; }) ||
        d.models.some(function (x) { return x.toLowerCase() === q; });
    });
  }

  root.HCGCompat = {
    evaluate: evaluate, normalizeVersion: normalizeVersion, parseVersion: parseVersion, compare: cmp,
    trollStoreCanRun: trollStoreCanRun, trollStoreMethod: trollStoreMethod, searchDevices: searchDevices,
    RANGES: RANGES, CHIPS_ALL: CHIPS_ALL, CHIPS_A13_AND_EARLIER: CHIPS_A13_AND_EARLIER, SOURCES: SOURCES,
    LAST_REVIEWED: LAST_REVIEWED
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
