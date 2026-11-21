//
//  PortalTouchSynth.m
//  HCG Portal — synthesised touches for the PREVIEW only (iOS Simulator). See the header.
//

#import "PortalTouchSynth.h"

#import <objc/message.h>

#include <dlfcn.h>
#include <mach/mach_time.h>

// ---- IOKit (private symbols, resolved at run time) ------------------------------------
typedef struct __IOHIDEvent *PTSHIDEventRef;
typedef double PTSHIDFloat; // IOHIDFloat on 64-bit
// AbsoluteTime is an 8-byte struct {lo, hi}: on arm64 and x86_64 it is passed exactly like a uint64_t.
typedef PTSHIDEventRef (*PTSCreateDigitizerEvent)(CFAllocatorRef, uint64_t, uint32_t type, uint32_t index, uint32_t identity,
                                                   uint32_t eventMask, uint32_t buttonMask, PTSHIDFloat x, PTSHIDFloat y,
                                                   PTSHIDFloat z, PTSHIDFloat tipPressure, PTSHIDFloat barrelPressure,
                                                   Boolean range, Boolean touch, uint32_t options);
typedef PTSHIDEventRef (*PTSCreateFingerEvent)(CFAllocatorRef, uint64_t, uint32_t index, uint32_t identity, uint32_t eventMask,
                                                PTSHIDFloat x, PTSHIDFloat y, PTSHIDFloat z, PTSHIDFloat tipPressure,
                                                PTSHIDFloat twist, PTSHIDFloat minorRadius, PTSHIDFloat majorRadius,
                                                PTSHIDFloat quality, PTSHIDFloat density, PTSHIDFloat irregularity, Boolean range,
                                                Boolean touch, uint32_t options);
typedef void (*PTSAppendEvent)(PTSHIDEventRef parent, PTSHIDEventRef child, uint32_t options);
typedef void (*PTSSetIntegerValue)(PTSHIDEventRef event, uint32_t field, int value);

enum {
    PTSTransducerHand = 3,
    PTSEventRange = 1 << 0,
    PTSEventTouch = 1 << 1,
    PTSEventPosition = 1 << 2,
    PTSFieldDigitizerIsDisplayIntegrated = (11 << 16) + 25, // kIOHIDEventTypeDigitizer, field 25
};

static PTSCreateDigitizerEvent gCreateDigitizer;
static PTSCreateFingerEvent gCreateFinger;
static PTSAppendEvent gAppend;
static PTSSetIntegerValue gSetInteger;

// ---- UIKit (private selectors, checked at run time) ------------------------------------
@interface UITouch (PTSPrivate)
- (void)setWindow:(UIWindow *)window;
- (void)setView:(UIView *)view;
- (void)setTapCount:(NSUInteger)count;
- (void)setIsTap:(BOOL)isTap;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)setPhase:(UITouchPhase)phase;
- (void)setGestureView:(UIView *)view;
- (void)_setLocationInWindow:(CGPoint)location resetPrevious:(BOOL)resetPrevious;
- (void)_setIsFirstTouchForView:(BOOL)first;
- (void)_setIsTapToClick:(BOOL)tapToClick;
- (void)_setHidEvent:(PTSHIDEventRef)event;
@end

@interface UIApplication (PTSPrivate)
- (UIEvent *)_touchesEvent;
@end

@interface UIEvent (PTSPrivate)
- (void)_clearTouches;
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayed;
- (void)_setHIDEvent:(PTSHIDEventRef)event;
@end

static NSString *gWhyNot;

static BOOL PTSResolve(void) {
    static dispatch_once_t once;
    static BOOL ok;
    dispatch_once(&once, ^{
        void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        gCreateDigitizer = (PTSCreateDigitizerEvent)dlsym(iokit ?: RTLD_DEFAULT, "IOHIDEventCreateDigitizerEvent");
        gCreateFinger = (PTSCreateFingerEvent)dlsym(iokit ?: RTLD_DEFAULT, "IOHIDEventCreateDigitizerFingerEventWithQuality");
        gAppend = (PTSAppendEvent)dlsym(iokit ?: RTLD_DEFAULT, "IOHIDEventAppendEvent");
        gSetInteger = (PTSSetIntegerValue)dlsym(iokit ?: RTLD_DEFAULT, "IOHIDEventSetIntegerValue");
        NSMutableArray *missing = [NSMutableArray array];
        if (!gCreateDigitizer) [missing addObject:@"IOHIDEventCreateDigitizerEvent"];
        if (!gCreateFinger) [missing addObject:@"IOHIDEventCreateDigitizerFingerEventWithQuality"];
        if (!gAppend) [missing addObject:@"IOHIDEventAppendEvent"];
        if (!gSetInteger) [missing addObject:@"IOHIDEventSetIntegerValue"];
        for (NSString *name in @[ @"setWindow:", @"setView:", @"setPhase:", @"setTimestamp:", @"setTapCount:", @"setIsTap:",
                                  @"_setLocationInWindow:resetPrevious:", @"_setIsFirstTouchForView:", @"_setHidEvent:" ])
            if (![UITouch instancesRespondToSelector:NSSelectorFromString(name)]) [missing addObject:[@"UITouch -" stringByAppendingString:name]];
        if (![UIApplication instancesRespondToSelector:@selector(_touchesEvent)]) [missing addObject:@"UIApplication -_touchesEvent"];
        UIEvent *event = [[UIApplication sharedApplication] respondsToSelector:@selector(_touchesEvent)]
                             ? [[UIApplication sharedApplication] _touchesEvent]
                             : nil;
        for (NSString *name in @[ @"_clearTouches", @"_addTouch:forDelayedDelivery:", @"_setHIDEvent:" ])
            if (![event respondsToSelector:NSSelectorFromString(name)]) [missing addObject:[@"UITouchesEvent -" stringByAppendingString:name]];
        ok = missing.count == 0;
        gWhyNot = ok ? nil : [@"missing " stringByAppendingString:[missing componentsJoinedByString:@", "]];
    });
    return ok;
}

