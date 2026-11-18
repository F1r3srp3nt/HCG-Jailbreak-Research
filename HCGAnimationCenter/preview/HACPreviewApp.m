//
//  HACPreviewApp.m
//  HCG Animation Center — PREVIEW and integration run (iOS Simulator only).
//
//  Built by scripts/preview.sh. One app plays two roles:
//
//  1. Settings: loads the REAL HCGAnimationCenterPrefs.bundle (compiled for the
//     Simulator from preferences/) with Preferences.framework from the
//     Simulator runtime, and drives it: the root page, the media library
//     (importing generated media, including damaged and unsupported files),
//     the editor (crop, speed), Apply to Home Screen / Lock Screen, and the AI
//     page with a LOCAL test provider (preview first, explicit Save).
//
//  2. A stand-in SpringBoard running the REAL tweak code (HACController,
//     HACHosts, HCGBackgroundView) the way SpringBoard would: the app's
//     UIApplication class is named SpringBoard, its windows are
//     SBHomeScreenWindow, SBCoverSheetWindow and _SBWallpaperWindow, an
//     SBWallpaperController hands out the system wallpaper views, and lock /
//     screen-off arrive as Darwin notifications with notify state (preview
//     names, so the Simulator's real SpringBoard is never touched).
//     When their checkouts are supplied (HAC_WITH_HALO / _VORTEX / _NEXUS):
//       - HCG Halo's REAL controller draws its border in the same
//         SBHomeScreenWindow (its own preview build flags);
//       - HCG Vortex's REAL engine transforms the stand-in Home Screen pages
//         (SBRootFolderView / SBIconScrollView / SBIconListView) during a swipe;
//       - HCG Nexus's REAL panel opens over the Home Screen.
//
//  What is NOT real: SpringBoard itself, its wallpaper (a generated image),
//  window levels, PosterBoard, a dark display, Reduce Motion / Low Power
//  toggles, a device and its performance. Preview evidence, not a device
//  result.
//
//  Prints "HAC-PREVIEW-STATE <name> | …", "HAC-PREVIEW-SHOT <name>" (the script
//  takes a Simulator screenshot), "HAC-PREVIEW-CHECK PASS|FAIL <what>", then
//  "HAC-PREVIEW-DONE failures=N".
//

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "HACAIGeneration.h"
#import "HACAIViewController.h"
#import "HACController.h"
#import "HACEditorViewController.h"
#import "HACLibraryViewController.h"
#import "HACLibrary.h"
#import "HACPreferences.h"
#import "HACTestMedia.h"
#import "HCGBackgroundView.h"

#include <dlfcn.h>
#include <notify.h>

#ifdef HAC_WITH_HALO
#import "HaloController.h"
#import "HaloPreferences.h"
#endif
#ifdef HAC_WITH_VORTEX
#import "VortexCore.h"
#import "VortexPreferences.h"
#endif
#ifdef HAC_WITH_NEXUS
#import "HCGCore.h"
#import "HCGNexusModel.h"
#import "HCGOverlayController.h"
#import "HCGPreviewPlatform.h"
#endif

static int gFailures = 0;

static void Say(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void Say(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static void Check(BOOL ok, NSString *what) {
    if (!ok) gFailures++;
    Say(@"HAC-PREVIEW-CHECK %@ %@", ok ? @"PASS" : @"FAIL", what);
}

#pragma mark - Stand-ins for the SpringBoard classes the tweaks look up

@interface SBApplication : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@end
@implementation SBApplication
@end

@interface SBHomeScreenWindow : UIWindow
@end
@implementation SBHomeScreenWindow
@end

@interface SBCoverSheetWindow : UIWindow
@end
@implementation SBCoverSheetWindow
@end

@interface _SBWallpaperWindow : UIWindow
@end
@implementation _SBWallpaperWindow
@end

static UIView *gLockWallpaper, *gHomeWallpaper;

@interface SBWallpaperController : NSObject
+ (instancetype)sharedInstance;
- (id)_wallpaperViewForVariant:(long long)variant;
@end
@implementation SBWallpaperController
+ (instancetype)sharedInstance {
    static SBWallpaperController *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[SBWallpaperController alloc] init];
    });
    return shared;
}
- (id)_wallpaperViewForVariant:(long long)variant {
    return variant == 0 ? gLockWallpaper : gHomeWallpaper;
}
@end

static SBApplication *gFront;

@interface SpringBoard : UIApplication
- (void)frontDisplayDidChange:(id)display;
- (id)_accessibilityFrontMostApplication;
@end
@implementation SpringBoard
- (void)frontDisplayDidChange:(id)display {
}
- (id)_accessibilityFrontMostApplication {
    return gFront;
}
@end

// The Home Screen paging structure HCG Vortex hooks (SpringBoardHome, iOS 14+).
@interface SBIconListView : UIView
@end
@implementation SBIconListView
- (void)layoutSubviews {
    [super layoutSubviews];
}
@end

@interface SBIconScrollView : UIScrollView
@end
@implementation SBIconScrollView
@end

@interface SBFolderView : UIView <UIScrollViewDelegate>
@property (nonatomic, readonly) UIScrollView *scrollView;
@property (nonatomic, readonly, copy) NSArray *iconListViews;
@property (nonatomic, readonly) long long currentPageIndex;
@property (nonatomic, readonly, getter=isEditing) BOOL editing;
@end
@implementation SBFolderView {
    SBIconScrollView *_scroll;
    NSMutableArray *_lists;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _scroll = [[SBIconScrollView alloc] initWithFrame:self.bounds];
        _scroll.pagingEnabled = YES;
        _scroll.showsHorizontalScrollIndicator = NO;
        _scroll.delegate = self;
        _scroll.clipsToBounds = NO;
        [self addSubview:_scroll];
        _lists = [NSMutableArray array];
    }
    return self;
}
- (UIScrollView *)scrollView {
    return _scroll;
}
- (NSArray *)iconListViews {
    return [_lists copy];
}
- (long long)currentPageIndex {
    return (long long)lround(_scroll.contentOffset.x / MAX(1.0, _scroll.bounds.size.width));
}
- (BOOL)isEditing {
    return NO;
}
- (void)addPage:(SBIconListView *)page {
    [_lists addObject:page];
    [_scroll addSubview:page];
    [self setNeedsLayout];
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _scroll.frame = self.bounds;
    CGFloat w = self.bounds.size.width;
    for (NSUInteger i = 0; i < _lists.count; i++)
        [_lists[i] setFrame:CGRectMake(i * w, 0, w, self.bounds.size.height)];
    _scroll.contentSize = CGSizeMake(w * _lists.count, self.bounds.size.height);
}
@end

