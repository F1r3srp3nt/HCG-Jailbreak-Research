//
//  PortalStandIns.m
//  HCG Portal — Simulator stand-ins (PREVIEW / TESTS ONLY). See the header.
//

#import "PortalStandIns.h"

#import <objc/runtime.h>

#include <notify.h>

void PSIPostState(const char *name, uint64_t value) {
    // Keep one registration per name open for the life of the process: notifyd
    // drops a name's state when its last registration is cancelled, and
    // SpringBoard (the real publisher) keeps its registration too.
    static NSMutableDictionary<NSString *, NSNumber *> *tokens;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tokens = [NSMutableDictionary dictionary];
    });
    NSString *key = @(name);
    int token = 0;
    if (tokens[key]) {
        token = tokens[key].intValue;
    } else {
        if (notify_register_check(name, &token) != NOTIFY_STATUS_OK) return;
        tokens[key] = @(token);
    }
    notify_set_state(token, value);
    notify_post(name);
}

@implementation SBLockScreenUnlockRequest
@end

@implementation SBDefaultCoverSheetContext
- (SBLockScreenUnlockRequest *)createUnlockRequest {
    SBLockScreenUnlockRequest *r = [[SBLockScreenUnlockRequest alloc] init];
    r.fromContext = YES;
    return r;
}
@end

@implementation CSMainPageContentViewController
- (void)loadView {
    self.view = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.view.backgroundColor = UIColor.clearColor;
}
@end

@implementation SBFLockScreenDateView
@end

@implementation CSComplicationContainerViewController
- (void)loadView {
    self.view = [[UIView alloc] initWithFrame:CGRectZero];
}
@end

@implementation NCNotificationListCell
@end

@implementation CSAdjunctItemView
@end

@implementation CSQuickActionsButton
@end

static UILabel *PSILabel(NSString *text, CGFloat size, UIFontWeight weight, CGFloat alpha) {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [UIFont systemFontOfSize:size weight:weight];
    l.textColor = [UIColor colorWithWhite:1 alpha:alpha];
    return l;
}

static void PSIPlatter(UIView *v, CGFloat radius) {
    v.backgroundColor = [UIColor colorWithWhite:1 alpha:0.17];
    v.layer.cornerRadius = radius;
    v.layer.borderWidth = 0.5;
    v.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
}

static NSUInteger gOriginalWillAppearCalls;

void PSIHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original) {
    Method inherited = class_getInstanceMethod(cls, selector);
    if (!inherited) return;
    if (class_addMethod(cls, selector, replacement, method_getTypeEncoding(inherited))) {
        if (original) *original = method_getImplementation(inherited); // the superclass's
    } else {
        IMP previous = method_setImplementation(class_getInstanceMethod(cls, selector), replacement);
        if (original) *original = previous;
    }
}

@implementation CSCoverSheetViewController {
    CSMainPageContentViewController *_main;
    CSComplicationContainerViewController *_widgets;
    SBFLockScreenDateView *_date;
    SBDefaultCoverSheetContext *_context;
    NSMutableArray<NCNotificationListCell *> *_cells;
    CSAdjunctItemView *_media;
    CSQuickActionsButton *_flashlight, *_camera;
    UILabel *_caption;
    NSUInteger _notificationCount;
    BOOL _showsMedia;
}

+ (NSUInteger)originalWillAppearCalls {
    return gOriginalWillAppearCalls;
}

- (void)viewWillAppear:(BOOL)animated {
    gOriginalWillAppearCalls++;
    [super viewWillAppear:animated];
}

- (instancetype)init {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _main = [[CSMainPageContentViewController alloc] init];
        _mainPageAvailable = YES;
        _widgets = [[CSComplicationContainerViewController alloc] init];
        _context = [[SBDefaultCoverSheetContext alloc] init];
        _cells = [NSMutableArray array];
    }
    return self;
}

- (CSMainPageContentViewController *)mainPageContentViewController {
    return _mainPageAvailable ? _main : nil;
}

