#!/usr/bin/env python3
"""Generate the original SVG illustrations used by the HCG Jailbreak Academy guide.

These are schematic drawings made for HCG, NOT screenshots of Dopamine, TrollStore, Sileo or iOS. On-screen wording
is taken from Dopamine 3.0.13's English strings (Application/Dopamine/en.lproj/Localizable.strings) and from the
ios.cfw.guide steps; layout and styling are invented. Each phone carries an "Illustration" label.

Run: python3 tools/make_illustrations.py   (writes academy/assets/img/*.svg)
"""
from __future__ import annotations

from pathlib import Path
from xml.sax.saxutils import escape as x

OUT = Path(__file__).resolve().parent.parent / "academy" / "assets" / "img"
FONT = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif"
BG, SCREEN, ROW, LINE, TEXT, MUTED, CYAN, OK, WARN, RED = (
    "#0a1116", "#10181e", "#18232b", "#2a3a45", "#e6edf1", "#9aa9b2", "#2fd3e6", "#4fcf91", "#e7b866", "#ff8a80")
W, H = 240, 480


def svg(w: int, h: int, body: str, title: str, desc: str) -> str:
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" role="img" '
            f'aria-labelledby="t d" font-family="{FONT}">\n<title id="t">{x(title)}</title>\n<desc id="d">{x(desc)}</desc>\n'
            f'<rect width="{w}" height="{h}" fill="{BG}"/>\n{body}\n</svg>\n')


def text(xp, yp, s, size=12, fill=TEXT, weight=400, anchor="start"):
    return f'<text x="{xp}" y="{yp}" font-size="{size}" fill="{fill}" font-weight="{weight}" text-anchor="{anchor}">{x(s)}</text>'


def phone(content: str, header: str, back: str = "") -> str:
    """A generic phone frame (not an Apple device drawing) with a title bar."""
    b = [f'<rect x="8" y="8" width="{W-16}" height="{H-16}" rx="30" fill="#05080b" stroke="{LINE}" stroke-width="2"/>',
         f'<rect x="16" y="16" width="{W-32}" height="{H-32}" rx="24" fill="{SCREEN}"/>',
         f'<rect x="{W/2-34}" y="22" width="68" height="16" rx="8" fill="#05080b"/>',
         text(W / 2, 64, header, 14, TEXT, 700, "middle")]
    if back:
        b.append(text(28, 64, "‹ " + back, 11, CYAN))
    b.append(f'<line x1="16" y1="76" x2="{W-16}" y2="76" stroke="{LINE}"/>')
    b.append(content)
    b.append(f'<rect x="{W/2-44}" y="{H-50}" width="88" height="18" rx="2" fill="none" stroke="{MUTED}" stroke-dasharray="3 2"/>')
    b.append(text(W / 2, H - 37, "ILLUSTRATION", 9, MUTED, 600, "middle"))
    return "\n".join(b)


def row(y, label, right="", hl=False, sub="", color=TEXT):
    stroke = f' stroke="{CYAN}" stroke-width="2"' if hl else ""
    h = 40 if sub else 34
    s = [f'<rect x="26" y="{y}" width="{W-52}" height="{h}" rx="6" fill="{ROW}"{stroke}/>', text(36, y + 21, label, 12, color)]
    if sub:
        s[-1] = text(36, y + 17, label, 12, color)
        s.append(text(36, y + 31, sub, 9.5, MUTED))
    if right:
        s.append(text(W - 36, y + (21 if not sub else 24), right, 11, CYAN if hl else MUTED, 600, "end"))
    return "\n".join(s)


def toggle(y, label, on=True, hl=False):
    stroke = f' stroke="{CYAN}" stroke-width="2"' if hl else ""
    knob = W - 48 if on else W - 64
    return "\n".join([f'<rect x="26" y="{y}" width="{W-52}" height="34" rx="6" fill="{ROW}"{stroke}/>',
                      text(36, y + 21, label, 11.5),
                      f'<rect x="{W-76}" y="{y+9}" width="38" height="17" rx="8.5" fill="{OK if on else LINE}"/>',
                      f'<circle cx="{knob+6}" cy="{y+17.5}" r="7" fill="#fff"/>'])