@interface SBRootFolderView : SBFolderView
@end
@implementation SBRootFolderView
@end

#pragma mark - Hook installers (the tweaks' Logos hooks, done by hand: original first)

static void Chain(Class cls, SEL sel, void (^after)(id self_, id arg)) {
    Method method = class_getInstanceMethod(cls, sel);
    __block IMP original = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^(id self_, id arg) {
        ((void (*)(id, SEL, id))original)(self_, sel, arg);
        after(self_, arg);
    });
    method_setImplementation(method, replacement);
}

static void HACInstallHook(void) {
    Chain([SpringBoard class], @selector(frontDisplayDidChange:), ^(id self_, id display) {
        HACControllerFrontDisplayDidChange(display);
    });
}

#ifdef HAC_WITH_HALO
static void HaloInstallHook(void) {
    Chain([SpringBoard class], @selector(frontDisplayDidChange:), ^(id self_, id display) {
        HaloControllerFrontDisplayDidChange(display);
    });
}
#endif

#ifdef HAC_WITH_VORTEX
static void ChainVoid(Class cls, SEL sel, void (^after)(id self_)) {
    Method method = class_getInstanceMethod(cls, sel);
    __block IMP original = method_getImplementation(method);
    method_setImplementation(method, imp_implementationWithBlock(^(id self_) {
        ((void (*)(id, SEL))original)(self_, sel);
        after(self_);
    }));
}

static void VortexInstallHooks(void) {
    Chain([SBFolderView class], @selector(scrollViewDidScroll:), ^(id self_, id scrollView) {
        VortexCoreHandleScroll(self_, scrollView);
    });
    ChainVoid([SBFolderView class], @selector(layoutSubviews), ^(id self_) {
        VortexCoreHandleLayout(self_);
    });
    BOOL list = VortexCoreListLayoutHookAvailable();
    if (list)
        ChainVoid([SBIconListView class], @selector(layoutSubviews), ^(id self_) {
            VortexCoreHandleListLayout(self_);
        });
    VortexCoreNoteListLayoutHookInstalled(list);
}

/// HCG Vortex checks it is inside com.apple.springboard before doing anything.
/// Only for the duration of its bootstrap call, the main bundle says so.
static NSString *VortexBundleIdentifier(id self_, SEL _cmd) {
    return @"com.apple.springboard";
}
#endif

#pragma mark - System state (preview notification names)

static void PostState(const char *name, uint64_t value) {
    int token = NOTIFY_TOKEN_INVALID;
    if (notify_register_check(name, &token) != NOTIFY_STATUS_OK) return;
    notify_set_state(token, value);
    notify_post(name);
    notify_cancel(token);
}

#pragma mark - Inspection

static NSArray<UIWindow *> *Windows(void) {
    NSMutableArray *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:[UIWindowScene class]]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    return windows;
}

static void CollectIdentified(UIView *view, NSString *prefix, NSMutableArray *out) {
    if ([view.accessibilityIdentifier hasPrefix:prefix]) [out addObject:view];
    for (UIView *sub in view.subviews) CollectIdentified(sub, prefix, out);
}

static NSArray<UIView *> *ViewsIdentified(NSString *prefix) {
    NSMutableArray *out = [NSMutableArray array];
    for (UIWindow *w in Windows()) CollectIdentified(w, prefix, out);
    return out;
}

static HCGBackgroundView *SurfaceView(int surface) {
    return HACControllerPreviewSurfaceView(surface);
}

static AVPlayer *PlayerOf(HCGBackgroundView *view) {
    return view ? [view valueForKey:@"player"] : nil;
}

static NSString *Rendering(NSString *key) {
    NSDictionary *surface = HACControllerPreviewStatus()[key];
    return [surface isKindOfClass:[NSDictionary class]] ? surface[@"rendering"] : @"";
}

static UIImage *WallpaperImage(NSString *title, double hue) {
    CGSize size = UIScreen.mainScreen.bounds.size;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        NSArray *colours = @[
            (id)[UIColor colorWithHue:hue saturation:0.35 brightness:0.55 alpha:1].CGColor,
            (id)[UIColor colorWithHue:fmod(hue + 0.1, 1) saturation:0.45 brightness:0.25 alpha:1].CGColor
        ];
        CGGradientRef g = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colours, NULL);
        CGContextDrawLinearGradient(ctx.CGContext, g, CGPointZero, CGPointMake(size.width, size.height), 0);
        CGGradientRelease(g);
        CGColorSpaceRelease(space);
        NSDictionary *attrs = @{
            NSFontAttributeName : [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold],
            NSForegroundColorAttributeName : [UIColor colorWithWhite:1 alpha:0.6]
        };
        [title drawAtPoint:CGPointMake(20, size.height * 0.62) withAttributes:attrs];
    }];
}

#pragma mark - A local AI provider (tests only: generates a video on the device, no network)

@interface HACPreviewAIProvider : NSObject <HACAIGenerationProvider>
@end
@implementation HACPreviewAIProvider
- (NSString *)providerName {
    return @"Local test provider (preview only)";
}
- (HACAIAccess *)currentAccess {
    return [HACAIAccess accessWithState:HACAIAccessAllowed
                            explanation:@"Preview harness: a local generator stands in for HCG AI and central access."];
}
- (void)generate:(HACAIRequest *)request progress:(HACAIProgress)progress completion:(HACAICompletion)completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        progress(0.2, @"Generating (local test provider)");
        NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"ai-preview.mov"];
        NSError *error = nil;
        BOOL ok = HACWriteTestVideo(url, CGSizeMake(540, 1170), request.durationSeconds, 0.82, NO, &error);
        progress(1.0, @"Done");
        HACAIResult *result = nil;
        if (ok) {
            result = [[HACAIResult alloc] init];
            result.previewFile = url;
            result.suggestedName = @"Aurora (AI)";
            result.generatorInfo = @{@"provider" : @"preview-local", @"prompt" : request.prompt, @"requestID" : [NSUUID UUID].UUIDString};
        }
        completion(result, ok ? nil : error);
    });
}
- (void)cancel {
}
@end

#pragma mark - The run

@interface HACPreviewController : UIViewController
@end

