#!/usr/bin/env python3
"""Regenerates preferences/Resources/Root.plist (HCG Vortex Settings layout).

Values here must match +[VortexPreferences validPresets / validEffectIdentifiers /
validDirections / validEasings]; scripts/validate.sh cross-checks them.
Usage: python3 scripts/generate_root_plist.py
"""
import os
import plistlib

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
D = "com.hakmicapitalgroup.vortex"
N = "com.hakmicapitalgroup.vortex/preferences-changed"


def group(label=None, footer=None, **kw):
    d = {"cell": "PSGroupCell"}
    if label:
        d["label"] = label
    if footer:
        d["footerText"] = footer
    d.update(kw)
    return d


def pref(cell, key, label, **kw):
    d = {"cell": cell, "key": key, "label": label, "defaults": D, "PostNotification": N, "id": key}
    d.update(kw)
    return d


def lst(key, label, pairs):
    return pref("PSLinkListCell", key, label, detail="PSListItemsController",
                validTitles=[t for t, _ in pairs], validValues=[v for _, v in pairs])


def slider(key, mn, mx):
    return pref("PSSliderCell", key, "", min=mn, max=mx, showValue=True)


def info(label, getter, ident):
    return {"cell": "PSTitleValueCell", "label": label, "get": getter, "id": ident}


EFFECTS = [("Reverse Slide", "reverse-slide"), ("Vertical Rise", "vertical-rise"),
           ("Vertical Fall", "vertical-fall"), ("Custom Directions", "custom"), ("iOS Default", "stock")]
PRESETS = EFFECTS[:4] + [("Per-Swipe Effects", "per-direction")] + EFFECTS[4:]
DIRECTIONS = [("Left", "left"), ("Right", "right"), ("Top", "up"), ("Bottom", "down"),
              ("Top Left", "up-left"), ("Top Right", "up-right"), ("Bottom Left", "down-left"),
              ("Bottom Right", "down-right")]
EASINGS = [("Linear", "linear"), ("Ease In", "ease-in"), ("Ease Out", "ease-out"),
           ("Ease In-Out", "ease-in-out"), ("Sine", "sine")]

ITEMS = [
    group("General", "The preset applies to both swipe directions. Choose “Per-Swipe Effects” to set each "
          "direction separately below. “Restore Default Behavior” switches to the stock iOS animation "
          "without touching your other settings."),
    pref("PSSwitchCell", "enabled", "Enable Vortex"),
    lst("preset", "Animation Preset", PRESETS),
    {"cell": "PSButtonCell", "label": "Restore Default Behavior", "action": "restoreDefaultBehavior:",
     "id": "restoreDefault"},
    group("Directional Controls", "Swipe effects are used with the “Per-Swipe Effects” preset. The two "
          "direction controls define the “Custom Directions” effect: where the incoming page enters from "
          "and where the outgoing page exits to. Your actual page navigation is never changed — only how it "
          "looks."),
    lst("swipeLeftEffect", "Swipe Left Effect", EFFECTS),
    lst("swipeRightEffect", "Swipe Right Effect", EFFECTS),
    lst("incomingDirection", "Incoming Page From", DIRECTIONS),
    lst("outgoingDirection", "Outgoing Page To", DIRECTIONS),
    pref("PSSwitchCell", "reverseAnimation", "Reverse Animation"),
    group("Duration", "0 = visuals track your finger exactly. Higher values let the visual transition trail the "
          "gesture and glide to completion over the chosen time (seconds)."),
    slider("duration", 0.0, 1.0),
    group("Speed Multiplier", "Above 1.0 the visual transition completes earlier in the swipe; below 1.0 it holds "
          "back. Start and end positions are always exact."),
    slider("speed", 0.25, 4.0),
    group("Animation Intensity", "How far the outgoing page travels. Below 1.0 it moves less and fades out "
          "(parallax) while the incoming page covers it."),
    slider("intensity", 0.1, 1.0),
    group("Animation"),
    lst("easing", "Easing Mode", EASINGS),
    pref("PSSwitchCell", "fadePages", "Fade Pages"),
    group("Development", "Engine status is reported by SpringBoard after each respring. HCG Vortex makes no network "
          "connections and collects no analytics or telemetry."),
    info("Version", "versionString:", "version"),
    info("Engine Status", "engineStatus:", "engineStatus"),
    info("Engine Detail", "engineDetail:", "engineDetail"),
    info("This Device", "systemVersion:", "systemVersion"),
    info("Test Target", "compatibilityTarget:", "compatibilityTarget"),
    pref("PSSwitchCell", "diagnosticLogging", "Diagnostic Logging"),
    {"cell": "PSButtonCell", "label": "Reset Preferences", "action": "resetPreferences:", "id": "resetPreferences",
     "isDestructive": True},
    group(None, "© 2026 Hakmi Capital Group · HCG Vortex is free software distributed through the HCG Repo."),
]

if __name__ == "__main__":
    out = os.path.join(ROOT, "preferences", "Resources", "Root.plist")
    with open(out, "wb") as f:
        plistlib.dump({"title": "HCG Vortex", "items": ITEMS}, f)
    print(f"wrote {out} ({len(ITEMS)} specifiers)")
