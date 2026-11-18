//
//  HaloNexusBorderController.m
//  HCG Halo — Hakmi Capital Group
//
//  Sections: preview · status · border target · look (match / presets) ·
//  style (mode, colours, sliders, direction) · effects · reset.
//  Every change is written through the shared HaloPreferences validator, shown
//  in the preview at once, and sent to SpringBoard (sliders: on release).
//

#import "HaloNexusBorderController.h"
#import "HaloColoursController.h"
#import "HaloNexusDefinition.h"
#import "HaloPanelBorderView.h"
#import "HaloPreferences.h"
#import "HaloTheme.h"

#include <notify.h>

static NSString *const kCellID = @"HaloNexusCell";
static NSString *const kEffectsFooter =
    @"Opening Trace: a light travels once around the panel as it opens, then settles (skipped with Reduce Motion). "
    @"Fade With Panel: off makes the border disappear as soon as the panel starts closing. Workspace Pulse: one soft "
    @"swell when you switch workspace. None of these delay the panel.";
static NSString *const kResetFooter = @"Resets the panel border's look and effects to Nexus Signature. The border target "
                                      @"and every screen-edge setting are kept.";

typedef NS_ENUM(NSInteger, HaloNexusSection) {
    HaloNexusSectionStatus,
    HaloNexusSectionTarget,
    HaloNexusSectionLook,
    HaloNexusSectionStyle,
    HaloNexusSectionEffects,
    HaloNexusSectionReset,
};

typedef NS_ENUM(NSInteger, HaloRowKind) {
    HaloRowInfo,
    HaloRowCheck,
    HaloRowSwitch,
    HaloRowChoice,
    HaloRowSlider,
    HaloRowLink,
    HaloRowButton,
};

@interface HaloNexusRow : NSObject
@property (nonatomic) HaloRowKind kind;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, copy) NSString *key;      // preference / appearance key
@property (nonatomic, copy) NSString *value;    // check rows
@property (nonatomic) BOOL on;
@property (nonatomic) BOOL enabled;
@property (nonatomic) double minimum, maximum, current;
@property (nonatomic) BOOL integral;
@property (nonatomic, copy) NSString *unit;
@property (nonatomic, copy) NSArray<NSString *> *choiceTitles, *choiceValues;
@property (nonatomic, copy) void (^action)(void);
@end

@implementation HaloNexusRow
- (instancetype)init {
    if ((self = [super init])) _enabled = YES;
    return self;
}
@end

@interface HaloNexusSliderCell : UITableViewCell
@property (nonatomic, readonly) UISlider *slider;
@property (nonatomic, readonly) UILabel *titleLabel, *valueLabel;
@end

@implementation HaloNexusSliderCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])) {
        _titleLabel = [UILabel new];
        _valueLabel = [UILabel new];
        _slider = [UISlider new];
        _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        _titleLabel.adjustsFontForContentSizeCategory = YES;
        _valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightRegular];
        _valueLabel.textAlignment = NSTextAlignmentRight;
        _titleLabel.textColor = HaloTheme.textPrimary;
        _valueLabel.textColor = HaloTheme.textSecondary;
        _slider.minimumTrackTintColor = HaloTheme.cyan;
        _slider.maximumTrackTintColor = [HaloTheme.deepViolet colorWithAlphaComponent:0.35];
        for (UIView *v in @[ _titleLabel, _valueLabel, _slider ]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:v];
        }
        UILayoutGuide *m = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
            [_titleLabel.topAnchor constraintEqualToAnchor:m.topAnchor],
            [_valueLabel.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
            [_valueLabel.firstBaselineAnchor constraintEqualToAnchor:_titleLabel.firstBaselineAnchor],
            [_valueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_titleLabel.trailingAnchor constant:8],
            [_slider.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
            [_slider.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
            [_slider.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:6],
            [_slider.bottomAnchor constraintEqualToAnchor:m.bottomAnchor],
        ]];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}
@end

@implementation HaloNexusBorderController {
    HaloNexusDefinition *_definition;
    NSString *_definitionError;
    NSArray<NSArray<HaloNexusRow *> *> *_sections;
    NSArray<NSString *> *_headers;
    NSArray<NSString *> *_footers;
    UIView *_previewHost;
    UIView *_panelSilhouette;
    HaloPanelBorderView *_preview;
    UIColor *_previousNavigationTint;
    BOOL _observingStatus;
}