@implementation HACPreviewController {
    NSMutableArray<void (^)(void)> *_steps;
    UIWindow *_wallpaperWindow, *_coverWindow, *_settingsWindow, *_captionWindow, *_appWindow, *_nexusWindow;
    SBHomeScreenWindow *_homeWindow;
    SBRootFolderView *_folder;
    UIButton *_firstIcon;
    UILabel *_caption;
    UINavigationController *_settingsNav;
    NSURL *_media;
    NSInteger _iconTaps;
    HCGBackgroundPreset *_videoItem, *_gifItem;
#ifdef HAC_WITH_NEXUS
    HCGNexusModel *_nexusModel;
    HCGOverlayController *_nexusOverlay;
    id _nexusStore, _nexusLauncher, _nexusEnvironment;
#endif
}

- (void)loadView {
    // The stand-in Home Screen: transparent, with paged icon lists and a dock.
    UIView *root = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    root.backgroundColor = UIColor.clearColor;
    _folder = [[SBRootFolderView alloc] initWithFrame:root.bounds];
    _folder.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    NSArray *names = @[ @"Mail", @"Photos", @"Maps", @"Notes", @"Music", @"Clock", @"Files", @"Health", @"Wallet", @"News",
                        @"Books", @"Podcasts", @"Camera", @"Weather", @"Home", @"Stocks" ];
    CGSize s = root.bounds.size;
    CGFloat icon = 60, gap = (s.width - 4 * icon) / 5;
    for (int page = 0; page < 2; page++) {
        SBIconListView *list = [[SBIconListView alloc] initWithFrame:root.bounds];
        for (int i = 0; i < 16; i++) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
            b.frame = CGRectMake(gap + (i % 4) * (icon + gap), 80 + (i / 4) * 100, icon, icon);
            b.backgroundColor = [UIColor colorWithHue:fmod(0.08 * i + page * 0.37, 1) saturation:0.55 brightness:0.92 alpha:1];
            b.layer.cornerRadius = 14;
            b.layer.cornerCurve = kCACornerCurveContinuous;
            [b setTitle:[names[(NSUInteger)i] substringToIndex:1] forState:UIControlStateNormal];
            b.tintColor = UIColor.whiteColor;
            b.titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
            b.accessibilityLabel = names[(NSUInteger)i];
            [b addTarget:self action:@selector(iconTapped) forControlEvents:UIControlEventTouchUpInside];
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(b.frame.origin.x - 10, CGRectGetMaxY(b.frame) + 4, icon + 20, 14)];
            label.text = names[(NSUInteger)i];
            label.textColor = UIColor.whiteColor;
            label.font = [UIFont systemFontOfSize:11];
            label.textAlignment = NSTextAlignmentCenter;
            [list addSubview:b];
            [list addSubview:label];
            if (page == 0 && i == 0) _firstIcon = b;
        }
        [_folder addPage:list];
    }
    [root addSubview:_folder];
    UIView *dock = [[UIView alloc] initWithFrame:CGRectMake(12, s.height - 110, s.width - 24, 92)];
    dock.backgroundColor = [UIColor colorWithWhite:1 alpha:0.22];
    dock.layer.cornerRadius = 30;
    dock.userInteractionEnabled = NO;
    [root addSubview:dock];
    self.view = root;
}

- (void)iconTapped {
    _iconTaps++;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_steps) return;
    [self buildWindows];
    _steps = [NSMutableArray array];
    [self buildScript];
    [self next];
}

- (UIWindow *)windowWithLevel:(UIWindowLevel)level root:(UIViewController *)root class:(Class)cls {
    UIWindowScene *scene = self.view.window.windowScene;
    UIWindow *w = [[cls alloc] initWithWindowScene:scene];
    w.frame = scene.screen.bounds;
    w.windowLevel = level;
    w.rootViewController = root;
    w.backgroundColor = UIColor.clearColor;
    return w;
}

- (void)buildWindows {
    // The system wallpaper (behind everything), Home and Lock variants.
    UIViewController *wallpaperRoot = [[UIViewController alloc] init];
    _wallpaperWindow = [self windowWithLevel:UIWindowLevelNormal - 10 root:wallpaperRoot class:[_SBWallpaperWindow class]];
    UIImageView *home = [[UIImageView alloc] initWithImage:WallpaperImage(@"System wallpaper (Home Screen)", 0.58)];
    UIImageView *lock = [[UIImageView alloc] initWithImage:WallpaperImage(@"System wallpaper (Lock Screen)", 0.95)];
    for (UIImageView *v in @[ home, lock ]) {
        v.frame = _wallpaperWindow.bounds;
        v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [wallpaperRoot.view addSubview:v];
    }
    lock.hidden = YES;
    gHomeWallpaper = home;
    gLockWallpaper = lock;
    _wallpaperWindow.hidden = NO;

    // The Lock Screen (Cover Sheet): clock and a notification over the Lock wallpaper.
    UIViewController *coverRoot = [[UIViewController alloc] init];
    coverRoot.view.backgroundColor = UIColor.clearColor;
    UILabel *time = [[UILabel alloc] initWithFrame:CGRectMake(0, 120, coverRoot.view.bounds.size.width, 100)];
    time.text = @"9:41";
    time.font = [UIFont systemFontOfSize:96 weight:UIFontWeightSemibold];
    time.textColor = UIColor.whiteColor;
    time.textAlignment = NSTextAlignmentCenter;
    time.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [coverRoot.view addSubview:time];
    UIView *note = [[UIView alloc] initWithFrame:CGRectMake(16, 520, coverRoot.view.bounds.size.width - 32, 72)];
    note.backgroundColor = [UIColor colorWithWhite:1 alpha:0.25];
    note.layer.cornerRadius = 18;
    [coverRoot.view addSubview:note];
    _coverWindow = [self windowWithLevel:1100 root:coverRoot class:[SBCoverSheetWindow class]];
    _coverWindow.hidden = YES;

    // An app in front (opaque).
    UIViewController *appRoot = [[UIViewController alloc] init];
    appRoot.view.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *appLabel = [[UILabel alloc] initWithFrame:appRoot.view.bounds];
    appLabel.text = @"An app is open";
    appLabel.textAlignment = NSTextAlignmentCenter;
    [appRoot.view addSubview:appLabel];
    _appWindow = [self windowWithLevel:500 root:appRoot class:[UIWindow class]];
    _appWindow.hidden = YES;

    // Settings.
    _settingsNav = [[UINavigationController alloc] initWithRootViewController:[[UIViewController alloc] init]];
    _settingsNav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _settingsWindow = [self windowWithLevel:3000 root:_settingsNav class:[UIWindow class]];
    _settingsWindow.backgroundColor = UIColor.blackColor;
    _settingsWindow.hidden = YES;

    // Caption (never interactive).
    UIViewController *captionRoot = [[UIViewController alloc] init];
    UILabel *banner = [[UILabel alloc] init];
    banner.text = @"PREVIEW · iOS Simulator · stand-in SpringBoard · NOT a device result";
    banner.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    banner.textAlignment = NSTextAlignmentCenter;
    banner.backgroundColor = [UIColor colorWithRed:1 green:0.71 blue:0.28 alpha:0.92];
    _caption = [[UILabel alloc] init];
    _caption.numberOfLines = 2;
    _caption.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightMedium];
    _caption.textColor = UIColor.whiteColor;
    _caption.textAlignment = NSTextAlignmentCenter;
    _caption.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    for (UILabel *l in @[ banner, _caption ]) {
        l.translatesAutoresizingMaskIntoConstraints = NO;
        [captionRoot.view addSubview:l];
    }
    UILayoutGuide *safe = captionRoot.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [banner.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [banner.leadingAnchor constraintEqualToAnchor:captionRoot.view.leadingAnchor],
        [banner.trailingAnchor constraintEqualToAnchor:captionRoot.view.trailingAnchor],
        [_caption.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [_caption.leadingAnchor constraintEqualToAnchor:captionRoot.view.leadingAnchor],
        [_caption.trailingAnchor constraintEqualToAnchor:captionRoot.view.trailingAnchor],
        [_caption.heightAnchor constraintEqualToConstant:36],
    ]];
    captionRoot.view.userInteractionEnabled = NO;
    _captionWindow = [self windowWithLevel:4000 root:captionRoot class:[UIWindow class]];
    _captionWindow.userInteractionEnabled = NO;
    _captionWindow.hidden = NO;

