# AI-generated backgrounds through HCG AI (later phase)

**Status in 0.1.0~beta1: interface only. HCG AI is not connected. The package contains no network code**
(`validate.sh` section 7 fails on any networking API or URL). *Settings › AI Backgrounds* explains this and keeps
*Generate Preview* disabled.

## The contract (`preferences/HACAIGeneration.h`)

```
HACAIGenerationProvider
  providerName
  currentAccess -> HACAIAccess { Unavailable | SignedOut | NotEntitled | Allowed, explanation }
  generate:(HACAIRequest)progress:completion:(HACAIResult | NSError)
  cancel

HACAIRequest  prompt (1–500 chars), style (calm | vivid | abstract), durationSeconds (2–10), pixelSize (portrait screen)
HACAIResult   previewFile (local video), suggestedName, generatorInfo (provider, model, request ID, prompt)
```

## Rules

1. **Central HCG access controls decide.** The provider asks HCG's access service (HCG account, entitlement); Animation
   Center never decides entitlement itself and never caches a grant beyond the provider's answer. The UI enables
   *Generate Preview* only for `Allowed` and otherwise shows the provider's explanation.
2. **Generation produces a preview only.** The result is a local file shown in the editor's preview mode with the same
   controls (trim, scale, loop, speed). Nothing is added to the library, assigned, or applied.
3. **Only an explicit choice adopts it**: *Apply to Home Screen*, *Apply to Lock Screen* or *Save to Library*. The
   file then goes through the normal importer (video track only, limits, still, checksum), and the preset records
   `origin: "ai"` and `generator: {kind: "ai", …}`. *Discard*, or leaving the screen, deletes the preview file.
4. The preset format is unchanged: an AI background is an ordinary version-1 preset.

## What was tested

The Simulator preview registers a **local test provider** (no network; it generates a video on the device) and checks:
the result opens as a preview; the library and assignments are unchanged; *Save to Library* adds exactly one item with
`origin: ai` and the generator record. `tests/test_runtime.m` checks that the shipped provider reports *not connected*,
refuses to generate, and that requests are validated.

## Still to do (with HCG AI)

- An `HCGAIProvider` that talks to HCG AI through HCG's shared client and access SDK (not in this repository).
- Moderation and a content policy owned by HCG AI.
- Usage limits and errors surfaced through `HACAIAccess.explanation`.
- A privacy notice in Settings before the first request (prompts leave the device only then).