static void HaloNexusStatusUpdated(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object,
                                   CFDictionaryRef userInfo) {
    HaloNexusBorderController *controller = (__bridge HaloNexusBorderController *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [controller rebuild];
    });
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)dealloc {
    [self stopObservingStatus];
    [_preview teardown];
}

#pragma mark Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Nexus Panel Border";
    if (@available(iOS 13.0, *)) self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [HaloTheme styleTableView:self.tableView];
    self.view.tintColor = HaloTheme.cyan;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kCellID];
    [self.tableView registerClass:[HaloNexusSliderCell class] forCellReuseIdentifier:@"slider"];
    [self loadDefinition];
    [self buildPreview];
    [self rebuild];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadDefinition]; // Nexus may have been installed or updated meanwhile
    [self buildPreview];
    [self rebuild];
    [self startObservingStatus];
    [self requestStatusSoon];
    UINavigationBar *bar = self.navigationController.navigationBar;
    _previousNavigationTint = bar.tintColor;
    bar.tintColor = HaloTheme.cyan;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.navigationController.navigationBar.tintColor = _previousNavigationTint;
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    _preview.active = NO; // stop animating while off screen
    if (!self.navigationController || ![self.navigationController.viewControllers containsObject:self])
        [self stopObservingStatus];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self refreshPreview];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutPreview];
}

#pragma mark Definition (installed by HCG Nexus)

- (void)loadDefinition {
    NSString *path = [HaloNexusDefinition installedPathNextToBundle:[NSBundle bundleForClass:[self class]]];
    NSString *error = nil;
    HaloNexusDefinition *definition = path ? [HaloNexusDefinition definitionAtPath:path error:&error] : nil;
    _definition = definition;
    _definitionError = definition ? nil
                                  : (error ?: @"HCG Nexus is not installed, or is older than " HALO_NEXUS_MIN_VERSION
                                              @" (no border definition)");
}

#pragma mark Preview

- (void)buildPreview {
    if (!_definition) {
        [_preview teardown];
        _preview = nil;
        UILabel *label = [UILabel new];
        label.numberOfLines = 0;
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        label.textColor = HaloTheme.textSecondary;
        label.text = @"No preview: requires compatible HCG Nexus.";
        label.frame = CGRectMake(0, 0, CGRectGetWidth(self.tableView.bounds) ?: 375, 64);
        self.tableView.tableHeaderView = label;
        _previewHost = nil;
        _panelSilhouette = nil;
        return;
    }
    if (_preview && _preview.definition.cornerRadius == _definition.cornerRadius &&
        _preview.definition.outset == _definition.outset && _preview.definition.glowMargin == _definition.glowMargin &&
        _preview.definition.clipInterior == _definition.clipInterior)
        return;
    [_preview teardown];
    CGFloat width = CGRectGetWidth(self.tableView.bounds) ?: 375;
    _previewHost = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 300)];
    _previewHost.clipsToBounds = YES;
    _previewHost.isAccessibilityElement = YES;
    _previewHost.accessibilityLabel = @"Preview of the HCG Nexus panel border";

    // An outline of the panel shape described by the installed definition;
    // on the phone the border follows the live panel instead.
    _panelSilhouette = [UIView new];
    _panelSilhouette.backgroundColor = [HaloTheme colourWithHex:0x0E1424 alpha:0.96];
    _panelSilhouette.layer.cornerRadius = (CGFloat)_definition.cornerRadius;
    if (@available(iOS 13.0, *)) _panelSilhouette.layer.cornerCurve = _definition.continuousCorners ? kCACornerCurveContinuous : kCACornerCurveCircular;
    UILabel *title = [UILabel new];
    title.text = @"HCG Nexus";
    title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    title.textColor = HaloTheme.textPrimary;
    title.frame = CGRectMake(16, 14, 160, 20);
    [_panelSilhouette addSubview:title];
    for (NSInteger i = 0; i < 4; i++) {
        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(16, 48 + i * 34, 120 - i * 14, 18)];
        bar.backgroundColor = [HaloTheme.textSecondary colorWithAlphaComponent:0.16];
        bar.layer.cornerRadius = 6;
        [_panelSilhouette addSubview:bar];
    }
    [_previewHost addSubview:_panelSilhouette];

    UILabel *caption = [UILabel new];
    caption.tag = 7;
    caption.text = @"PREVIEW — on the phone the border follows the live panel";
    caption.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    caption.textColor = HaloTheme.textSecondary;
    caption.textAlignment = NSTextAlignmentCenter;
    [_previewHost addSubview:caption];

    UIButton *replay = [UIButton buttonWithType:UIButtonTypeSystem];
    replay.tag = 8;
    [replay setTitle:@"Replay Opening" forState:UIControlStateNormal];
    replay.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [replay addTarget:self action:@selector(replayOpening) forControlEvents:UIControlEventTouchUpInside];
    [_previewHost addSubview:replay];

    _preview = [[HaloPanelBorderView alloc] initWithDefinition:_definition];
    [self layoutPreview];
    [_preview attachToHostView:_panelSilhouette];
    self.tableView.tableHeaderView = _previewHost;
    [self refreshPreview];
}