def button(y, label, hl=True, fill=CYAN, fg="#031015"):
    ring = f'<rect x="30" y="{y-4}" width="{W-60}" height="48" rx="12" fill="none" stroke="{CYAN}" stroke-width="2" stroke-dasharray="4 3"/>' if hl else ""
    return "\n".join([ring, f'<rect x="36" y="{y}" width="{W-72}" height="40" rx="9" fill="{fill}"/>',
                      text(W / 2, y + 25, label, 14, fg, 700, "middle")])


def tap(xp, yp):
    return (f'<circle cx="{xp}" cy="{yp}" r="13" fill="none" stroke="{CYAN}" stroke-width="2"/>'
            f'<circle cx="{xp}" cy="{yp}" r="4" fill="{CYAN}"/>')


PHONES = {
    # ---- TrollStore route
    "ts-plus": ("TrollStore Apps tab with the plus button", "Open TrollStore and tap the plus button at the top right of the Apps tab.",
                phone("\n".join([
                    text(W - 34, 64, "+", 22, CYAN, 700, "end"), tap(W - 40, 58),
                    row(92, "TrollStore", "Installed"), row(132, "TrollHelper", "Persistence"),
                    text(W / 2, 210, "Apps installed with TrollStore", 10, MUTED, 400, "middle"),
                    text(W / 2, 224, "appear in this list.", 10, MUTED, 400, "middle"),
                    f'<line x1="16" y1="{H-80}" x2="{W-16}" y2="{H-80}" stroke="{LINE}"/>',
                    text(W * 0.3, H - 62, "Apps", 11, CYAN, 600, "middle"), text(W * 0.7, H - 62, "Settings", 11, MUTED, 400, "middle")]),
                    "Apps")),
    "ts-file": ("File picker with Dopamine.ipa selected", "In the file picker, open the folder where you saved the Dopamine .ipa and tap the file.",
                phone("\n".join([
                    text(30, 98, "Downloads", 12, MUTED, 600),
                    row(108, "Dopamine.ipa", "", True, "from github.com/opa334/Dopamine"), tap(W - 52, 128),
                    row(156, "Other file.pdf", "", False, ""),
                    text(W / 2, 236, "Use the official .ipa only:", 10, MUTED, 400, "middle"),
                    text(W / 2, 250, "ellekit.space/dopamine", 10, CYAN, 600, "middle")]), "Choose a file", "Back")),
    "ts-install": ("TrollStore install prompt for Dopamine", "TrollStore asks for confirmation. Tap Install.",
                   phone("\n".join([
                       f'<rect x="36" y="140" width="{W-72}" height="150" rx="14" fill="{ROW}" stroke="{LINE}"/>',
                       text(W / 2, 172, "Dopamine", 15, TEXT, 700, "middle"), text(W / 2, 192, "Install this app?", 11, MUTED, 400, "middle"),
                       f'<line x1="36" y1="214" x2="{W-36}" y2="214" stroke="{LINE}"/>',
                       text(W / 2, 240, "Install", 14, CYAN, 700, "middle"), tap(W / 2 + 36, 236),
                       f'<line x1="36" y1="256" x2="{W-36}" y2="256" stroke="{LINE}"/>',
                       text(W / 2, 278, "Cancel", 13, MUTED, 400, "middle")]), "TrollStore")),
    # ---- Sideload route
    "sl-trust": ("Settings, VPN and Device Management, Trust", "Settings, General, VPN and Device Management: open your Apple Account under Developer App and tap Trust.",
                 phone("\n".join([
                     text(30, 98, "DEVELOPER APP", 9.5, MUTED, 600),
                     row(106, "Apple Development: you@…", "›"),
                     text(30, 172, "Apps from developer “you@…”", 10, MUTED),
                     text(30, 186, "are not trusted on this iPhone.", 10, MUTED),
                     button(206, "Trust “you@…”"),
                     text(W / 2, 290, "Older versions call this", 10, MUTED, 400, "middle"),
                     text(W / 2, 304, "Profiles & Device Management", 10, MUTED, 400, "middle")]),
                     "Device Management", "General")),
    "sl-devmode": ("Settings, Privacy and Security, Developer Mode", "On iOS 16 or later, turn on Developer Mode in Settings, Privacy and Security, then restart when asked.",
                   phone("\n".join([
                       row(92, "Location Services", "On"), row(132, "Tracking", "›"),
                       text(30, 194, "SECURITY", 9.5, MUTED, 600),
                       toggle(202, "Developer Mode", True, True),
                       text(30, 262, "iOS restarts and asks you to", 10, MUTED), text(30, 276, "confirm after unlocking.", 10, MUTED)]),
                       "Privacy & Security", "Settings")),
    # ---- Dopamine
    "dp-main": ("Dopamine main screen with the Jailbreak button", "Dopamine's main screen. Reboot first (recommended), open Dopamine, and tap Jailbreak.",
                phone("\n".join([
                    f'<circle cx="{W/2}" cy="146" r="34" fill="none" stroke="{CYAN}" stroke-width="2"/>',
                    text(W / 2, 152, "D", 26, CYAN, 800, "middle"),
                    text(W / 2, 206, "Dopamine", 18, TEXT, 700, "middle"),
                    text(W / 2, 224, "by opa334, ElleKit by évelyne", 9.5, MUTED, 400, "middle"),
                    row(246, "Settings", "›"), row(284, "Credits", "›"),
                    button(H - 118, "Jailbreak")]), "")),
    "dp-pm": ("Select Package Manager(s) screen", "On the first jailbreak Dopamine asks which package manager to install. If unsure, choose Sileo.",
              phone("\n".join([
                  text(W / 2, 106, "Select Package Manager(s)", 13, TEXT, 700, "middle"),
                  text(W / 2, 128, "If you are unsure which one", 10, MUTED, 400, "middle"),
                  text(W / 2, 142, "to select, select Sileo", 10, MUTED, 400, "middle"),
                  row(162, "Sileo", "✓", True), row(204, "Zebra", ""),
                  button(H - 118, "Continue")]), "")),
    "dp-done": ("Dopamine progress log ending in Jailbroken", "Dopamine shows its progress while it works; the device does a userspace reboot and the app then shows Jailbroken.",
                phone("\n".join([
                    text(30, 104, "Jailbreaking", 13, TEXT, 700),
                    text(30, 130, "✓ Exploiting Kernel", 10.5, MUTED), text(30, 148, "✓ Bypassing PAC / PPL", 10.5, MUTED),
                    text(30, 166, "✓ Initializing Environment", 10.5, MUTED), text(30, 184, "✓ Initializing Protection", 10.5, MUTED),
                    text(30, 202, "✓ Rebooting Userspace", 10.5, MUTED),
                    text(30, 226, "Exact steps differ by device.", 9.5, MUTED),
                    f'<rect x="36" y="{H-118}" width="{W-72}" height="40" rx="9" fill="{ROW}" stroke="{OK}"/>',
                    text(W / 2, H - 93, "Jailbroken", 14, OK, 700, "middle")]), "")),
    "dp-settings": ("Dopamine Settings: Tweak Injection and actions", "Dopamine Settings: Tweak Injection, Verbose Logs, Refresh Jailbreak Apps, Reinstall Package Managers, Change mobile Password, Hide Jailbreak, Remove Jailbreak.",
                    phone("\n".join([
                        text(30, 96, "JAILBREAK SETTINGS", 9, MUTED, 600),
                        toggle(102, "Tweak Injection", True, True), toggle(140, "Verbose Logs", False),
                        text(30, 194, "ACTIONS", 9, MUTED, 600),
                        row(200, "Refresh Jailbreak Apps"), row(238, "Reinstall Package Managers"),
                        row(276, "Change “mobile” Password"), row(314, "Hide Jailbreak"),
                        row(352, "Remove Jailbreak", "", False, "", RED)]), "Settings", "Dopamine")),
    # ---- Sileo
    "si-sources": ("Sileo Sources tab with the ElleKit source", "In Sileo, open the Sources tab and tap the ElleKit repository, then All Categories.",
                   phone("\n".join([
                       row(90, "ElleKit", "›", True, "repository"), tap(W - 52, 110),
                       row(140, "Another source", "›", False, "", MUTED),
                       row(184, "Another source", "›", False, "", MUTED),
                       text(W / 2, 256, "Which other sources appear", 10, MUTED, 400, "middle"),
                       text(W / 2, 270, "depends on your setup.", 10, MUTED, 400, "middle"),
                       f'<line x1="16" y1="{H-80}" x2="{W-16}" y2="{H-80}" stroke="{LINE}"/>',
                       text(W * 0.2, H - 62, "Featured", 9.5, MUTED, 400, "middle"), text(W * 0.4, H - 62, "News", 9.5, MUTED, 400, "middle"),
                       text(W * 0.6, H - 62, "Sources", 9.5, CYAN, 700, "middle"), text(W * 0.8, H - 62, "Search", 9.5, MUTED, 400, "middle")]),
                       "Sources")),
    "si-get": ("Sileo package page with the Get button and the Queued bar", "Tap Get on ElleKit, search for PreferenceLoader and tap Get, then tap the Queued bar.",
               phone("\n".join([
                   f'<rect x="30" y="92" width="46" height="46" rx="10" fill="{ROW}" stroke="{LINE}"/>',
                   text(88, 110, "ElleKit", 14, TEXT, 700), text(88, 128, "Tweak injection library", 10, MUTED),
                   f'<rect x="{W-86}" y="100" width="54" height="26" rx="13" fill="{CYAN}"/>',
                   text(W - 59, 118, "GET", 11, "#031015", 800, "middle"), tap(W - 59, 113),
                   text(30, 176, "Then: Search › PreferenceLoader › Get", 10, MUTED),
                   f'<rect x="26" y="{H-122}" width="{W-52}" height="38" rx="10" fill="{ROW}" stroke="{CYAN}" stroke-width="2"/>',
                   text(W / 2, H - 98, "Queued (2)", 12, CYAN, 700, "middle")]), "ElleKit", "All Categories")),
    "si-confirm": ("Sileo queue with Confirm, then Reboot Device", "Tap Confirm. When it finishes, tap Reboot Device; this is a userspace reboot and you stay jailbroken.",
                   phone("\n".join([
                       text(30, 100, "INSTALLATIONS", 9.5, MUTED, 600),
                       row(108, "ElleKit"), row(146, "PreferenceLoader"),
                       button(200, "Confirm"),
                       text(W / 2, 282, "When it finishes:", 10, MUTED, 400, "middle"),
                       button(296, "Reboot Device", True, ROW, CYAN),
                       text(W / 2, 362, "Stays jailbroken afterwards", 10, OK, 600, "middle")]), "Queue")),
}


