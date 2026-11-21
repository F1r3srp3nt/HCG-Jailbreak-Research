//
//  HCGBackgroundKit.h
//  HCGBackgroundKit — Hakmi Capital Group
//
//  Opt-in component for HCG apps: reads, validates and writes HCG background
//  presets (format version 1) and renders them with HCGBackgroundView.
//  It has no dependency on HCG Animation Center, needs no jailbreak and makes
//  no network requests. An app that adopts it keeps working when the tweak is
//  not installed. See README.md.
//

#import "HCGBackgroundCore.h"
#import "HCGBackgroundPreset.h"
#import "HCGBackgroundView.h"

/// Version of this component (independent of the preset format version).
#define HCG_BACKGROUND_KIT_VERSION "1.1.0"