- (void)layoutPreview {
    if (!_previewHost) return;
    CGFloat width = CGRectGetWidth(self.tableView.bounds) ?: 375;
    if (CGRectGetWidth(_previewHost.frame) != width) {
        _previewHost.frame = CGRectMake(0, 0, width, 300);
        self.tableView.tableHeaderView = _previewHost;
    }
    CGFloat panelWidth = MIN(220, width - 120);
    _panelSilhouette.frame = CGRectMake((width - panelWidth) / 2, 34, panelWidth, 200);
    [_previewHost viewWithTag:7].frame = CGRectMake(16, 8, width - 32, 16);
    [_previewHost viewWithTag:8].frame = CGRectMake((width - 180) / 2, 252, 180, 36);
    [_preview relayout];
}

- (void)refreshPreview {
    if (!_preview) return;
    HaloSettings *settings = [HaloPreferences loadSettings];
    HaloAppearance appearance = settings.effectiveNexusAppearance;
    HaloRenderPlan plan = halo_render_plan(appearance.mode, UIAccessibilityIsReduceMotionEnabled(),
                                           [NSProcessInfo processInfo].lowPowerModeEnabled, settings.lowPowerPolicy);
    [_preview setAppearance:appearance plan:plan reduceTransparency:UIAccessibilityIsReduceTransparencyEnabled()];
    _preview.active = self.view.window != nil;
}

- (void)replayOpening {
    if (!_preview) return;
    HaloSettings *settings = [HaloPreferences loadSettings];
    if (!settings.nexusOpenTrace || UIAccessibilityIsReduceMotionEnabled()) {
        [self playPreviewPulse];
        return;
    }
    // The same call the SpringBoard side makes on Nexus's will-open event,
    // with Nexus's animated opening duration.
    [_preview playOpeningTraceWithDuration:0.34];
}

- (void)playPreviewPulse {
    if ([HaloPreferences loadSettings].nexusWorkspacePulse)
        [_preview playWorkspacePulseReducedMotion:UIAccessibilityIsReduceMotionEnabled()];
}

#pragma mark Status (from SpringBoard)

- (void)startObservingStatus {
    if (_observingStatus) return;
    _observingStatus = YES;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self,
                                    HaloNexusStatusUpdated, (__bridge CFStringRef)HaloStatusUpdatedNotification, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (void)stopObservingStatus {
    if (!_observingStatus) return;
    _observingStatus = NO;
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self,
                                       (__bridge CFStringRef)HaloStatusUpdatedNotification, NULL);
}

- (void)requestStatusSoon {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        notify_post(HaloStatusRequestNotification.UTF8String);
    });
}

- (NSString *)springBoardSummary {
    NSDictionary *status = [HaloPreferences readStatus];
    NSString *state = status[HaloStatusKeyNexusState];
    if (![state isKindOfClass:[NSString class]] || !state.length) return @"Not reported (respring)";
    NSDictionary *labels = @{
        @"attached" : @"Attached to the panel",
        @"waiting" : @"Waiting for the panel",
        @"off" : @"Off",
        @"unavailable" : @"Unavailable",
    };
    return labels[state] ?: state;
}

#pragma mark Model

- (HaloNexusRow *)row:(HaloRowKind)kind title:(NSString *)title {
    HaloNexusRow *row = [HaloNexusRow new];
    row.kind = kind;
    row.title = title;
    return row;
}

- (HaloNexusRow *)slider:(NSString *)title key:(NSString *)key min:(double)min max:(double)max value:(double)value unit:(NSString *)unit {
    HaloNexusRow *row = [self row:HaloRowSlider title:title];
    row.key = key;
    row.minimum = min;
    row.maximum = max;
    row.current = value;
    row.unit = unit;
    return row;
}

