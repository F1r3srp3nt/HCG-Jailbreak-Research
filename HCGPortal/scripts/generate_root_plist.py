#!/usr/bin/env python3
"""Generates preferences/Resources/Root.plist, the HCG Portal Settings layout.

    python3 -I scripts/generate_root_plist.py          # write
    python3 -I scripts/generate_root_plist.py --check  # exit 1 if the file is stale

The keys, defaults and choices here must match src/PortalPreferences.m and
src/PortalCore.c; scripts/validate.sh section 2 checks that they do.
"""
import os
import plistlib
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "preferences", "Resources", "Root.plist")
DOMAIN = "com.hakmicapitalgroup.portal"
NOTE = DOMAIN + "/preferences-changed"


def group(ident, label=None, footer=None):
    d = {"cell": "PSGroupCell", "id": ident}
    if label:
        d["label"] = label
    if footer:
        d["footerText"] = footer
    return d


def pref(cell, key, label, default, **extra):
    d = {"cell": cell, "key": key, "id": key, "label": label, "default": default, "defaults": DOMAIN, "PostNotification": NOTE}
    d.update(extra)
    return d


def button(ident, label, action):
    return {"cell": "PSButtonCell", "id": ident, "label": label, "action": action}


def value(ident, label, getter):
    return {"cell": "PSTitleValueCell", "id": ident, "label": label, "get": getter}


def slider(key, default, lo, hi):
    return pref("PSSliderCell", key, "", default, min=lo, max=hi, showValue=True)


ITEMS = [
    group("generalGroup", "HCG Portal",
          "Off after installation. Changes apply immediately, without a respring. HCG Portal works only on an unlocked "
          "iPhone: it appears on the Cover Sheet when you pull it down after unlocking with Face ID, Touch ID or your "
          "passcode, and never on the locked Lock Screen. Locking removes it at once."),
    pref("PSSwitchCell", "enabled", "Enable HCG Portal", False),
    value("engineStatus", "Status", "engineStatus:"),
    value("visibilityStatus", "On the Cover Sheet", "visibilityStatus:"),
    group("statusDetailGroup"),
    group("placementGroup", "Placement",
          "On the Cover Sheet the portal sits below the clock and widgets and above notifications. It moves, shrinks, collapses to a "
          "small orb or hides when notifications, media controls, the flashlight or the camera need the space."),
    button("openPlacement", "Position & Size", "openPlacement:"),
    group("appearanceGroup", "Appearance"),
    pref("PSLinkListCell", "palette", "Colour", "signature", detail="PSListItemsController",
         validValues=["signature", "aurora", "solar", "mono"],
         validTitles=["HCG Signature (Cyan and Violet)", "Aurora (Teal and Green)", "Solar (Amber and Rose)",
                      "Mono (White and Silver)"]),
    group("brightnessGroup", "Brightness"),
    slider("brightness", 0.85, 0.2, 1.0),
    group("speedGroup", "Animation Speed", "How fast the rings turn. Even the fastest setting is slow by design."),
    slider("speed", 1.0, 0.25, 2.0),
    group("intensityGroup", "Intensity",
          "Glow and particles. Particles stay sparse, and switch off with Reduce Motion or in Low Power Mode."),
    slider("intensity", 0.6, 0.0, 1.0),
    button("resetAppearance", "Reset Appearance", "resetAppearance:"),
    group("behaviourGroup", "Behaviour",
          "The opening animation plays briefly the first time the portal appears after you unlock. With Reduce Motion on, "
          "the portal is static and the opening animation is skipped."),
    pref("PSSwitchCell", "unlockAnimation", "Opening Animation on Unlock", True),
    pref("PSLinkListCell", "lowPower", "In Low Power Mode", "static", detail="PSListItemsController",
         validValues=["static", "economy", "hide"],
         validTitles=["Static (Default)", "Economy: Slow, No Particles", "Hide the Portal"]),
    group("destinationsGroup", "Destinations"),
    button("openApps", "HCG Apps", "openApps:"),
    value("nexusStatus", "Nexus", "nexusStatus:"),
    value("backgroundsStatus", "Backgrounds", "backgroundsStatus:"),
    value("devicesStatus", "Devices", "devicesStatus:"),
    group("recoveryGroup", "Recovery",
          "Turning Enable off removes the portal at once and the Cover Sheet behaves as if HCG Portal were not installed. "
          "If Settings can't be opened: over SSH, touch /var/mobile/Library/Preferences/com.hakmicapitalgroup.portal.disabled "
          "and respring (the kill switch). After three quick SpringBoard crashes in a row HCG Portal turns itself off."),
    button("resetAll", "Reset All HCG Portal Settings", "resetAll:"),
    pref("PSSwitchCell", "diagnosticLogging", "Diagnostic Logging", False),
    group("aboutGroup", "About",
          "Free public beta demo by Hakmi Capital Group. No account, no payment, no network access, no telemetry."),
    value("version", "Version", "versionString:"),
    value("build", "Build", "buildString:"),
    value("system", "iOS", "systemVersion:"),
]


def render():
    return plistlib.dumps({"title": "HCG Portal", "items": ITEMS}, sort_keys=True)


def main():
    data = render()
    if "--check" in sys.argv[1:]:
        try:
            current = open(OUT, "rb").read()
        except OSError:
            current = b""
        if current != data:
            print(f"{OUT} is stale: run scripts/generate_root_plist.py")
            sys.exit(1)
        print("Root.plist up to date")
        return
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "wb").write(data)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