BOOL PTSAvailable(NSString **why) {
    BOOL ok = PTSResolve();
    if (why) *why = gWhyNot;
    return ok;
}

static PTSHIDEventRef PTSHIDEventForTouch(UITouch *touch) {
    uint64_t now = mach_absolute_time();
    PTSHIDEventRef hand = gCreateDigitizer(kCFAllocatorDefault, now, PTSTransducerHand, 0, 0, PTSEventTouch, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    gSetInteger(hand, PTSFieldDigitizerIsDisplayIntegrated, 1);
    uint32_t mask = touch.phase == UITouchPhaseMoved ? PTSEventPosition : (PTSEventRange | PTSEventTouch);
    Boolean touching = touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled;
    CGPoint p = [touch locationInView:touch.window];
    PTSHIDEventRef finger = gCreateFinger(kCFAllocatorDefault, now, 1, 2, mask, p.x, p.y, 0, 0, 0, 5.0, 5.0, 1.0, 1.0, 1.0,
                                          touching, touching, 0);
    gSetInteger(finger, PTSFieldDigitizerIsDisplayIntegrated, 1);
    gAppend(hand, finger, 0);
    CFRelease(finger);
    return hand;
}

static void PTSSend(UITouch *touch) {
    PTSHIDEventRef hid = PTSHIDEventForTouch(touch);
    [touch _setHidEvent:hid];
    UIEvent *event = [[UIApplication sharedApplication] _touchesEvent];
    [event _clearTouches];
    [event _setHIDEvent:hid];
    [event _addTouch:touch forDelayedDelivery:NO];
    CFRelease(hid);
    [[UIApplication sharedApplication] sendEvent:event];
}

static void PTSSpin(NSTimeInterval seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([until timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

static UITouch *PTSBegin(UIWindow *window, CGPoint point) {
    UIView *target = [window hitTest:point withEvent:nil];
    UITouch *touch = [[UITouch alloc] init];
    [touch setWindow:window];
    [touch setTapCount:1];
    [touch _setLocationInWindow:point resetPrevious:YES];
    [touch setView:target];
    [touch setPhase:UITouchPhaseBegan];
    if ([touch respondsToSelector:@selector(_setIsTapToClick:)]) [touch _setIsTapToClick:NO];
    [touch _setIsFirstTouchForView:YES];
    [touch setIsTap:YES];
    [touch setTimestamp:[NSProcessInfo processInfo].systemUptime];
    if ([touch respondsToSelector:@selector(setGestureView:)]) [touch setGestureView:target];
    PTSSend(touch);
    return touch;
}

static void PTSPhase(UITouch *touch, UITouchPhase phase, CGPoint point) {
    [touch setPhase:phase];
    [touch _setLocationInWindow:point resetPrevious:NO];
    [touch setTimestamp:[NSProcessInfo processInfo].systemUptime];
    PTSSend(touch);
}

BOOL PTSTap(UIWindow *window, CGPoint point, NSTimeInterval hold) {
    if (!PTSResolve() || !window) return NO;
    UITouch *touch = PTSBegin(window, point);
    PTSSpin(MAX(hold, 0.02));
    PTSPhase(touch, UITouchPhaseEnded, point);
    PTSSpin(0.35);
    return YES;
}

BOOL PTSDrag(UIWindow *window, CGPoint from, CGPoint to, NSUInteger steps) {
    if (!PTSResolve() || !window) return NO;
    if (steps < 2) steps = 2;
    UITouch *touch = PTSBegin(window, from);
    PTSSpin(0.02);
    for (NSUInteger i = 1; i <= steps; i++) {
        CGFloat t = (CGFloat)i / steps;
        CGPoint p = CGPointMake(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t);
        PTSPhase(touch, UITouchPhaseMoved, p);
        PTSSpin(0.016);
    }
    PTSPhase(touch, UITouchPhaseEnded, to);
    PTSSpin(0.35);
    return YES;
}
