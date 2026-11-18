#!/usr/bin/env python3
"""Regenerates preferences/Resources/Root.plist and the effect panes (HCG Vortex Settings layout).

Values here must match +[VortexPreferences validPresets / validEffectIdentifiers /
validDirections / validEasings]; scripts/validate.sh cross-checks them.
Each pane is PANES[name] -> preferences/Resources/<name>.plist, opened by VortexEffectPaneController.
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
           ("Vertical Fall", "vertical-fall"), ("Tornado", "tornado"), ("Orbital", "orbital"), ("Warp", "warp"),
           ("Holographic Layers", "holographic"), ("Circuit Flow", "circuit-flow"), ("Magnetic Grid", "magnetic"),
           ("Custom Directions", "custom"), ("iOS Default", "stock")]
PRESETS = EFFECTS[:-1] + [("Per-Swipe Effects", "per-direction")] + EFFECTS[-1:]
SPIN = [("Follow Swipe", "follow-swipe"), ("Clockwise", "clockwise"), ("Counterclockwise", "counterclockwise")]
TRAVEL = [("Follow Swipe", "follow-swipe"), ("Against Swipe", "against-swipe"), ("Stay Centred", "centred")]
TORNADO_PRESETS = [("Subtle", "subtle"), ("Classic Tornado", "classic"), ("Sci-Fi Vortex", "scifi"), ("Custom", "custom")]
ACCENTS = [("Cyan", "cyan"), ("Purple", "purple"), ("Green", "green"), ("Amber", "amber"), ("Magenta", "magenta"),
           ("White", "white")]
DIRECTIONS = [("Left", "left"), ("Right", "right"), ("Top", "up"), ("Bottom", "down"),
              ("Top Left", "up-left"), ("Top Right", "up-right"), ("Bottom Left", "down-left"),
              ("Bottom Right", "down-right")]
EASINGS = [("Linear", "linear"), ("Ease In", "ease-in"), ("Ease Out", "ease-out"),
           ("Ease In-Out", "ease-in-out"), ("Sine", "sine")]


def stepped(key, mn, mx):
    """Integer slider (rings, layers)."""
    return pref("PSSliderCell", key, "", min=mn, max=mx, showValue=True, isSegmented=True, segmentCount=mx - mn)


def link(label, pane, ident):
    return {"cell": "PSLinkCell", "label": label, "detail": "VortexEffectPaneController", "isController": True,
            "pane": pane, "id": ident}


def preview(effect):
    return {"cell": "PSDefaultCell", "cellClass": "VortexEffectPreviewCell", "height": 300, "effect": effect,
            "id": f"{effect}Preview"}


def labelled(title, footer, item):
    return [group(title, footer), item]


RESET = [group(None, "Returns only this page's settings to their defaults."),
         {"cell": "PSButtonCell", "label": "Reset to Defaults", "action": "resetPane:", "id": "resetPane"}]
UNTESTED = " Implemented and build-validated; not yet tested on a device."

PANES = {
    "Tornado": [
        group("Tornado", "During a page swipe the icons lift out of the grid into a 3-D tornado: a narrow tip, a wide "
              "opening and several spiral turns. The funnel travels with your finger; the next page's icons unwind "
              "into place. Pause holds it, reversing unwinds it, letting go restores the page. Widgets fade in place. "
              "Choose Tornado as the Animation Preset or for one swipe direction." + UNTESTED),
        preview("tornado"),
        group("Preset", "Choosing a preset sets the controls below. Changing any control switches to Custom."),
        lst("tornadoPreset", "Preset", TORNADO_PRESETS),
        *labelled("Funnel Height", "Fraction of the screen height.", slider("tornadoHeight", 0.35, 0.85)),
        *labelled("Upper Radius", "The wide opening, as a fraction of the screen width.", slider("tornadoRadius", 0.15, 0.6)),
        *labelled("Lower Radius", "The narrow tip. Always smaller than the opening.", slider("tornadoTipRadius", 0.02, 0.25)),
        *labelled("Spiral Turns", "How many times the funnel winds from opening to tip.", slider("tornadoRotations", 1.0, 4.0)),
        *labelled("Intensity", "How fast the funnel turns as you swipe and how far icons climb.",
                  slider("tornadoIntensity", 0.1, 1.0)),
        *labelled("Depth & Perspective", "0 = flat. Higher values add perspective scaling, front/back ordering and "
                  "a dimmer back side.", slider("tornadoDepth", 0.0, 1.0)),
        group("Motion", "Spin Icons rotates each icon about its own centre; off keeps icon faces readable."),
        lst("tornadoDirection", "Rotation Direction", SPIN),
        lst("tornadoTravel", "Travel", TRAVEL),
        pref("PSSwitchCell", "tornadoIconSpin", "Spin Icons"),
        *RESET,
    ],
    "Orbital": [
        group("Orbital", "Icons move onto concentric orbital rings around a shared centre, travel around it (inner "
              "rings faster) and resolve into the next page's grid. Rings, not a funnel." + UNTESTED),
        preview("orbital"),
        *labelled("Outer Radius", "Fraction of the screen width.", slider("orbitalRadius", 0.2, 0.48)),
        *labelled("Rings", "2 to 5 concentric rings.", stepped("orbitalRings", 2, 5)),
        *labelled("Ring Tilt", "0 = flat circles. Higher values tilt the rings for a subtle sense of depth.",
                  slider("orbitalTilt", 0.0, 1.0)),
        *labelled("Orbit Speed", "Turns of the outer ring over a full swipe.", slider("orbitalSpeed", 0.25, 2.0)),
        group("Motion"),
        lst("orbitalDirection", "Direction", SPIN),
        *RESET,
    ],
    "Warp": [
        group("Warp", "Icons recede towards a vanishing point, pass through a short tunnel and expand into the "
              "destination grid. No flashing and no blur: opacity and size change smoothly." + UNTESTED),
        preview("warp"),
        *labelled("Intensity", "How deep the icons travel into the tunnel.", slider("warpIntensity", 0.1, 1.0)),
        *labelled("Perspective", "Strength of the perspective.", slider("warpPerspective", 0.2, 1.0)),
        *RESET,
    ],
    "Holographic": [
        group("Holographic Layers", "Icons separate into floating depth layers that slide at different speeds "
              "(parallax) and tilt during the swipe. Icons and labels return exactly to their original look." + UNTESTED),
        preview("holographic"),
        *labelled("Depth", "Separation between layers.", slider("holoDepth", 0.0, 1.0)),
        *labelled("Tilt", "3-D tilt of the icons while they move.", slider("holoTilt", 0.0, 1.0)),
        *labelled("Layers", "2 to 4 depth layers.", stepped("holoLayers", 2, 4)),
        *RESET,
    ],
    "CircuitFlow": [
        group("Circuit Flow", "Icons run along right-angle circuit traces and leave a brief illuminated trail. "
              "Trails are drawn as a few shape layers per page (no blur or shadows). Colour and glow are set in "
              "Appearance. Standalone effect: it is not combined with other effects." + UNTESTED),
        preview("circuit-flow"),
        *labelled("Trail Length", "Fraction of the screen width.", slider("circuitTrail", 0.1, 0.6)),
        *labelled("Trace Intensity", "Brightness of the traces.", slider("circuitIntensity", 0.1, 1.0)),
        *RESET,
    ],
    "Magnetic": [
        group("Magnetic Grid", "The subtle everyday option. Pages move as in iOS; icons gently loosen from the grid "
              "and lock into their exact positions with one small magnetic snap as the page arrives. Nothing keeps "
              "moving after the page is ready." + UNTESTED),
        preview("magnetic"),
        *labelled("Separation", "How far icons drift apart (at most about 14 pt).", slider("magneticStrength", 0.1, 1.0)),
        *labelled("Snap", "The single overshoot as icons lock in (at most about 3 pt). 0 = none.",
                  slider("magneticSnap", 0.0, 1.0)),
        *RESET,
    ],
    "Appearance": [
        group("Appearance", "Colour and glow of Circuit Flow traces and the effect previews. A shared appearance "
              "with HCG Halo and HCG Nexus is planned but not implemented: these settings affect HCG Vortex only."),
        lst("accentColor", "Accent Colour", ACCENTS),
        *labelled("Glow Intensity", "0 = thin traces only.", slider("glowIntensity", 0.0, 1.0)),
        *RESET,
    ],
    "Accessibility": [
        group("Reduce Motion", "While Settings › Accessibility › Motion › Reduce Motion is on, every icon effect "
              "(Tornado, Orbital, Warp, Holographic Layers, Circuit Flow, Magnetic Grid) uses the stock iOS "
              "animation. Page effects are unchanged."),
        info("Reduce Motion", "reduceMotionStatus:", "reduceMotionStatus"),
        group("Performance", "Icon effects update a few layer properties per icon per frame and allocate no images. "
              "Frame rate and battery impact have NOT been measured on a device yet. If a page stutters, choose "
              "Magnetic Grid or a page effect."),
        group("Safety", "Enable Vortex (main page) turns everything off immediately. If SpringBoard keeps "
              "crashing, Vortex disables itself after 3 quick crashes, or create the kill-switch file described in "
              "the package's Removal notes and respring."),
    ],
}

ITEMS = [
    group("General", "The preset applies to both swipe directions. Choose “Per-Swipe Effects” to set each "
          "direction separately below. “Restore Default Behavior” switches to the stock iOS animation "
          "without touching your other settings."),
    pref("PSSwitchCell", "enabled", "Enable Vortex"),
    lst("preset", "Animation Preset", PRESETS),
    {"cell": "PSButtonCell", "label": "Restore Default Behavior", "action": "restoreDefaultBehavior:",
     "id": "restoreDefault"},
    group("Effects", "Each effect has its own page with a live preview, controls and Reset to Defaults. "
          "Tornado: icons form a travelling 3-D funnel. Orbital: icons circle on concentric rings. Warp: icons "
          "pass through a tunnel. Holographic Layers: floating parallax layers. Circuit Flow: icons run along "
          "glowing circuit traces. Magnetic Grid: subtle loosen-and-snap. All six are implemented and "
          "build-validated; none has been tested on a device yet."),
    link("Tornado", "Tornado", "paneTornado"),
    link("Orbital", "Orbital", "paneOrbital"),
    link("Warp", "Warp", "paneWarp"),
    link("Holographic Layers", "Holographic", "paneHolographic"),
    link("Circuit Flow", "CircuitFlow", "paneCircuitFlow"),
    link("Magnetic Grid", "Magnetic", "paneMagnetic"),
    group("Directional Controls", "Swipe effects are used with the “Per-Swipe Effects” preset. The two "
          "direction controls define the “Custom Directions” effect: where the incoming page enters from "
          "and where the outgoing page exits to. Your actual page navigation is never changed — only how it "
          "looks."),
    lst("swipeLeftEffect", "Swipe Left Effect", EFFECTS),
    lst("swipeRightEffect", "Swipe Right Effect", EFFECTS),
    lst("incomingDirection", "Incoming Page From", DIRECTIONS),
    lst("outgoingDirection", "Outgoing Page To", DIRECTIONS),
    pref("PSSwitchCell", "reverseAnimation", "Reverse Animation"),
    group("Appearance & Accessibility"),
    link("Appearance", "Appearance", "paneAppearance"),
    link("Accessibility & Performance", "Accessibility", "paneAccessibility"),
    group("Duration", "0 = visuals track your finger exactly. Higher values let the visual transition trail the "
          "gesture and glide to completion over the chosen time (seconds)."),
    slider("duration", 0.0, 1.0),
    group("Speed Multiplier", "Above 1.0 the visual transition completes earlier in the swipe; below 1.0 it holds "
          "back. Start and end positions are always exact."),
    slider("speed", 0.25, 4.0),
    group("Animation Intensity", "Page effects: how far the outgoing page travels. Below 1.0 it moves less and "
          "fades out (parallax) while the incoming page covers it."),
    slider("intensity", 0.1, 1.0),
    group("Animation"),
    lst("easing", "Easing Mode", EASINGS),
    pref("PSSwitchCell", "fadePages", "Fade Pages"),
    group("Reset & Diagnostics", "Engine status is reported by SpringBoard after each respring. HCG Vortex makes no "
          "network connections and collects no analytics or telemetry."),
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
    res = os.path.join(ROOT, "preferences", "Resources")
    with open(os.path.join(res, "Root.plist"), "wb") as f:
        plistlib.dump({"title": "HCG Vortex", "items": ITEMS}, f)
    for name, items in PANES.items():
        with open(os.path.join(res, f"{name}.plist"), "wb") as f:
            plistlib.dump({"title": name, "items": items}, f)
    print(f"wrote Root.plist ({len(ITEMS)} specifiers) and {len(PANES)} panes")