#ifdef HAC_WITH_NEXUS
    UIViewController *nexusRoot = [[UIViewController alloc] init];
    nexusRoot.view.backgroundColor = UIColor.clearColor;
    _nexusWindow = [self windowWithLevel:1000 root:nexusRoot class:[UIWindow class]];
    _nexusWindow.hidden = NO;
    _nexusStore = [[HCGUserDefaultsKeyValueStore alloc] initWithSuiteName:@"com.hakmicapitalgroup.animationcenter.nexus-preview"];
    [_nexusStore removeAllValues];
    _nexusLauncher = [[HCGPreviewLauncher alloc] init];
    _nexusModel = [[HCGNexusModel alloc] initWithStore:_nexusStore notifier:nil launcher:_nexusLauncher];
    _nexusEnvironment = [[HCGPreviewEnvironment alloc] initWithHostViewController:nexusRoot];
    _nexusOverlay = [[HCGOverlayController alloc] initWithModel:_nexusModel environment:_nexusEnvironment];
    HCGSystemSignals signals;
    signals.deviceLocked = HCGTriStateNo;
    signals.coverSheetVisible = HCGTriStateNo;
    signals.screenBlanked = HCGTriStateNo;
    [_nexusOverlay updateSystemSignals:signals];
#endif
}

#pragma mark Steps

- (void)state:(NSString *)name caption:(NSString *)caption {
    _caption.text = caption;
    Say(@"HAC-PREVIEW-STATE %@ | home=%@ | lock=%@", name, Rendering(HACStatusKeyHome), Rendering(HACStatusKeyLock));
}

- (void)shot:(NSString *)name {
    [CATransaction flush];
    // Handshake with scripts/preview.sh: it takes the Simulator screenshot, then
    // creates Documents/shot-ack/<name>. Hold this exact state until then.
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *ack = [[docs stringByAppendingPathComponent:@"shot-ack"] stringByAppendingPathComponent:name];
    Say(@"HAC-PREVIEW-SHOT %@", name);
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:20];
    while (![[NSFileManager defaultManager] fileExistsAtPath:ack] && [limit timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    if (![[NSFileManager defaultManager] fileExistsAtPath:ack]) Say(@"HAC-PREVIEW-NOTE no screenshot ack for %@", name);
}

- (void)next {
    if (!_steps.count) return;
    void (^step)(void) = _steps.firstObject;
    [_steps removeObjectAtIndex:0];
    step();
}

- (void)setPrefs:(NSDictionary *)values {
    for (NSString *key in values) {
        id v = values[key];
        CFPreferencesSetAppValue((__bridge CFStringRef)key, v == [NSNull null] ? NULL : (__bridge CFPropertyListRef)v,
                                 (__bridge CFStringRef)HACPreferencesDomain);
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)HACPreferencesDomain);
    [HACPreferences postChanged];
}

- (void)setLocked:(BOOL)locked {
    gLockWallpaper.hidden = !locked; // SpringBoard shows the Lock variant while locked
    gHomeWallpaper.hidden = locked;
    _coverWindow.hidden = !locked;
    PostState(HAC_LOCKSTATE_NOTIFICATION, locked ? 1 : 0);
}

- (void)setScreenOn:(BOOL)on {
    PostState(HAC_BLANKED_NOTIFICATION, on ? 0 : 1);
}

- (void)pressAlertAction:(NSString *)title {
    UIViewController *top = _settingsNav.presentedViewController;
    if (![top isKindOfClass:[UIAlertController class]]) return;
    for (UIAlertAction *action in ((UIAlertController *)top).actions) {
        if (![action.title isEqualToString:title]) continue;
        void (^handler)(UIAlertAction *) = [action valueForKey:@"handler"];
        [top dismissViewControllerAnimated:NO
                                completion:^{
                                    if (handler) handler(action);
                                }];
        return;
    }
}

- (void)dismissAlerts {
    if (_settingsNav.presentedViewController) [_settingsNav dismissViewControllerAnimated:NO completion:nil];
}

- (BOOL)viewIsIndexZero:(UIView *)view in:(UIView *)container {
    return view.superview == container && container.subviews.firstObject == view;
}