def diagram_cycle() -> str:
    w, h = 760, 300
    def box(xp, yp, bw, title, sub, color):
        return (f'<rect x="{xp}" y="{yp}" width="{bw}" height="86" rx="8" fill="{SCREEN}" stroke="{color}" stroke-width="2"/>'
                + text(xp + bw / 2, yp + 36, title, 16, TEXT, 700, "middle") + text(xp + bw / 2, yp + 60, sub, 12, MUTED, 400, "middle"))
    def arrow(x1, y1, x2, y2, label, color=CYAN, ly=None):
        return (f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="2" marker-end="url(#ah)"/>'
                + text((x1 + x2) / 2, ly if ly is not None else (y1 + y2) / 2 - 8, label, 12, color, 600, "middle"))
    body = [f'<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
            f'<path d="M0 0L10 5L0 10z" fill="context-stroke"/></marker></defs>',
            box(30, 40, 220, "Stock iOS", "no tweaks running", MUTED),
            box(500, 40, 230, "Jailbroken", "tweaks + package manager", OK),
            arrow(250, 70, 498, 70, "open Dopamine › Jailbreak"),
            arrow(500, 110, 252, 110, "full reboot / power off / battery dies", WARN, 132),
            f'<path d="M560 128 C560 200 670 200 670 128" fill="none" stroke="{OK}" stroke-width="2" marker-end="url(#ah)"/>',
            text(615, 214, "respring / userspace reboot:", 12, OK, 600, "middle"),
            text(615, 230, "stays jailbroken", 12, OK, 600, "middle"),
            text(30, 270, "Semi-untethered: the jailbreak lives in memory and is re-applied with the app after every full reboot.", 13, TEXT),
            text(30, 290, "Original HCG diagram.", 11, MUTED)]
    return svg(w, h, "\n".join(body), "Semi-untethered jailbreak cycle",
               "Stock iOS becomes jailbroken when you open Dopamine and tap Jailbreak. A respring or userspace reboot keeps the "
               "jailbreak; a full reboot returns the device to stock iOS until you run Dopamine again.")