- (void)rebuildMainPage {
    CSMainPageContentViewController *fresh = [[CSMainPageContentViewController alloc] init];
    UIView *old = _main.view;
    [self addChildViewController:fresh];
    fresh.view.frame = old.frame;
    // The widgets controller moves with its view (UIKit requires the view's controller
    // hierarchy to match); its new parent is the new main page.
    [_widgets willMoveToParentViewController:nil];
    [_widgets.view removeFromSuperview];
    [_widgets removeFromParentViewController];
    for (UIView *v in [old.subviews copy]) {
        if ([NSStringFromClass([v class]) hasPrefix:@"Portal"]) continue;
        [fresh.view addSubview:v];
    }
    [fresh addChildViewController:_widgets];
    [fresh.view addSubview:_widgets.view];
    [_widgets didMoveToParentViewController:fresh];
    [self.view insertSubview:fresh.view aboveSubview:old];
    [fresh didMoveToParentViewController:self];
    [_main willMoveToParentViewController:nil];
    [old removeFromSuperview];
    [_main removeFromParentViewController];
    _main = fresh;
    [self.view setNeedsLayout];
}
- (CSComplicationContainerViewController *)complicationContainerViewController {
    return _widgets;
}
- (SBFLockScreenDateView *)dateView {
    return _date;
}
- (SBDefaultCoverSheetContext *)coverSheetContext {
    return _context;
}
- (NSArray<NCNotificationListCell *> *)notificationCells {
    return [_cells copy];
}
- (CSAdjunctItemView *)mediaView {
    return _showsMedia ? _media : nil;
}
- (CSQuickActionsButton *)flashlight {
    return _flashlight;
}
- (CSQuickActionsButton *)camera {
    return _camera;
}
- (UILabel *)caption {
    return _caption;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *v = self.view;
    CAGradientLayer *wallpaper = [CAGradientLayer layer];
    wallpaper.frame = v.bounds;
    wallpaper.colors = @[
        (id)[UIColor colorWithRed:0.04 green:0.06 blue:0.16 alpha:1].CGColor,
        (id)[UIColor colorWithRed:0.11 green:0.07 blue:0.27 alpha:1].CGColor,
        (id)[UIColor colorWithRed:0.02 green:0.14 blue:0.24 alpha:1].CGColor,
    ];
    wallpaper.startPoint = CGPointMake(0.15, 0);
    wallpaper.endPoint = CGPointMake(0.85, 1);
    [v.layer addSublayer:wallpaper];

    [self addChildViewController:_main];
    _main.view.frame = v.bounds;
    [v addSubview:_main.view];
    [_main didMoveToParentViewController:self];
    UIView *page = _main.view;
    CGFloat W = v.bounds.size.width, H = v.bounds.size.height;
    CGFloat top = 59;

    _date = [[SBFLockScreenDateView alloc] initWithFrame:CGRectMake(0, top + 8, W, 132)];
    UILabel *date = PSILabel(@"Wednesday 18 November", 20, UIFontWeightSemibold, 0.85);
    date.textAlignment = NSTextAlignmentCenter;
    date.frame = CGRectMake(0, 0, W, 26);
    [_date addSubview:date];
    UILabel *clock = PSILabel(@"9:41", 92, UIFontWeightSemibold, 0.95);
    clock.textAlignment = NSTextAlignmentCenter;
    clock.frame = CGRectMake(0, 24, W, 104);
    [_date addSubview:clock];
    [page addSubview:_date];

    _widgets.view.frame = CGRectMake(40, top + 146, W - 80, 58);
    CGFloat ww = (W - 80 - 20) / 3;
    NSArray *widgetSymbols = @[ @"battery.100", @"cloud.sun.fill", @"calendar" ];
    for (int i = 0; i < 3; i++) {
        UIView *w = [[UIView alloc] initWithFrame:CGRectMake(i * (ww + 10), 0, ww, 58)];
        PSIPlatter(w, 18);
        UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:widgetSymbols[i]]];
        iv.tintColor = UIColor.whiteColor;
        iv.center = CGPointMake(ww / 2, 29);
        [w addSubview:iv];
        [_widgets.view addSubview:w];
    }
    [self addChildViewController:_widgets];
    [page addSubview:_widgets.view];
    [_widgets didMoveToParentViewController:self];

    _media = [[CSAdjunctItemView alloc] initWithFrame:CGRectZero];
    PSIPlatter(_media, 24);
    UILabel *song = PSILabel(@"Now Playing", 15, UIFontWeightSemibold, 0.92);
    song.frame = CGRectMake(18, 16, 240, 20);
    [_media addSubview:song];
    UILabel *artist = PSILabel(@"Media controls", 14, UIFontWeightRegular, 0.6);
    artist.frame = CGRectMake(18, 38, 240, 18);
    [_media addSubview:artist];
    UIImageView *play = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"play.fill"]];
    play.tintColor = UIColor.whiteColor;
    play.frame = CGRectMake(W / 2 - 22, 110, 20, 22);
    [_media addSubview:play];
    _media.hidden = YES;
    [page addSubview:_media];

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium];
    _flashlight = [[CSQuickActionsButton alloc] initWithFrame:CGRectMake(46, H - 34 - 50 - 22, 50, 50)];
    _camera = [[CSQuickActionsButton alloc] initWithFrame:CGRectMake(W - 46 - 50, H - 34 - 50 - 22, 50, 50)];
    NSArray *symbols = @[ @"flashlight.off.fill", @"camera.fill" ];
    NSArray *buttons = @[ _flashlight, _camera ];
    for (NSUInteger i = 0; i < 2; i++) {
        CSQuickActionsButton *b = buttons[i];
        PSIPlatter(b, 25);
        UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbols[i] withConfiguration:cfg]];
        iv.tintColor = UIColor.whiteColor;
        iv.center = CGPointMake(25, 25);
        iv.userInteractionEnabled = NO;
        [b addSubview:iv];
        b.accessibilityLabel = i == 0 ? @"Flashlight" : @"Camera";
        [v addSubview:b];
    }
    UIView *home = [[UIView alloc] initWithFrame:CGRectMake((W - 134) / 2, H - 13, 134, 5)];
    home.backgroundColor = [UIColor colorWithWhite:1 alpha:0.85];
    home.layer.cornerRadius = 2.5;
    [v addSubview:home];

    _caption = PSILabel(@"", 11, UIFontWeightMedium, 0.75);
    _caption.textAlignment = NSTextAlignmentCenter;
    _caption.numberOfLines = 2;
    _caption.frame = CGRectMake(16, H - 34 - 18, W - 32, 30);
    _caption.userInteractionEnabled = NO;
    [v addSubview:_caption];
    [self relayoutSamples];
}

