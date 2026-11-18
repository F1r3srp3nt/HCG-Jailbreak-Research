# HCG-repo changes for 0.2.0~beta1 (proposed, not applied)

These are edits for `packages/com.hakmicapitalgroup.vortex/package.toml` on HCG-repo `main`. This session cannot write
to HCG-repo.

## 1. Access: candidate channel only

The owner has authorised candidate builds as free public demos, without sign-in or payment. Production access
policies are separate and unchanged. So list this version in the existing per-package exception:

```toml
exception_versions = ["0.1.0~beta1", "0.1.0~beta2", "0.2.0~beta1"]
```

Nothing else in `[access]` changes. No other product's sign-in or ownership protection is touched. Whether 0.1.0~beta2
is also listed is unchanged by this handoff (see its own handoff).

## 2. Version entry (no device results yet)

```toml
[versions."0.2.0~beta1"]
status = "experimental"
# Adds the Tornado effect. Not yet installed or tested on a device.
```

## 3. Notes and known issues (additions)

```
- **0.2.0~beta1 adds Tornado:** the icons form a spinning 3-D funnel as you swipe between pages. It has not been tested on a device; frame rate and battery impact are unmeasured.
- Tornado uses the stock animation while Reduce Motion is on. Widgets fade in place instead of joining the funnel.
- Not tested together with HCG Halo or HCG Nexus.
```

Keep the existing 0.1.0~beta1 install-failure entry as it is.

## 4. Import

Add `imports/hcg-vortex-0.2.0-beta1-rootless.toml` (`channel = "candidate"`) on a branch. **Prepare packages** checks
it. Then merge, and run Publish when HCG decides to.