def diagram_rootless() -> str:
    w, h = 760, 330
    def col(xp, title, sub, sys_note, writable, color):
        return "\n".join([
            text(xp, 36, title, 17, TEXT, 700), text(xp, 56, sub, 12, MUTED),
            f'<rect x="{xp}" y="72" width="330" height="96" rx="6" fill="{SCREEN}" stroke="{LINE}"/>',
            text(xp + 14, 98, "System volume:  /  (/Applications, /usr, /Library …)", 12, TEXT, 600),
            text(xp + 14, 122, sys_note[0], 12, color, 600), text(xp + 14, 142, sys_note[1], 11.5, MUTED),
            f'<rect x="{xp}" y="182" width="330" height="96" rx="6" fill="{SCREEN}" stroke="{LINE}"/>',
            text(xp + 14, 208, "Data volume:  /var, /private/preboot …", 12, TEXT, 600),
            text(xp + 14, 232, writable[0], 12, color if writable[2] else MUTED, 600), text(xp + 14, 252, writable[1], 11.5, MUTED)])
    body = [col(30, "Rootful (older style)", "package architecture iphoneos-arm",
                ("✎ jailbreak files written here", "tweaks install into / directly"),
                ("user data only", "", False), WARN),
            col(400, "Rootless (Dopamine)", "package architecture iphoneos-arm64",
                ("untouched by the jailbreak", "the system stays as Apple shipped it"),
                ("✎ everything goes under /var/jb", "a link to a hidden folder in /private/preboot", True), OK),
            text(30, 306, "Rootless tweaks must be rebuilt for /var/jb; Sileo shows only packages built for your layout.", 13, TEXT),
            text(30, 324, "Original HCG diagram, simplified.", 11, MUTED)]
    return svg(w, h, "\n".join(body), "Rootful versus rootless",
               "Rootful jailbreaks write into the system volume. Rootless jailbreaks such as Dopamine leave the system volume "
               "alone and keep all jailbreak files under /var/jb on the data volume.")