- (void)setNotificationCount:(NSUInteger)count {
    _notificationCount = count;
    [self relayoutSamples];
}

- (void)setShowsMedia:(BOOL)shows {
    _showsMedia = shows;
    [self relayoutSamples];
}

- (void)relayoutSamples {
    if (!self.isViewLoaded) return;
    UIView *page = _main.view;
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
    while (_cells.count < _notificationCount) {
        NSArray *apps = @[ @"Messages", @"Calendar", @"Reminders", @"Mail", @"Weather", @"News", @"Fitness", @"Photos" ];
        NCNotificationListCell *cell = [[NCNotificationListCell alloc] initWithFrame:CGRectZero];
        PSIPlatter(cell, 20);
        UIView *icon = [[UIView alloc] initWithFrame:CGRectMake(12, 14, 36, 36)];
        icon.backgroundColor = [UIColor colorWithWhite:1 alpha:0.35];
        icon.layer.cornerRadius = 8;
        [cell addSubview:icon];
        UILabel *title = PSILabel(apps[_cells.count % apps.count], 14, UIFontWeightSemibold, 0.92);
        title.frame = CGRectMake(58, 12, 220, 18);
        [cell addSubview:title];
        UILabel *body = PSILabel(@"Sample notification (stand-in)", 14, UIFontWeightRegular, 0.62);
        body.frame = CGRectMake(58, 32, 260, 18);
        [cell addSubview:body];
        [page addSubview:cell];
        [_cells addObject:cell];
    }
    CGFloat y = H - 34 - 50 - 22 - 18; // iOS 16+: notifications and media grow upwards from the bottom
    _media.hidden = !_showsMedia;
    if (_showsMedia) {
        y -= 160; // the iOS 16+ Lock Screen player, with scrubber and controls
        _media.frame = CGRectMake(10, y, W - 20, 160);
        y -= 10;
    }
    for (NSUInteger i = 0; i < _cells.count; i++) {
        NCNotificationListCell *cell = _cells[i];
        cell.hidden = i >= _notificationCount;
        if (cell.hidden) continue;
        y -= 64;
        cell.frame = CGRectMake(10, y, W - 20, 64);
        y -= 8;
    }
    [self.view setNeedsLayout];
}

@end

#pragma mark - Lock Screen manager

static NSUInteger gLockScreenManagerCalls, gPresentationManagerCalls;

