#!/usr/bin/env python3
"""Writes preferences/Resources/Root.plist (the main Settings page).

    python3 -I scripts/generate_root_plist.py          # write
    python3 -I scripts/generate_root_plist.py --check  # exit 1 if the file is stale

One source for the Settings layout, so validate.sh can check every key,
identifier and choice against the code (src/HACPreferences.m, src/HACPolicy.c).
"""
import os
import plistlib
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "preferences", "Resources", "Root.plist")
DOMAIN = "com.hakmicapitalgroup.animationcenter"
NOTIFY = DOMAIN + "/preferences-changed"


def group(ident, label=None, footer=None):
    d = {"cell": "PSGroupCell", "id": ident}
    if label:
        d["label"] = label
    if footer:
        d["footerText"] = footer
    return d


def switch(key, label, default):
    return {"cell": "PSSwitchCell", "id": key, "key": key, "label": label, "default": default,
            "defaults": DOMAIN, "PostNotification": NOTIFY}


def choice(key, label, values, titles, default, message=None):
    d = {"cell": "PSLinkListCell", "detail": "PSListItemsController", "id": key, "key": key, "label": label,
         "validValues": values, "validTitles": titles, "default": default, "defaults": DOMAIN,
         "PostNotification": NOTIFY}
    if message:
        d["staticTextMessage"] = message
    return d


def value(ident, label, getter):
    return {"cell": "PSTitleValueCell", "id": ident, "label": label, "get": getter}


def button(ident, label, action):
    return {"cell": "PSButtonCell", "id": ident, "label": label, "action": action}


ITEMS = [
    group("general", footer="Off after installation. Your system wallpaper is never changed: when HCG Animation "
                            "Center is off, or a screen has no background, your normal wallpaper shows. Changes apply "
                            "without a respring."),
    switch("enabled", "Enable HCG Animation Center", False),
    value("engineStatus", "Status", "engineStatus:"),
    group("statusDetail"),

    group("homeGroup", "Home Screen", "Plays behind your icons, dock and widgets. Pauses when an app is open, the "
                                      "phone is locked or the screen is off."),
    switch("homeEnabled", "Home Screen Background", True),
    button("chooseHome", "Choose Background…", "chooseHome:"),
    value("homeBackground", "Background", "homeBackground:"),
    value("homeRendering", "Now", "homeRendering:"),

    group("lockGroup", "Lock Screen (Experimental)",
          "Plays while the phone is locked and the screen is on, and stops when you unlock. Where iOS gives it no safe "
          "place, nothing is drawn and your normal Lock Screen shows; Status says why."),
    switch("lockEnabled", "Lock Screen Background", False),
    choice("lockSource", "Use", ["same", "own"], ["Same as Home Screen", "Its Own Background"], "own"),
    button("chooseLock", "Choose Background…", "chooseLock:"),
    value("lockBackground", "Background", "lockBackground:"),
    value("lockRendering", "Now", "lockRendering:"),

    group("libraryGroup", "Library", "Import videos and GIFs from Photos or Files, then trim, scale, loop and "
                                     "preview them before applying."),
    button("openLibrary", "Media Library", "openLibrary:"),

    group("playbackGroup", "Playback", "Backgrounds always play muted. Video stops while the device is hot. "
                                       "Unsupported or damaged media shows its still image, or your normal wallpaper."),
    choice("reduceMotion", "With Reduce Motion", ["still", "play"], ["Show Still Image", "Keep Playing"], "still"),
    choice("lowPower", "In Low Power Mode", ["still", "play", "system"],
           ["Show Still Image", "Keep Playing", "Use System Wallpaper"], "still"),

    group("aiGroup", "AI Backgrounds", "A later phase: HCG AI will generate a preview that you choose to apply. "
                                       "Not connected in this beta."),
    button("openAI", "AI Backgrounds", "openAI:"),

    group("recoveryGroup", "Recovery",
          "Restore System Wallpaper turns HCG Animation Center off at once. If Settings can't be opened: over SSH, "
          "touch /var/mobile/Library/Preferences/com.hakmicapitalgroup.animationcenter.disabled and respring. After "
          "three quick SpringBoard crashes in a row it turns itself off. Uninstalling and respringing always restores "
          "normal wallpaper behaviour."),
    button("restoreSystemWallpaper", "Restore System Wallpaper", "restoreSystemWallpaper:"),

    group("advancedGroup", "Advanced", "Placement decides where the background view goes. Automatic tries the "
                                       "Home Screen window first, and the Lock Screen wallpaper view then the Cover "
                                       "Sheet window. Write Hierarchy Probe saves a read-only description of "
                                       "SpringBoard's windows for device testing."),
    choice("homePlacement", "Home Screen Placement", ["automatic", "homeWindow", "wallpaper"],
           ["Automatic", "Home Screen Window", "Wallpaper View"], "automatic"),
    choice("lockPlacement", "Lock Screen Placement", ["automatic", "wallpaper", "coverSheet"],
           ["Automatic", "Wallpaper View", "Cover Sheet Window"], "automatic"),
    switch("diagnosticLogging", "Diagnostic Logging", False),
    button("writeProbe", "Write Hierarchy Probe", "writeProbe:"),
    value("environment", "Environment", "environmentStatus:"),
    value("version", "Version", "versionString:"),
]

PLIST = {"title": "HCG Animation Center", "items": ITEMS}


def main():
    data = plistlib.dumps(PLIST, fmt=plistlib.FMT_XML, sort_keys=True)
    if "--check" in sys.argv:
        current = open(OUT, "rb").read() if os.path.exists(OUT) else b""
        if current != data:
            print("Root.plist is stale: run scripts/generate_root_plist.py")
            sys.exit(1)
        print("Root.plist up to date")
        return
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "wb").write(data)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