- (void)buildScript {
    __weak HACPreviewController *weakSelf = self;
// Steps fire from run-loop TIMERS, not dispatch_after: a block running on the
// main dispatch queue blocks every other main-queue block (the importer's and
// the AI provider's completions) until it returns, so WAIT_UNTIL could never
// see them finish. A timer callback is not on the main queue, so the nested
// run loop in WAIT_UNTIL drains it.
#define STEP(delay, ...)                                                                                   \
    [_steps addObject:^{                                                                                   \
        [NSTimer scheduledTimerWithTimeInterval:(delay)                                                    \
                                        repeats:NO                                                         \
                                          block:^(NSTimer *timer_) {                                       \
                                              HACPreviewController *self = weakSelf;                       \
                                              if (!self) return;                                           \
                                              @try {                                                       \
                                                  __VA_ARGS__;                                             \
                                              } @catch (NSException * e) {                                 \
                                                  Check(NO, [NSString stringWithFormat:@"exception: %@ — %@", e.name, e.reason]); \
                                              }                                                            \
                                              [self next];                                                 \
                                          }];                                                              \
    }]
#define WAIT_UNTIL(timeout, cond)                                                                          \
    do {                                                                                                   \
        NSDate *limit_ = [NSDate dateWithTimeIntervalSinceNow:(timeout)];                                   \
        while (!(cond) && [limit_ timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; \
    } while (0)

    // ---- 0. Before anything is enabled: the system wallpaper only ----------------
    STEP(1.5, {
        Check(ViewsIdentified(@"HCGAnimationCenter").count == 0, @"off after installation: no background views anywhere");
        Check([HACControllerPreviewStatus()[HACStatusKeyState] isEqualToString:HACEngineStateDisabled], @"engine state: disabled");
        [self state:@"00-off" caption:@"Installed, off: the system wallpaper shows"];
        [self shot:@"00-off-system-wallpaper"];
    });

    // ---- 1. Settings: the real Settings bundle ---------------------------------
    __block UIViewController *settingsRoot = nil;
    STEP(1.5, {
        void *prefs = dlopen("/System/Library/PrivateFrameworks/Preferences.framework/Preferences", RTLD_NOW | RTLD_GLOBAL);
        Check(prefs != NULL, @"Preferences.framework loaded from the Simulator runtime");
        NSBundle *bundle = [NSBundle bundleWithPath:[NSBundle.mainBundle pathForResource:@"HCGAnimationCenterPrefs" ofType:@"bundle"]];
        NSError *error = nil;
        Check([bundle loadAndReturnError:&error], [NSString stringWithFormat:@"Settings bundle loads (%@)", error.localizedDescription ?: @"ok"]);
        settingsRoot = [[bundle.principalClass alloc] init];
        Check([NSStringFromClass([settingsRoot class]) isEqualToString:@"HACRootListController"], @"principal class HACRootListController");
        [self->_settingsNav setViewControllers:@[ settingsRoot ] animated:NO];
        self->_settingsWindow.hidden = NO;
        [settingsRoot loadViewIfNeeded];
        NSArray *specifiers = [settingsRoot valueForKey:@"specifiers"];
        Check(specifiers.count >= 25, [NSString stringWithFormat:@"root page has its rows (%lu specifiers)", (unsigned long)specifiers.count]);
        [self state:@"01-settings-root" caption:@"Settings › HCG Animation Center"];
        [self shot:@"01-settings-root"];
    });
    __block HACLibraryViewController *library = nil;
    STEP(2.0, {
        NSURL *source = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"import"];
        [[NSFileManager defaultManager] createDirectoryAtURL:source withIntermediateDirectories:YES attributes:nil error:NULL];
        NSURL *video = [source URLByAppendingPathComponent:@"Ocean Waves.mov"];
        NSURL *gif = [source URLByAppendingPathComponent:@"Neon Pulse.gif"];
        Check(HACWriteTestVideo(video, CGSizeMake(720, 1280), 6, 0.55, YES, NULL), @"generated a 6 s 720×1280 video with sound");
        Check(HACWriteTestGIF(gif, CGSizeMake(240, 360), @[ @0.12, @0.12, @0.12, @0.12, @0.12, @0.12 ], NULL), @"generated a 6-frame GIF");
        NSDictionary *bad = HACWriteBadMedia([source URLByAppendingPathComponent:@"bad"], video);
        library = [[NSClassFromString(@"HACLibraryViewController") alloc] initBrowsing];
        [self->_settingsNav pushViewController:library animated:NO];
        __block BOOL finished = NO;
        void (^done)(NSUInteger, NSArray *) = ^(NSUInteger imported, NSArray *problems) {
            Check(imported == 2, [NSString stringWithFormat:@"imported the video and the GIF (%lu)", (unsigned long)imported]);
            Check(problems.count == 2, [NSString stringWithFormat:@"refused the damaged file and the still image, with reasons: %@",
                                                                  [problems componentsJoinedByString:@" / "]]);
            finished = YES;
        };
        [library importFileURLs:@[ video, gif, bad[@"random"], bad[@"still"] ] completion:done];
        WAIT_UNTIL(90, finished);
        Check(finished, @"imports finished");
        [[HACLibrary shared] reload];
        for (HCGBackgroundPreset *p in [HACLibrary shared].items) {
            if ([p.origin isEqualToString:@"gif"]) self->_gifItem = p;
            else self->_videoItem = p;
        }
        Check(self->_videoItem && self->_gifItem, @"library has the video and the GIF (with thumbnails)");
        [self state:@"02-library" caption:@"Media Library: imported video + GIF; damaged and still files refused"];
        [self shot:@"02-library"];
    });
    __block HACEditorViewController *editor = nil;
    STEP(2.0, {
        editor = [[NSClassFromString(@"HACEditorViewController") alloc] initWithItem:self->_gifItem preferredSurface:HACSurfaceHome];
        [self->_settingsNav pushViewController:editor animated:NO];
        [editor setScaling:2];
        [editor setZoom:1.5 centerX:0.4 centerY:0.5];
        HCGBackgroundPreset *draft = editor.draft;
        Check(draft.scaling == HCGBackgroundScalingCrop && draft.crop.size.width < 0.99, @"editor: crop with zoom");
        [self state:@"03-editor-crop" caption:@"Editor: live preview on the shared renderer, Crop 1.5×, icon overlay"];
        [self shot:@"03-editor-crop"];
    });
    STEP(1.5, {
        [editor applyToSurface:HACSurfaceHome];
        HACSettings *s = [HACPreferences loadSettings];
        Check([s.homePreset.identifier isEqualToString:self->_gifItem.identifier] && s.homePreset.scaling == HCGBackgroundScalingCrop,
              @"Apply to Home Screen stores the edited preset");
        Check([self->_settingsNav.presentedViewController isKindOfClass:[UIAlertController class]],
              @"master switch off: Settings offers to turn it on");
        [self shot:@"04-apply-offers-enable"];
        [self pressAlertAction:@"Not Now"];
    });
    STEP(1.5, {
        [self->_settingsNav popViewControllerAnimated:NO];
        editor = [[NSClassFromString(@"HACEditorViewController") alloc] initWithItem:self->_videoItem preferredSurface:HACSurfaceLock];
        [self->_settingsNav pushViewController:editor animated:NO];
        [editor applyToSurface:HACSurfaceLock];
        UIAlertController *alert = (UIAlertController *)self->_settingsNav.presentedViewController;
        Check([alert isKindOfClass:[UIAlertController class]] && [alert.title containsString:@"Experimental"],
              @"Lock Screen apply explains it is experimental first");
        [self shot:@"05-lock-experimental"];
        [self pressAlertAction:@"Turn On and Apply"];
    });
    STEP(1.0, {
        HACSettings *s = [HACPreferences loadSettings];
        Check(s.lockEnabled && [s.lockPreset.identifier isEqualToString:self->_videoItem.identifier], @"Lock Screen turned on and assigned");
        [self dismissAlerts];
        [self->_settingsNav popToRootViewControllerAnimated:NO];
    });
    // AI: preview first, nothing stored until an explicit choice.
    __block HACAIViewController *ai = nil;
    STEP(1.0, {
        [HACAIGeneration registerProvider:[[HACPreviewAIProvider alloc] init]];
        ai = [[NSClassFromString(@"HACAIViewController") alloc] init];
        [self->_settingsNav pushViewController:ai animated:NO];
        NSUInteger before = [HACLibrary shared].items.count;
        [ai generateWithPrompt:@"slow violet aurora over dark water"];
        WAIT_UNTIL(60, [NSStringFromClass([self->_settingsNav.topViewController class]) isEqualToString:@"HACEditorViewController"]);
        UIViewController *preview = self->_settingsNav.topViewController;
        Check([preview isKindOfClass:NSClassFromString(@"HACEditorViewController")] && ((HACEditorViewController *)preview).isAIPreview,
              @"AI result opens as a preview");
        [[HACLibrary shared] reload];
        Check([HACLibrary shared].items.count == before, @"AI preview is NOT added to the library or applied");
        HACSettings *s = [HACPreferences loadSettings];
        Check([s.homePreset.identifier isEqualToString:self->_gifItem.identifier], @"assignments unchanged by the preview");
        [self state:@"06-ai-preview" caption:@"AI Backgrounds (local test provider): preview only until you choose"];
        [self shot:@"06-ai-preview"];
    });
    STEP(1.5, {
        UIViewController *preview = self->_settingsNav.topViewController;
        NSUInteger before = [HACLibrary shared].items.count;
        ((void (*)(id, SEL))objc_msgSend)(preview, NSSelectorFromString(@"saveAI"));
        WAIT_UNTIL(60, ([[HACLibrary shared] reload], [HACLibrary shared].items.count == before + 1));
        HCGBackgroundPreset *adopted = [HACLibrary shared].items.firstObject;
        Check([HACLibrary shared].items.count == before + 1 && [adopted.origin isEqualToString:@"ai"] &&
                  [adopted.generator[@"kind"] isEqualToString:@"ai"],
              @"Save to Library adopts it (origin ai, generator recorded)");
        [HACAIGeneration registerProvider:nil];
        [self->_settingsNav popToRootViewControllerAnimated:NO];
        // The user turns it on in Settings (the real switch handler).
        id spec = ((id (*)(id, SEL, id))objc_msgSend)(settingsRoot, NSSelectorFromString(@"specifierForID:"), @"enabled");
        ((void (*)(id, SEL, id, id))objc_msgSend)(settingsRoot, NSSelectorFromString(@"setPreferenceValue:specifier:"), @YES, spec);
        Check([HACPreferences loadSettings].enabled, @"Enable switch written through CFPreferences");
    });
    STEP(2.5, {
        ((void (*)(id, SEL))objc_msgSend)(settingsRoot, NSSelectorFromString(@"reloadSpecifiers"));
        [self state:@"07-settings-enabled" caption:@"Enabled: Status and Now rows come from SpringBoard"];
        [self shot:@"07-settings-enabled"];
    });

    // ---- 2. SpringBoard: Home Screen ---------------------------------------------
    STEP(1.0, {
        self->_settingsWindow.hidden = YES;
        HCGBackgroundView *home = SurfaceView(HACSurfaceHome);
        WAIT_UNTIL(10, PlayerOf(SurfaceView(HACSurfaceHome)).currentItem.status == AVPlayerItemStatusReadyToPlay);
        home = SurfaceView(HACSurfaceHome);
        Check(home && [self viewIsIndexZero:home in:self->_homeWindow], @"Home background is in SBHomeScreenWindow at index 0 (below the icons)");
        Check(home.display == HCGBackgroundDisplayPlaying && PlayerOf(home).rate > 0, @"Home background playing");
        Check(PlayerOf(home).muted, @"muted");
        CGPoint p = [self->_firstIcon convertPoint:CGPointMake(30, 30) toView:self->_homeWindow];
        UIView *hit = [self->_homeWindow hitTest:p withEvent:nil];
        Check(hit == self->_firstIcon, [NSString stringWithFormat:@"icon taps reach the icon (hit %@)", NSStringFromClass([hit class])]);
        Check([home hitTest:CGPointMake(10, 10) withEvent:nil] == nil, @"the background never takes a touch");
        HCGBackgroundView *lock = SurfaceView(HACSurfaceLock);
        Check(!lock || lock.hidden, @"unlocked: the Lock background is hidden");
        [self state:@"10-home-playing" caption:@"Home Screen: GIF background (crop 1.5×) behind the icons"];
        [self shot:@"10-home-playing"];
    });
#ifdef HAC_WITH_HALO
    STEP(0.5, {
        NSArray *halo = ViewsIdentified(@"HCGHaloOverlay");
        UIView *overlay = halo.firstObject;
        Check(halo.count == 1, @"HCG Halo (real controller) drew its border overlay");
        Check(overlay.superview == self->_homeWindow && [self->_homeWindow.subviews indexOfObject:overlay] >
                                                            [self->_homeWindow.subviews indexOfObject:SurfaceView(HACSurfaceHome)],
              @"Halo's border stays above the background in the same window");
    });
#endif
#ifdef HAC_WITH_VORTEX
    STEP(0.5, {
        // A page swipe driven frame by frame; HCG Vortex (real engine) transforms the pages.
        UIScrollView *scroll = self->_folder.scrollView;
        CGFloat w = scroll.bounds.size.width;
        __block BOOL transformed = NO, backgroundSteady = YES;
        HCGBackgroundView *home = SurfaceView(HACSurfaceHome);
        CGRect before = home.frame;
        for (int i = 1; i <= 24; i++) {
            [scroll setContentOffset:CGPointMake(w * i / 24.0, 0) animated:NO];
            [self->_folder layoutIfNeeded];
            for (UIView *list in self->_folder.iconListViews) {
                if (!CATransform3DIsIdentity(list.layer.transform) || !CATransform3DIsIdentity(list.layer.sublayerTransform)) transformed = YES;
                for (UIView *sub in list.subviews)
                    if (!CATransform3DIsIdentity(sub.layer.transform)) transformed = YES;
            }
            if (!CGRectEqualToRect(home.frame, before) || ![self viewIsIndexZero:home in:self->_homeWindow]) backgroundSteady = NO;
            if (i == 12) {
                [CATransaction flush];
                [self state:@"11-vortex-mid-swipe" caption:@"HCG Vortex (real engine) mid-swipe over the background"];
                [self shot:@"11-vortex-mid-swipe"];
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
            } else {
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]];
            }
        }
        Check(transformed, @"HCG Vortex transformed the icon pages during the swipe");
        Check(backgroundSteady, @"the background did not move or change order during the swipe");
        Check(PlayerOf(home).rate > 0, @"still playing after the swipe");
        [scroll setContentOffset:CGPointZero animated:NO];
    });
