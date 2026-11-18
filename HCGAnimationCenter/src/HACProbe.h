//
//  HACProbe.h
//  HCG Animation Center — Hakmi Capital Group
//
//  A read-only snapshot of SpringBoard's windows and wallpaper views, written
//  on request (Settings › Diagnostics › Write Hierarchy Probe) to
//  /var/mobile/Library/HCGAnimationCenter/Diagnostics/hierarchy-<time>.txt.
//
//  It records class names, frames, window levels and hidden/alpha state —
//  never view contents, text, images or user data — so the first device run
//  shows where the Home Screen and Lock Screen wallpaper really live on that
//  iOS version. It changes nothing.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Writes a probe; returns its path, or nil with *error.
NSString *_Nullable HACWriteHierarchyProbe(NSDictionary<NSString *, id> *status, NSError **error);

/// The probe text (no file); for tests.
NSString *HACHierarchyProbeText(NSDictionary<NSString *, id> *status);

NS_ASSUME_NONNULL_END