- (HaloNexusRow *)choice:(NSString *)title key:(NSString *)key titles:(NSArray *)titles values:(NSArray *)values current:(NSString *)current {
    HaloNexusRow *row = [self row:HaloRowChoice title:title];
    row.key = key;
    row.choiceTitles = titles;
    row.choiceValues = values;
    NSUInteger index = [values indexOfObject:current];
    row.detail = index == NSNotFound ? current : titles[index];
    return row;
}

- (void)rebuild {
    HaloSettings *settings = [HaloPreferences loadSettings];
    NSDictionary *look = [HaloPreferences dictionaryFromAppearance:settings.nexusAppearance];
    BOOL available = _definition != nil;
    NSDictionary *status = [HaloPreferences readStatus];
    __weak HaloNexusBorderController *weakSelf = self;

    // Status
    NSMutableArray *statusRows = [NSMutableArray array];
    HaloNexusRow *nexus = [self row:HaloRowInfo title:@"HCG Nexus"];
    nexus.detail = available ? [NSString stringWithFormat:@"%@ · compatible", _definition.nexusVersion] : @"Not compatible";
    [statusRows addObject:nexus];
    HaloNexusRow *sb = [self row:HaloRowInfo title:@"Panel Border"];
    sb.detail = [self springBoardSummary];
    [statusRows addObject:sb];
    NSString *rendering = status[HaloStatusKeyNexusRendering];
    if ([rendering isKindOfClass:[NSString class]] && rendering.length) {
        HaloNexusRow *now = [self row:HaloRowInfo title:@"Now"];
        now.detail = rendering;
        [statusRows addObject:now];
    }
    NSMutableArray *statusFooter = [NSMutableArray array];
    if (!available) [statusFooter addObject:[NSString stringWithFormat:@"Requires compatible HCG Nexus. %@.", _definitionError]];
    else [statusFooter addObject:[NSString stringWithFormat:@"Border definition installed by HCG Nexus: %@", _definition.path]];
    NSString *detail = status[HaloStatusKeyNexusDetail];
    if ([detail isKindOfClass:[NSString class]] && detail.length) [statusFooter addObject:[NSString stringWithFormat:@"SpringBoard: %@", detail]];
    if (!settings.enabled) [statusFooter addObject:@"HCG Halo is off: turn on Enable HCG Halo on HCG Halo's page to draw any border."];

    // Target
    NSMutableArray *targetRows = [NSMutableArray array];
    NSArray *targetTitles = @[ @"Screen Edge", @"Nexus Panel", @"Both" ];
    NSArray *targetValues = [HaloPreferences validTargets];
    NSString *currentTarget = [HaloPreferences readValueForKey:HaloKeyTarget];
    for (NSUInteger i = 0; i < targetValues.count; i++) {
        HaloNexusRow *row = [self row:HaloRowCheck title:targetTitles[i]];
        row.key = HaloKeyTarget;
        row.value = targetValues[i];
        row.on = [currentTarget isEqualToString:targetValues[i]];
        row.enabled = available || [targetValues[i] isEqualToString:@"screen"] || row.on;
        [targetRows addObject:row];
    }
    NSString *targetFooter = available
                                 ? @"Screen Edge is the default and is unchanged by these settings. With Nexus Panel or Both, the "
                                   @"border appears only while the HCG Nexus panel is shown."
                                 : @"Nexus Panel and Both: requires compatible HCG Nexus (" HALO_NEXUS_MIN_VERSION
                                   @" or later). The screen-edge border keeps working.";

    // Look
    NSMutableArray *lookRows = [NSMutableArray array];
    HaloNexusRow *match = [self row:HaloRowSwitch title:@"Match Screen Edge"];
    match.key = HaloKeyNexusMatchScreen;
    match.on = settings.nexusMatchScreen;
    [lookRows addObject:match];
    NSString *matching = settings.nexusMatchScreen ? nil : [HaloPreferences matchingNexusPresetIdentifier];
    NSMutableArray *presets = [NSMutableArray array];
    NSArray *ordered = @[ @"builtin.nexus-signature", @"builtin.reactor", @"builtin.hologram" ];
    for (NSString *identifier in ordered) {
        NSDictionary *p = [HaloPreferences presetWithIdentifier:identifier];
        if (p) [presets addObject:p];
    }
    for (NSDictionary *p in [[HaloPreferences builtInPresets] arrayByAddingObjectsFromArray:[HaloPreferences userPresets]]) {
        if (![ordered containsObject:p[HaloPresetKeyID]]) [presets addObject:p];
    }
    for (NSDictionary *p in presets) {
        HaloNexusRow *row = [self row:HaloRowCheck title:p[HaloPresetKeyName]];
        row.key = @"preset";
        row.value = p[HaloPresetKeyID];
        row.on = [matching isEqualToString:p[HaloPresetKeyID]];
        row.enabled = !settings.nexusMatchScreen;
        [lookRows addObject:row];
    }

    // Style
    NSMutableArray *styleRows = [NSMutableArray array];
    if (!settings.nexusMatchScreen) {
        [styleRows addObject:[self choice:@"Mode" key:HaloKeyMode
                                   titles:@[ @"Static", @"Breathing", @"Colour Flow", @"Orbit", @"Sci-Fi Circuit" ]
                                   values:[HaloPreferences validModes] current:look[HaloKeyMode]]];
        [styleRows addObject:[self choice:@"Colour Style" key:HaloKeyColourStyle
                                   titles:@[ @"Single Colour", @"Multiple Colours", @"Gradient" ]
                                   values:[HaloPreferences validColourStyles] current:look[HaloKeyColourStyle]]];
        HaloNexusRow *colours = [self row:HaloRowLink title:@"Edit Colours"];
        colours.detail = [NSString stringWithFormat:@"%lu", (unsigned long)[look[HaloKeyColours] count]];
        colours.action = ^{
            HaloColoursController *c = [[HaloColoursController alloc] initForNexusBorder];
            c.didChange = ^{
                [weakSelf refreshPreview];
            };
            [weakSelf.navigationController pushViewController:c animated:YES];
        };
        [styleRows addObject:colours];
        [styleRows addObject:[self slider:@"Brightness" key:HaloKeyBrightness min:HALO_BRIGHTNESS_MIN max:HALO_BRIGHTNESS_MAX
                                    value:[look[HaloKeyBrightness] doubleValue] unit:@"%"]];
        [styleRows addObject:[self slider:@"Thickness" key:HaloKeyThickness min:HALO_THICKNESS_MIN max:6
                                    value:[look[HaloKeyThickness] doubleValue] unit:@"pt"]];
        [styleRows addObject:[self slider:@"Glow" key:HaloKeyGlow min:HALO_GLOW_MIN max:HALO_GLOW_MAX
                                    value:[look[HaloKeyGlow] doubleValue] unit:@"%"]];
        [styleRows addObject:[self slider:@"Speed" key:HaloKeySpeed min:HALO_SPEED_MIN max:HALO_SPEED_MAX
                                    value:[look[HaloKeySpeed] doubleValue] unit:@"×"]];
        [styleRows addObject:[self slider:@"Soft Pulse" key:HaloKeyPulse min:HALO_PULSE_MIN max:HALO_PULSE_MAX
                                    value:[look[HaloKeyPulse] doubleValue] unit:@"%"]];
        HaloNexusRow *segments = [self slider:@"Segments" key:HaloKeySegments min:HALO_SEGMENTS_MIN max:HALO_SEGMENTS_MAX
                                        value:[look[HaloKeySegments] doubleValue] unit:@""];
        segments.integral = YES;
        [styleRows addObject:segments];
        [styleRows addObject:[self slider:@"Segment Length" key:HaloKeySegmentLength min:HALO_SEGMENT_LENGTH_MIN
                                      max:HALO_SEGMENT_LENGTH_MAX value:[look[HaloKeySegmentLength] doubleValue] unit:@"%"]];
        [styleRows addObject:[self choice:@"Direction" key:HaloKeyDirection titles:@[ @"Clockwise", @"Counter-clockwise" ]
                                   values:[HaloPreferences validDirections] current:look[HaloKeyDirection]]];
    }

    // Effects
    NSMutableArray *effectRows = [NSMutableArray array];
    NSArray *effects = @[
        @[ @"Opening Trace", HaloKeyNexusOpenTrace, @(settings.nexusOpenTrace) ],
        @[ @"Fade With Panel", HaloKeyNexusCloseFade, @(settings.nexusCloseFade) ],
        @[ @"Workspace Pulse", HaloKeyNexusWorkspacePulse, @(settings.nexusWorkspacePulse) ],
    ];
    for (NSArray *e in effects) {
        HaloNexusRow *row = [self row:HaloRowSwitch title:e[0]];
        row.key = e[1];
        row.on = [e[2] boolValue];
        [effectRows addObject:row];
    }

    HaloNexusRow *reset = [self row:HaloRowButton title:@"Reset Nexus Lighting"];
    reset.action = ^{
        [weakSelf confirmReset];
    };

    _sections = @[ statusRows, targetRows, lookRows, styleRows, effectRows, @[ reset ] ];
    _headers = @[ @"Status", @"Border Target", @"Panel Look", settings.nexusMatchScreen ? @"" : @"Panel Style", @"Effects", @"" ];
    _footers = @[
        [statusFooter componentsJoinedByString:@"\n\n"],
        targetFooter,
        settings.nexusMatchScreen ? @"The panel border uses the screen edge's look. Turn this off to style the panel separately."
                                  : @"Presets here change the panel border only. Nexus Signature, Reactor and Hologram are visual "
                                    @"styles; they do not reflect system activity.",
        settings.nexusMatchScreen ? @"" : @"Thickness and glow apply to the panel border only. The light sits just outside the "
                                          @"panel edge and never covers its content.",
        kEffectsFooter,
        kResetFooter,
    ];
    [self.tableView reloadData];
    [self refreshPreview];
}

