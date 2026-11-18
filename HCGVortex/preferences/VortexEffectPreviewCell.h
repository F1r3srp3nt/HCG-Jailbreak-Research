//
//  VortexEffectPreviewCell.h
//  HCG Vortex — Hakmi Capital Group
//
//  Live preview of a per-icon effect in Settings. The specifier's "effect"
//  property names it (e.g. "tornado"). Runs the SAME C geometry the
//  SpringBoard engine uses (src/VortexIconEffects.c) on a mock 4 x 6 page of
//  coloured tiles with the current settings. A preview of the geometry, not a
//  capture of the Home Screen.
//

#import <Preferences/PSTableCell.h>

@interface VortexEffectPreviewCell : PSTableCell
@end
