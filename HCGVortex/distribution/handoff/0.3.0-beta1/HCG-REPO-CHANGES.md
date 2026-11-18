# HCG-repo changes for 0.3.0~beta1 (proposed, not applied)

These are edits for `packages/com.hakmicapitalgroup.vortex/package.toml` on HCG-repo `main`. This session does not
change HCG-repo.

## 1. Access: candidate channel only

The owner has authorised candidate builds as free public demos, without sign-in or payment. Production access policies
are separate and unchanged. List this version in the existing per-package exception:

```toml
exception_versions = ["0.1.0~beta1", "0.1.0~beta2", "0.2.0~beta1", "0.3.0~beta1"]
```

Nothing else in `[access]` changes. No other product's sign-in or ownership protection is touched.

## 2. Version entry (no device results yet)

```toml
[versions."0.3.0~beta1"]
status = "experimental"
# Six icon effects (Tornado, Orbital, Warp, Holographic Layers, Circuit Flow, Magnetic Grid). Not yet installed or tested on a device.
```

## 3. Notes and known issues (additions)

```
- **0.3.0~beta1:** six icon effects (Tornado, Orbital, Warp, Holographic Layers, Circuit Flow, Magnetic Grid), each with its own Settings page and live preview. None has been tested on a device; frame rate and battery impact are unmeasured.
- Icon effects use the stock animation while Reduce Motion is on. Widgets fade in place instead of joining a formation.
- Not tested together with HCG Halo or HCG Nexus.
```

## 4. Import

Add `imports/hcg-vortex-0.3.0-beta1-rootless.toml` (`channel = "candidate"`) on a branch. **Prepare packages** checks
it. Then merge, and run Publish when HCG decides to.