#pragma mark Writing

- (void)commit {
    [HaloPreferences postChangeNotification];
    [self requestStatusSoon];
}

- (void)writeAppearanceValue:(id)value forKey:(NSString *)key {
    [HaloPreferences writeNexusAppearanceValue:value forKey:key];
}

- (void)confirmReset {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset Nexus Lighting"
                                                                   message:@"Return the panel border's look and effects to "
                                                                           @"Nexus Signature? The border target and every "
                                                                           @"screen-edge setting are kept."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak HaloNexusBorderController *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
                                                [HaloPreferences resetNexusLighting];
                                                [weakSelf commit];
                                                [weakSelf rebuild];
                                            }]];
    alert.view.tintColor = HaloTheme.cyan;
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark Table

- (HaloNexusRow *)rowAt:(NSIndexPath *)indexPath {
    return _sections[indexPath.section][indexPath.row];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)_sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_sections[section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSString *t = _headers[section];
    return t.length && _sections[section].count ? t : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    NSString *t = _footers[section];
    return t.length ? t : nil;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    [HaloTheme styleHeaderFooterView:view header:YES];
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    [HaloTheme styleHeaderFooterView:view header:NO];
}

- (NSString *)formatValue:(double)value row:(HaloNexusRow *)row {
    if (row.integral) return [NSString stringWithFormat:@"%.0f", value];
    if ([row.unit isEqualToString:@"%"]) return [NSString stringWithFormat:@"%.0f%%", value * 100];
    if ([row.unit isEqualToString:@"pt"]) return [NSString stringWithFormat:@"%.1f pt", value];
    return [NSString stringWithFormat:@"%.2f%@", value, row.unit];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    HaloNexusRow *row = [self rowAt:indexPath];
    if (row.kind == HaloRowSlider) {
        HaloNexusSliderCell *cell = [tableView dequeueReusableCellWithIdentifier:@"slider" forIndexPath:indexPath];
        [HaloTheme styleCell:cell];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.titleLabel.text = row.title;
        cell.valueLabel.text = [self formatValue:row.current row:row];
        cell.slider.minimumValue = (float)row.minimum;
        cell.slider.maximumValue = (float)row.maximum;
        cell.slider.value = (float)row.current;
        cell.slider.accessibilityLabel = row.title;
        cell.slider.tag = indexPath.section * 1000 + indexPath.row;
        [cell.slider removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
        [cell.slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [cell.slider addTarget:self
                        action:@selector(sliderReleased:)
              forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        return cell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID];
    if (row.kind == HaloRowInfo || row.kind == HaloRowChoice || row.kind == HaloRowLink)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    [HaloTheme styleCell:cell];
    cell.textLabel.text = row.title;
    cell.textLabel.textColor = row.enabled ? HaloTheme.textPrimary : HaloTheme.textDisabled;
    cell.detailTextLabel.text = row.detail;
    cell.detailTextLabel.textColor = HaloTheme.textSecondary;
    cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
    cell.detailTextLabel.minimumScaleFactor = 0.6;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessibilityTraits = UIAccessibilityTraitNone;
    switch (row.kind) {
    case HaloRowInfo:
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        break;
    case HaloRowCheck:
        cell.accessoryType = row.on ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        if (row.on) cell.accessibilityTraits |= UIAccessibilityTraitSelected;
        if (!row.enabled) cell.accessibilityTraits |= UIAccessibilityTraitNotEnabled;
        cell.accessibilityTraits |= UIAccessibilityTraitButton;
        break;
    case HaloRowSwitch: {
        UISwitch *toggle = [UISwitch new];
        toggle.on = row.on;
        toggle.onTintColor = HaloTheme.cyan;
        toggle.tag = indexPath.section * 1000 + indexPath.row;
        toggle.accessibilityLabel = row.title;
        [toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        break;
    }
    case HaloRowChoice:
    case HaloRowLink:
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessibilityTraits |= UIAccessibilityTraitButton;
        break;
    case HaloRowButton:
        cell.textLabel.textColor = [UIColor systemRedColor];
        cell.accessibilityTraits |= UIAccessibilityTraitButton;
        break;
    case HaloRowSlider:
        break;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    HaloNexusRow *row = [self rowAt:indexPath];
    if (!row.enabled) {
        if (row.kind == HaloRowCheck && [row.key isEqualToString:HaloKeyTarget]) {
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:@"Requires compatible HCG Nexus"
                                 message:[NSString stringWithFormat:@"%@.\n\nThe screen-edge border keeps working.", _definitionError]
                          preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
        return;
    }
    switch (row.kind) {
    case HaloRowCheck:
        if ([row.key isEqualToString:HaloKeyTarget]) {
            [HaloPreferences writeValue:row.value forKey:HaloKeyTarget];
        } else {
            [HaloPreferences applyPresetToNexus:row.value];
            [self replayOpening];
        }
        [self commit];
        [self rebuild];
        break;
    case HaloRowChoice: {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:row.title
                                                                       message:nil
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        __weak HaloNexusBorderController *weakSelf = self;
        for (NSUInteger i = 0; i < row.choiceValues.count; i++) {
            NSString *value = row.choiceValues[i];
            [sheet addAction:[UIAlertAction actionWithTitle:row.choiceTitles[i]
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(UIAlertAction *action) {
                                                        HaloNexusBorderController *strong = weakSelf;
                                                        [strong writeAppearanceValue:value forKey:row.key];
                                                        [strong commit];
                                                        [strong rebuild];
                                                    }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        sheet.view.tintColor = HaloTheme.cyan;
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        sheet.popoverPresentationController.sourceView = cell ?: tableView;
        sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : CGRectZero;
        [self presentViewController:sheet animated:YES completion:nil];
        break;
    }
    case HaloRowLink:
    case HaloRowButton:
        if (row.action) row.action();
        break;
    default:
        break;
    }
}

- (HaloNexusRow *)rowForTag:(NSInteger)tag {
    NSInteger section = tag / 1000, index = tag % 1000;
    if (section < 0 || section >= (NSInteger)_sections.count || index < 0 || index >= (NSInteger)_sections[section].count) return nil;
    return _sections[section][index];
}

- (void)switchChanged:(UISwitch *)toggle {
    HaloNexusRow *row = [self rowForTag:toggle.tag];
    if (!row.key) return;
    [HaloPreferences writeValue:@(toggle.on) forKey:row.key];
    [self commit];
    [self rebuild];
    if ([row.key isEqualToString:HaloKeyNexusOpenTrace] && toggle.on) [self replayOpening];
    if ([row.key isEqualToString:HaloKeyNexusWorkspacePulse] && toggle.on) [self playPreviewPulse];
}

- (void)sliderChanged:(UISlider *)slider {
    HaloNexusRow *row = [self rowForTag:slider.tag];
    if (!row.key) return;
    double value = row.integral ? round(slider.value) : slider.value;
    if (row.integral) slider.value = (float)value;
    row.current = value;
    [self writeAppearanceValue:@(value) forKey:row.key];
    HaloNexusSliderCell *cell = (HaloNexusSliderCell *)slider.superview.superview;
    if ([cell isKindOfClass:[HaloNexusSliderCell class]]) cell.valueLabel.text = [self formatValue:value row:row];
    [self refreshPreview]; // immediate local preview; SpringBoard follows on release
}

- (void)sliderReleased:(UISlider *)slider {
    [self commit];
}

@end