#endif
#ifdef HAC_WITH_NEXUS
    STEP(1.0, {
        HCGSettings *settings = self->_nexusModel.settings;
        settings.enabled = YES;
        settings.animationsEnabled = YES;
        [self->_nexusModel saveSettings:settings];
        [self->_nexusOverlay simulateHandleActivation];
    });
    STEP(2.0, {
        Check([self->_nexusOverlay isPanelOnScreen], @"HCG Nexus (real panel) open over the Home Screen");
        HCGBackgroundView *home = SurfaceView(HACSurfaceHome);
        Check([self viewIsIndexZero:home in:self->_homeWindow] && PlayerOf(home).rate > 0, @"background unaffected under the Nexus panel");
        [self state:@"12-nexus-open" caption:@"HCG Nexus panel (real) open; background keeps playing below"];
        [self shot:@"12-nexus-open"];
        [self->_nexusOverlay simulateOutsideTap];
    });
#endif
    STEP(1.0, {
        gFront = [[SBApplication alloc] init];
        gFront.bundleIdentifier = @"com.example.app";
        self->_appWindow.hidden = NO;
        [(SpringBoard *)UIApplication.sharedApplication frontDisplayDidChange:gFront];
        HCGBackgroundView *home = SurfaceView(HACSurfaceHome);
        Check(PlayerOf(home).rate == 0 && [Rendering(HACStatusKeyHome) containsString:@"app in front"], @"app in front: paused");
        [self state:@"13-app-in-front" caption:@"An app is open: Home background paused"];
        [self shot:@"13-app-in-front"];
    });
    STEP(1.0, {
        gFront = nil;
        self->_appWindow.hidden = YES;
        [(SpringBoard *)UIApplication.sharedApplication frontDisplayDidChange:nil];
        Check(PlayerOf(SurfaceView(HACSurfaceHome)).rate > 0, @"back on the Home Screen: playing again");
    });

    // ---- 3. Lock Screen ------------------------------------------------------------
    STEP(1.0, {
        [self setLocked:YES];
    });
    STEP(2.0, {
        HCGBackgroundView *lock = SurfaceView(HACSurfaceLock);
        WAIT_UNTIL(10, PlayerOf(SurfaceView(HACSurfaceLock)).currentItem.status == AVPlayerItemStatusReadyToPlay);
        lock = SurfaceView(HACSurfaceLock);
        Check(lock.superview == gLockWallpaper, @"Lock background on top of the Lock wallpaper view (wallpaper placement)");
        Check(lock.display == HCGBackgroundDisplayPlaying && PlayerOf(lock).rate > 0, @"Lock background playing while locked");
        Check(PlayerOf(SurfaceView(HACSurfaceHome)).rate == 0 || !SurfaceView(HACSurfaceHome).playerActive, @"Home paused while locked");
        [self state:@"20-lock-playing" caption:@"Lock Screen: video background under the clock and notifications"];
        [self shot:@"20-lock-playing"];
    });
    STEP(1.0, {
        [self setScreenOn:NO];
    });
    STEP(1.0, {
        Check(PlayerOf(SurfaceView(HACSurfaceLock)).rate == 0, @"screen off: Lock paused");
        Check([Rendering(HACStatusKeyLock) containsString:@"screen off"], [NSString stringWithFormat:@"status says why: %@", Rendering(HACStatusKeyLock)]);
        [self state:@"21-screen-off" caption:@"Screen off: everything paused"];
    });
    STEP(8.5, {
        Check(!SurfaceView(HACSurfaceLock).playerActive && !SurfaceView(HACSurfaceHome).playerActive,
              @"after 8 s hidden: every decoder released (memory)");
        [self setScreenOn:YES];
    });
    STEP(1.5, {
        WAIT_UNTIL(10, PlayerOf(SurfaceView(HACSurfaceLock)).rate > 0);
        Check(PlayerOf(SurfaceView(HACSurfaceLock)).rate > 0, @"screen on again: Lock plays again");
        [self setPrefs:@{HACKeyLockPlacement : @"coverSheet"}];
    });
    STEP(1.5, {
        HCGBackgroundView *lock = SurfaceView(HACSurfaceLock);
        Check([self viewIsIndexZero:lock in:self->_coverWindow], @"Cover Sheet placement: index 0 of SBCoverSheetWindow");
        [self state:@"22-lock-coversheet" caption:@"Lock Screen placement: Cover Sheet window"];
        [self shot:@"22-lock-coversheet"];
        [self setPrefs:@{HACKeyLockPlacement : @"automatic"}];
        [self setLocked:NO];
    });
    STEP(1.5, {
        HCGBackgroundView *lock = SurfaceView(HACSurfaceLock);
        Check(lock.hidden && !lock.playerActive, @"unlocked: Lock background hidden, no decoder");
        WAIT_UNTIL(10, PlayerOf(SurfaceView(HACSurfaceHome)).rate > 0);
        Check(PlayerOf(SurfaceView(HACSurfaceHome)).rate > 0, @"unlocked: Home plays");
    });

    // ---- 4. Damaged media, disable, recovery -----------------------------------------
    STEP(1.0, {
        NSURL *media = [HACPreferences mediaFolder];
        NSURL *broken = [media URLByAppendingPathComponent:@"broken.mov"];
        NSMutableData *noise = [NSMutableData dataWithLength:32 * 1024];
        arc4random_buf(noise.mutableBytes, noise.length);
        [noise writeToURL:broken atomically:YES];
        HCGBackgroundPreset *bad = [self->_videoItem copy];
        bad.identifier = [NSUUID UUID].UUIDString;
        bad.mediaFile = @"broken.mov";
        [self setPrefs:@{HACKeyHomePreset : [bad dictionaryRepresentation]}];
    });
    STEP(3.0, {
        HCGBackgroundView *home = SurfaceView(HACSurfaceHome);
        Check(home.mediaFailed && home.display == HCGBackgroundDisplayStill && !home.playerActive,
              [NSString stringWithFormat:@"damaged video: static fallback shown (%@)", Rendering(HACStatusKeyHome)]);
        [self state:@"30-damaged-still" caption:@"Damaged video: the still image is shown instead"];
        [self shot:@"30-damaged-still"];
        [self setPrefs:@{HACKeyHomePreset : [self->_gifItem dictionaryRepresentation]}];
    });
    STEP(2.0, {
        [self setPrefs:@{HACKeyEnabled : @NO}];
    });
    STEP(1.5, {
        Check(ViewsIdentified(@"HCGAnimationCenter").count == 0, @"disabled: every background view removed");
        Check(!gHomeWallpaper.hidden && gHomeWallpaper.subviews.count == 0, @"the system wallpaper is untouched and visible");
#ifdef HAC_WITH_HALO
        Check(ViewsIdentified(@"HCGHaloOverlay").count == 1, @"HCG Halo unaffected by disabling Animation Center");
#endif
        [self state:@"31-disabled" caption:@"Disabled: the normal wallpaper shows at once (no respring)"];
        [self shot:@"31-disabled-system-wallpaper"];
        [self setPrefs:@{HACKeyEnabled : @YES}];
    });
    STEP(2.0, {
        Check(SurfaceView(HACSurfaceHome).superview == self->_homeWindow, @"re-enabled: background back");
        [self setPrefs:@{HACKeyHomePreset : [NSNull null]}];
    });
    STEP(1.5, {
        Check(SurfaceView(HACSurfaceHome) == nil && ViewsIdentified(@"HCGAnimationCenter.home").count == 0,
              @"no Home background assigned: system wallpaper");
        Say(@"HAC-PREVIEW-STATUS %@", HACControllerPreviewStatus());
        Say(@"HAC-PREVIEW-DONE failures=%d", gFailures);
    });
