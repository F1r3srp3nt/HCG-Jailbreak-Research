# Roadmap (documented, NOT implemented)

Nothing on this page exists in 0.1.0~beta1. Each item names what it depends on and the rules it must keep. The rules
of the first beta stay in force for all of them: protected actions only after normal iOS authentication, the selected
action only, cancellation discards, nothing private on the Lock Screen, no device command while locked.

## 1. Hold-to-open typed commands, then HCG AI voice input

- **Hold** on the portal (≥ 0.6 s; a tap still opens the menu) opens a small command field **after** authentication:
  typing on the Lock Screen keyboard while locked would expose what is typed and invite commands without a user.
- Commands are matched locally against a fixed, documented vocabulary first ("open backgrounds", "apps", "nexus"),
  mapping to the same destinations as the menu; anything else is refused with an explanation.
- **HCG AI voice input** comes later and needs: a defined HCG AI service and its access rules (HCG Connect / ERP),
  microphone permission handled by an app (not SpringBoard), on-screen transcript before acting, and the same
  authentication gate. No audio is recorded while locked.
- Needs from Portal: a gesture recogniser limited to the orb, and Settings to turn it off.

## 2. Authenticated device selection through Connector and Origin

- Today **Devices** says *Not connected*: no Connector or Origin integration exists in any repository this session can
  see. When one does, Portal will inspect its contract first, as it did for Nexus.
- Device lists are private: shown only after authentication, never on the locked Lock Screen. Selection opens the
  owning app (or a future HCG device panel) rather than acting from SpringBoard.
- Identity and authorisation stay with HCG Connect and ERP (the rule HCG Nexus already follows: "Nexus stores no HCG
  credentials"). Portal stores none either.

## 3. Approved actions through HCG Agent Runtime

- Model: Agent Runtime's own approval flow (`/api/v1/tasks` → preview → `approve {digest}` → run, audited hash chain;
  branch `claude/brave-rubin-7vwtg1`, unmerged). Its iOS jailbroken adapter is planned, not implemented, and its API
  is loopback-only on the host.
- Portal would only ever **show** a pending approval and, after authentication, approve **exactly the previewed
  digest**; it never constructs commands itself and never runs anything while locked.
- Depends on: an Agent Runtime adapter reachable from the phone under HCG Connect, and a documented, versioned
  approval contract.

## 4. Additional portal themes and background packs

- Themes: more palettes and ring styles through the same render plan (Reduce Motion / Low Power rules unchanged).
  Theme packs would be data (colours, ring parameters) validated like preferences — never code.
- Background packs belong to **HCG Animation Center** (its HCG background preset format v1). Portal may *offer* a
  pack, opening Animation Center to apply it; Portal never writes Animation Center's preferences.

## 5. Companion work that would unlock existing destinations

- HCG Nexus: implement `HCGNexusPortalInterface` v1 (`INTEGRATIONS.md` §1).
- HCG Animation Center: a documented route to its library page (`INTEGRATIONS.md` §2).
- HCG Halo: optionally react to Portal lighting events v1 (`INTEGRATIONS.md` §3).