def diagram_route() -> str:
    w, h = 760, 360
    rows = [
        ("15.0 – 16.6.1", "TrollStore route", "TrollStore installs Dopamine permanently (no 7-day expiry)", OK),
        ("16.7 RC (20H18), 17.0", "TrollStore route", "TrollStore via TrollRestore (needs a computer)", OK),
        ("16.7 – 16.7.x, 17.0.1 – 17.3.1", "Sideload route", "all supported chips; re-sign every 7 days", WARN),
        ("17.4 – 18.7.1", "Sideload route", "A13 and earlier only; re-sign every 7 days", WARN),
        ("26.0 – 26.0.1", "Sideload route", "A13 and earlier only; re-sign every 7 days", WARN),
        ("anything else", "Not supported", "no Dopamine release covers it (as of 21 Nov 2026)", RED),
    ]
    body = [text(30, 34, "iOS / iPadOS version", 12, MUTED, 600), text(270, 34, "Route", 12, MUTED, 600), text(430, 34, "What it means", 12, MUTED, 600)]
    for i, (v, r, m, c) in enumerate(rows):
        y = 48 + i * 46
        body += [f'<rect x="24" y="{y}" width="712" height="38" rx="6" fill="{SCREEN}" stroke="{LINE}"/>',
                 f'<rect x="24" y="{y}" width="5" height="38" fill="{c}"/>',
                 text(40, y + 24, v, 13, TEXT, 700), text(270, y + 24, r, 13, c, 700), text(430, y + 24, m, 11.5, TEXT)]
    body += [text(30, 336, "From ios.cfw.guide (Installing Dopamine / Installing Dopamine (TrollStore)). Use the checker for your exact model.", 12, MUTED),
             text(30, 352, "Original HCG diagram.", 11, MUTED)]
    return svg(w, h, "\n".join(body), "Which installation route applies",
               "Versions 15.0 to 16.6.1, 16.7 RC and 17.0 use TrollStore. 16.7 to 16.7.x and 17.0.1 to 17.3.1 use sideloading on all "
               "supported chips; 17.4 to 18.7.1 and 26.0 to 26.0.1 use sideloading on A13 and earlier only. Anything else is not supported.")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (title, desc, body) in PHONES.items():
        (OUT / f"{name}.svg").write_text(svg(W, H, body, title + " (illustration)", desc), encoding="utf-8")
    (OUT / "diagram-cycle.svg").write_text(diagram_cycle(), encoding="utf-8")
    (OUT / "diagram-rootless.svg").write_text(diagram_rootless(), encoding="utf-8")
    (OUT / "diagram-route.svg").write_text(diagram_route(), encoding="utf-8")
    print(f"wrote {len(PHONES) + 3} SVGs to {OUT}")


if __name__ == "__main__":
    main()