@implementation SBLockScreenManager {
    void (^_pending)(BOOL);
    UIView *_sheet;
}

+ (NSUInteger)sharedInstanceCalls {
    return gLockScreenManagerCalls;
}

+ (instancetype)sharedInstance {
    gLockScreenManagerCalls++;
    return [self standIn];
}

+ (instancetype)standIn {
    static SBLockScreenManager *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[SBLockScreenManager alloc] init];
        shared.uiLocked = YES;
    });
    return shared;
}

- (BOOL)isUILocked {
    return _uiLocked;
}

- (BOOL)hasPendingRequest {
    return _pending != nil;
}

- (BOOL)unlockWithRequest:(id)request completion:(void (^)(BOOL))completion {
    _requestCount++;
    _lastRequest = [request isKindOfClass:[SBLockScreenUnlockRequest class]] ? request : nil;
    switch (_authMode) {
        case PSIAuthRefuse:
            return NO;
        case PSIAuthSucceed: {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(YES);
            });
            return YES;
        }
        case PSIAuthCancel: {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO);
            });
            return YES;
        }
        case PSIAuthHold: {
            _pending = [completion copy];
            [self showSheet];
            return YES;
        }
    }
    return NO;
}

- (void (^)(BOOL))resolvePending:(BOOL)success {
    void (^completion)(BOOL) = _pending;
    _pending = nil;
    [_sheet removeFromSuperview];
    _sheet = nil;
    if (completion) completion(success);
    return completion;
}

/// A clearly labelled stand-in for the system authentication UI (for screenshots).
- (void)showSheet {
    UIView *host = _coverSheetViewController.view;
    if (!host) return;
    _sheet = [[UIView alloc] initWithFrame:host.bounds];
    _sheet.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(40, host.bounds.size.height * 0.30, host.bounds.size.width - 80, 230)];
    panel.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.92];
    panel.layer.cornerRadius = 24;
    UIImageView *face = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"faceid"
                                                                    withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:56]]];
    face.tintColor = UIColor.whiteColor;
    face.center = CGPointMake(panel.bounds.size.width / 2, 70);
    [panel addSubview:face];
    UILabel *title = PSILabel(@"Face ID or Passcode", 18, UIFontWeightSemibold, 1);
    title.textAlignment = NSTextAlignmentCenter;
    title.frame = CGRectMake(0, 120, panel.bounds.size.width, 24);
    [panel addSubview:title];
    UILabel *note = PSILabel(@"SIMULATOR STAND-IN for the system authentication UI.\nOn the phone, iOS shows its own Face ID / "
                             @"passcode screen.",
                             12, UIFontWeightRegular, 0.7);
    note.numberOfLines = 3;
    note.textAlignment = NSTextAlignmentCenter;
    note.frame = CGRectMake(16, 150, panel.bounds.size.width - 32, 60);
    [panel addSubview:note];
    [_sheet addSubview:panel];
    [host addSubview:_sheet];
}

@end

@implementation SBCoverSheetPresentationManager
+ (NSUInteger)sharedInstanceCalls {
    return gPresentationManagerCalls;
}
+ (instancetype)sharedInstance {
    gPresentationManagerCalls++;
    return [self standIn];
}
+ (instancetype)standIn {
    static SBCoverSheetPresentationManager *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[SBCoverSheetPresentationManager alloc] init];
    });
    return shared;
}
- (BOOL)isVisible {
    return _visible;
}
@end

#pragma mark - Proposed Nexus interface (test double)

static BOOL gNexusActive;
static NSUInteger gNexusOpenCount;
static NSString *gNexusLastSource;

@implementation HCGNexusPortalInterface
+ (NSInteger)interfaceVersion {
    return 1;
}
+ (instancetype)activeInterface {
    static HCGNexusPortalInterface *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[HCGNexusPortalInterface alloc] init];
    });
    return gNexusActive ? shared : nil;
}
+ (void)setStandInActive:(BOOL)active {
    gNexusActive = active;
}
+ (NSUInteger)openCount {
    return gNexusOpenCount;
}
+ (NSString *)lastSource {
    return gNexusLastSource;
}
- (BOOL)canOpenPanel {
    return gNexusActive;
}
- (void)openPanelFromSource:(NSString *)source completion:(void (^)(BOOL, NSString *))completion {
    gNexusOpenCount++;
    gNexusLastSource = [source copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(YES, nil);
    });
}
@end