#undef STEP
#undef WAIT_UNTIL
}

- (void)setHomeWindow:(SBHomeScreenWindow *)window {
    _homeWindow = window;
}

@end

@interface HACPreviewAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation HACPreviewAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    HACPreviewController *root = [HACPreviewController new];
    SBHomeScreenWindow *window = [[SBHomeScreenWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    window.backgroundColor = UIColor.clearColor;
    window.rootViewController = root;
    [root setHomeWindow:window];
    self.window = window;
    [window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *store = [docs stringByAppendingPathComponent:@"HCGAnimationCenter"];
        [[NSFileManager defaultManager] removeItemAtPath:store error:NULL];
        [[NSFileManager defaultManager] removeItemAtPath:[docs stringByAppendingPathComponent:@"shot-ack"] error:NULL];
        [HACPreferences setStoreRootForTesting:store];
        // Fresh preferences: the package's defaults (off).
        CFArrayRef keys = CFPreferencesCopyKeyList((__bridge CFStringRef)HACPreferencesDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if (keys) {
            CFPreferencesSetMultiple(NULL, keys, (__bridge CFStringRef)HACPreferencesDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            CFRelease(keys);
        }
        [HACPreferences setConsecutiveUnstableLaunches:0];
        PostState(HAC_LOCKSTATE_NOTIFICATION, 0);
        PostState(HAC_BLANKED_NOTIFICATION, 0);
        Say(@"HAC-PREVIEW-START HCG Animation Center %s (store %@)", HAC_VERSION, store);
        HACControllerBootstrap(HACInstallHook); // as the tweak's %ctor does
#ifdef HAC_WITH_HALO
        NSMutableDictionary *reset = [NSMutableDictionary dictionary];
        for (NSString *key in [HaloPreferences allKeys]) reset[key] = [NSNull null];
        [HaloPreferences writeValues:reset];
        [HaloPreferences writeValues:@{HaloKeyEnabled : @YES, HaloKeyMode : @"flow", HaloKeyThickness : @4.0}];
        [HaloPreferences setConsecutiveUnstableLaunches:0];
        HaloControllerBootstrap(HaloInstallHook);
        Say(@"HAC-PREVIEW-START with HCG Halo %s (real controller)", HALO_VERSION);
#endif
#ifdef HAC_WITH_VORTEX
        CFPreferencesSetAppValue(CFSTR("enabled"), kCFBooleanTrue, CFSTR("com.hakmicapitalgroup.vortex"));
        CFPreferencesSetAppValue(CFSTR("preset"), CFSTR("vertical-rise"), CFSTR("com.hakmicapitalgroup.vortex"));
        CFPreferencesAppSynchronize(CFSTR("com.hakmicapitalgroup.vortex"));
        [VortexPreferences setConsecutiveUnstableLaunches:0];
        Method m = class_getInstanceMethod([NSBundle class], @selector(bundleIdentifier));
        IMP real = method_setImplementation(m, (IMP)VortexBundleIdentifier);
        VortexCoreBootstrap(VortexInstallHooks);
        method_setImplementation(m, real);
        Say(@"HAC-PREVIEW-START with HCG Vortex %s (real engine)", VORTEX_VERSION);
#endif
        return UIApplicationMain(argc, argv, @"SpringBoard", NSStringFromClass([HACPreviewAppDelegate class]));
    }
}
