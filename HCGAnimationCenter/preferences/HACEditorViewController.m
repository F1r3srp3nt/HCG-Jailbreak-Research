//
//  HACEditorViewController.m
//  HCG Animation Center — Hakmi Capital Group
//

#import "HACEditorViewController.h"
#import "HACLibrary.h"
#import "HACMediaImporter.h"
#import "HACPreferences.h"
#import "HACTheme.h"
#import "HCGBackgroundCore.h"

static NSArray<NSNumber *> *Speeds(void) {
    return @[ @0.5, @0.75, @1.0, @1.25, @1.5, @2.0 ];
}

// Normalised points (y down) between the source picture and the displayed one
// (rotated clockwise, then flipped in screen axes), so the part of the picture
// in the middle stays there when the orientation changes.
static CGPoint RotatePoint(CGPoint p, NSInteger degrees) {
    switch (hcgbg_rotation_normalize((double)degrees, NULL)) {
        case 90: return CGPointMake(1 - p.y, p.x);
        case 180: return CGPointMake(1 - p.x, 1 - p.y);
        case 270: return CGPointMake(p.y, 1 - p.x);
        default: return p;
    }
}

static CGPoint DisplayedFromSource(CGPoint p, NSInteger rotation, BOOL flipH, BOOL flipV) {
    p = RotatePoint(p, rotation);
    return CGPointMake(flipH ? 1 - p.x : p.x, flipV ? 1 - p.y : p.y);
}

static CGPoint SourceFromDisplayed(CGPoint p, NSInteger rotation, BOOL flipH, BOOL flipV) {
    p = CGPointMake(flipH ? 1 - p.x : p.x, flipV ? 1 - p.y : p.y);
    return RotatePoint(p, 360 - hcgbg_rotation_normalize((double)rotation, NULL));
}

@interface HACEditorViewController () <UITextFieldDelegate>
@end

@implementation HACEditorViewController {
    NSMutableArray<HCGBackgroundPreset *> *_drafts;    // [HACSurfaceHome], [HACSurfaceLock]
    NSMutableArray<HCGBackgroundPreset *> *_originals; // as saved in the library
    HCGBackgroundPreset *_item;                        // identity in the library
    BOOL _lockOwn, _lockOwnSaved;
    HACAIResult *_aiResult;
    NSURL *_folder;
    HACSurface _preferred;
    BOOL _adopted;
    BOOL _deleted;

    HACPreviewStage *_stage;
    UIStackView *_stack;
    UILabel *_info, *_sourceLabel, *_placementNote;
    UITextField *_nameField;
    UISlider *_startSlider, *_endSlider, *_zoomSlider, *_xSlider, *_ySlider, *_stillSlider;
    UILabel *_startLabel, *_endLabel, *_zoomLabel, *_xLabel, *_yLabel, *_stillLabel;
    UISegmentedControl *_placementSegment, *_overlaySegment, *_rotationSegment, *_modeSegment, *_speedSegment;
    UISwitch *_loopSwitch, *_flipHSwitch, *_flipVSwitch;
    UIButton *_useHomeButton, *_resetButton;
    UIActivityIndicatorView *_spinner;
    double _zoom, _centerX, _centerY;
    CGPoint _panStartCenter;
}

- (instancetype)initWithItem:(HCGBackgroundPreset *)item preferredSurface:(HACSurface)surface {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        HACLibrary *library = [HACLibrary shared];
        _item = [item copy];
        HCGBackgroundPreset *home = [library presetForItem:item placement:HACSurfaceHome] ?: [item copy];
        HCGBackgroundPreset *lock = [library presetForItem:item placement:HACSurfaceLock] ?: [home copy];
        _drafts = [NSMutableArray arrayWithObjects:[home copy], [lock copy], nil];
        _originals = [NSMutableArray arrayWithObjects:home, lock, nil];
        _lockOwn = _lockOwnSaved = [library item:item hasOwnSettingsForPlacement:HACSurfaceLock];
        _folder = [HACPreferences mediaFolder];
        _preferred = surface;
        _placement = surface == HACSurfaceLock ? HACSurfaceLock : HACSurfaceHome;
        self.title = item.name;
        [self syncFramingFromDraft];
    }
    return self;
}

- (instancetype)initWithAIResult:(HACAIResult *)result draft:(HCGBackgroundPreset *)draft {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _aiResult = result;
        _drafts = [NSMutableArray arrayWithObjects:[draft copy], [draft copy], nil];
        _originals = [NSMutableArray arrayWithObjects:[draft copy], [draft copy], nil];
        _folder = [result.previewFile URLByDeletingLastPathComponent];
        _preferred = HACSurfaceHome;
        _placement = HACSurfaceHome;
        self.title = @"AI Preview";
        [self syncFramingFromDraft];
    }
    return self;
}

- (BOOL)isAIPreview {
    return _aiResult != nil;
}

- (HCGBackgroundPreset *)current {
    return _drafts[(NSUInteger)_placement];
}

- (HCGBackgroundPreset *)draft {
    return [[self current] copy];
}

- (BOOL)lockHasOwnSettings {
    return _lockOwn;
}

- (HCGBackgroundView *)previewView {
    [self loadViewIfNeeded];
    return _stage.background;
}

- (double)zoom {
    return _zoom;
}

- (CGPoint)position {
    return CGPointMake(_centerX, _centerY);
}

- (HACFramingMode)framingMode {
    HCGBackgroundPreset *d = [self current];
    if (d.stretch) return HACFramingModeStretch;
    return d.scaling == HCGBackgroundScalingFit ? HACFramingModeFit : HACFramingModeFillCrop;
}

/// The screen the placement is laid out for (points; only the aspect matters).
- (CGSize)screenSize {
    if (_stage) return _stage.screenSize;
    CGSize s = UIScreen.mainScreen.bounds.size;
    return CGSizeMake(MIN(s.width, s.height), MAX(s.width, s.height));
}

#pragma mark View

- (void)viewDidLoad {
    [super viewDidLoad];
    HACApplyTheme(self);
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:scroll];
    _stack = [[UIStackView alloc] init];
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.spacing = 10;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:_stack];
    UILayoutGuide *content = scroll.contentLayoutGuide, *frame = scroll.frameLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:12],
        [_stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-24],
        [_stack.leadingAnchor constraintEqualToAnchor:frame.leadingAnchor constant:16],
        [_stack.trailingAnchor constraintEqualToAnchor:frame.trailingAnchor constant:-16],
    ]];

    // Placement (library mode): each screen keeps its own settings.
    if (!self.isAIPreview) {
        _placementSegment = [[UISegmentedControl alloc] initWithItems:@[ @"Home Screen", @"Lock Screen" ]];
        _placementSegment.selectedSegmentIndex = _placement;
        [_placementSegment addTarget:self action:@selector(placementChanged) forControlEvents:UIControlEventValueChanged];
        _placementSegment.accessibilityLabel = @"Settings for";
        [_stack addArrangedSubview:_placementSegment];
        _placementNote = [self footnote:@""];
        [_stack addArrangedSubview:_placementNote];
    }

    // Preview
    _stage = [[HACPreviewStage alloc] initWithFrame:CGRectZero];
    _stage.translatesAutoresizingMaskIntoConstraints = NO;
    _stage.overlay = _placement == HACSurfaceLock ? HACStageOverlayLockClock : HACStageOverlayHomeIcons;
    UIView *stageRow = [[UIView alloc] init];
    [stageRow addSubview:_stage];
    CGSize screen = _stage.screenSize;
    [NSLayoutConstraint activateConstraints:@[
        [_stage.topAnchor constraintEqualToAnchor:stageRow.topAnchor],
        [_stage.bottomAnchor constraintEqualToAnchor:stageRow.bottomAnchor],
        [_stage.centerXAnchor constraintEqualToAnchor:stageRow.centerXAnchor],
        [_stage.widthAnchor constraintEqualToAnchor:stageRow.widthAnchor multiplier:0.56],
        [_stage.heightAnchor constraintEqualToAnchor:_stage.widthAnchor multiplier:screen.height / screen.width],
    ]];
    [_stack addArrangedSubview:stageRow];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)];
    [_stage addGestureRecognizer:pan];

    _overlaySegment = [[UISegmentedControl alloc] initWithItems:@[ @"Plain", @"Home icons", @"Lock clock" ]];
    _overlaySegment.selectedSegmentIndex = _stage.overlay;
    [_overlaySegment addTarget:self action:@selector(overlayChanged) forControlEvents:UIControlEventValueChanged];
    [_stack addArrangedSubview:_overlaySegment];

    _info = [self footnote:@""];
    _info.textAlignment = NSTextAlignmentCenter;
    [_stack addArrangedSubview:_info];
    if (self.isAIPreview)
        [_stack addArrangedSubview:[self footnote:@"This is only a preview. Nothing is saved or applied until you tap "
                                                  @"Apply or Save to Library."]];

    // Name
    [_stack addArrangedSubview:[self header:@"Name"]];
    _nameField = [[UITextField alloc] init];
    _nameField.borderStyle = UITextBorderStyleRoundedRect;
    _nameField.text = [self current].name;
    _nameField.delegate = self;
    _nameField.returnKeyType = UIReturnKeyDone;
    _nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
    [_stack addArrangedSubview:_nameField];

    // Orientation
    [_stack addArrangedSubview:[self header:@"Orientation"]];
    _sourceLabel = [self footnote:@""];
    [_stack addArrangedSubview:_sourceLabel];
    _rotationSegment = [[UISegmentedControl alloc] initWithItems:@[ @"0°", @"90°", @"180°", @"270°" ]];
    _rotationSegment.accessibilityLabel = @"Rotation, clockwise";
    [_rotationSegment addTarget:self action:@selector(rotationChanged) forControlEvents:UIControlEventValueChanged];
    UIButton *rotate = [UIButton buttonWithType:UIButtonTypeSystem];
    [rotate setImage:[UIImage systemImageNamed:@"rotate.right"] forState:UIControlStateNormal];
    rotate.tintColor = HACAccentColor();
    rotate.accessibilityLabel = @"Rotate 90 degrees clockwise";
    [rotate addTarget:self action:@selector(rotateClockwise) forControlEvents:UIControlEventTouchUpInside];
    [rotate.widthAnchor constraintEqualToConstant:44].active = YES;
    UIStackView *rotationRow = [[UIStackView alloc] initWithArrangedSubviews:@[ _rotationSegment, rotate ]];
    rotationRow.spacing = 10;
    rotationRow.alignment = UIStackViewAlignmentCenter;
    [_stack addArrangedSubview:rotationRow];
    _flipHSwitch = [[UISwitch alloc] init];
    _flipVSwitch = [[UISwitch alloc] init];
    for (UISwitch *s in @[ _flipHSwitch, _flipVSwitch ]) {
        s.onTintColor = HACAccentColor();
        [s addTarget:self action:@selector(flipChanged) forControlEvents:UIControlEventValueChanged];
    }
    [_stack addArrangedSubview:[self row:@"Flip horizontally" control:_flipHSwitch value:nil]];
    [_stack addArrangedSubview:[self row:@"Flip vertically" control:_flipVSwitch value:nil]];

    // Framing
    [_stack addArrangedSubview:[self header:@"Framing"]];
    _modeSegment = [[UISegmentedControl alloc] initWithItems:@[ @"Fit", @"Fill / Crop", @"Stretch" ]];
    [_modeSegment addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
    [_stack addArrangedSubview:_modeSegment];
    _zoomSlider = [self slider];
    _zoomSlider.minimumValue = 1;
    _zoomSlider.maximumValue = 5;
    _zoomLabel = [self valueLabel];
    _xSlider = [self slider];
    _ySlider = [self slider];
    _xLabel = [self valueLabel];
    _yLabel = [self valueLabel];
    for (UISlider *s in @[ _xSlider, _ySlider ]) {
        s.minimumValue = 0;
        s.maximumValue = 1;
    }
    _xSlider.accessibilityLabel = @"Horizontal position";
    _ySlider.accessibilityLabel = @"Vertical position";
    [_stack addArrangedSubview:[self row:@"Zoom" control:_zoomSlider value:_zoomLabel]];
    [_stack addArrangedSubview:[self row:@"X" control:_xSlider value:_xLabel]];
    [_stack addArrangedSubview:[self row:@"Y" control:_ySlider value:_yLabel]];
    [_stack addArrangedSubview:[self footnote:@"Drag the preview to move the picture. Fit shows the whole picture "
                                              @"with bars, Fill / Crop covers the screen, Stretch fills it exactly "
                                              @"and ignores the proportions. The video file itself is never changed."]];
    _resetButton = HACMakeButton(@"Reset Transformations", @"arrow.counterclockwise", NO);
    [_resetButton addTarget:self action:@selector(resetTransformations) forControlEvents:UIControlEventTouchUpInside];
    [_stack addArrangedSubview:_resetButton];

    // Trim
    [_stack addArrangedSubview:[self header:@"Trim"]];
    _startSlider = [self slider];
    _endSlider = [self slider];
    _startLabel = [self valueLabel];
    _endLabel = [self valueLabel];
    for (UISlider *s in @[ _startSlider, _endSlider ]) {
        s.minimumValue = 0;
        s.maximumValue = (float)[self current].duration;
    }
    [_stack addArrangedSubview:[self row:@"Start" control:_startSlider value:_startLabel]];
    [_stack addArrangedSubview:[self row:@"End" control:_endSlider value:_endLabel]];

    // Playback
    [_stack addArrangedSubview:[self header:@"Playback"]];
    _loopSwitch = [[UISwitch alloc] init];
    _loopSwitch.onTintColor = HACAccentColor();
    [_loopSwitch addTarget:self action:@selector(loopChanged) forControlEvents:UIControlEventValueChanged];
    [_stack addArrangedSubview:[self row:@"Loop" control:_loopSwitch value:nil]];
    NSMutableArray *speedTitles = [NSMutableArray array];
    for (NSNumber *n in Speeds()) [speedTitles addObject:[NSString stringWithFormat:@"%g×", n.doubleValue]];
    _speedSegment = [[UISegmentedControl alloc] initWithItems:speedTitles];
    [_speedSegment addTarget:self action:@selector(speedChanged) forControlEvents:UIControlEventValueChanged];
    [_stack addArrangedSubview:_speedSegment];
    [_stack addArrangedSubview:[self footnote:@"Backgrounds always play muted. Without Loop, the clip plays once each "
                                              @"time the screen shows it, then holds its last frame."]];

    // Still
    [_stack addArrangedSubview:[self header:@"Still Image"]];
    _stillSlider = [self slider];
    _stillLabel = [self valueLabel];
    _stillSlider.minimumValue = 0;
    _stillSlider.maximumValue = (float)[self current].duration;
    [_stack addArrangedSubview:[self row:@"Frame" control:_stillSlider value:_stillLabel]];
    [_stack addArrangedSubview:[self footnote:@"Shown instead of the video when Reduce Motion or Low Power Mode is on, "
                                              @"when the device is hot, or if the video can't play. It is turned and "
                                              @"framed like the video."]];

    // Actions
    [_stack addArrangedSubview:[self header:@""]];
    if (!self.isAIPreview) {
        _useHomeButton = HACMakeButton(@"Use Home Screen Settings", @"arrow.uturn.backward", NO);
        [_useHomeButton addTarget:self action:@selector(useHomeSettingsForLock) forControlEvents:UIControlEventTouchUpInside];
        [_stack addArrangedSubview:_useHomeButton];
    }
    UIButton *home = HACMakeButton(@"Apply to Home Screen", @"apps.iphone", _preferred == HACSurfaceHome);
    [home addTarget:self action:@selector(applyHome) forControlEvents:UIControlEventTouchUpInside];
    UIButton *lock = HACMakeButton(@"Apply to Lock Screen", @"lock.iphone", _preferred == HACSurfaceLock);
    [lock addTarget:self action:@selector(applyLock) forControlEvents:UIControlEventTouchUpInside];
    [_stack addArrangedSubview:home];
    [_stack addArrangedSubview:lock];
    if (self.isAIPreview) {
        UIButton *save = HACMakeButton(@"Save to Library", @"tray.and.arrow.down", NO);
        [save addTarget:self action:@selector(saveAI) forControlEvents:UIControlEventTouchUpInside];
        UIButton *discard = HACMakeButton(@"Discard", @"trash", NO);
        [discard addTarget:self action:@selector(discardAI) forControlEvents:UIControlEventTouchUpInside];
        [_stack addArrangedSubview:save];
        [_stack addArrangedSubview:discard];
    } else {
        UIButton *export = HACMakeButton(@"Export…", @"square.and.arrow.up", NO);
        [export addTarget:self action:@selector(exportPreset:) forControlEvents:UIControlEventTouchUpInside];
        UIButton *delete = HACMakeButton(@"Delete from Library", @"trash", NO);
        [delete addTarget:self action:@selector(deleteItem) forControlEvents:UIControlEventTouchUpInside];
        [_stack addArrangedSubview:export];
        [_stack addArrangedSubview:delete];
    }
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _spinner.hidesWhenStopped = YES;
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_spinner];
    [NSLayoutConstraint activateConstraints:@[
        [_spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];

    for (UISlider *s in @[ _startSlider, _endSlider, _zoomSlider, _xSlider, _ySlider, _stillSlider ]) {
        [s addTarget:self action:@selector(sliderMoved:) forControlEvents:UIControlEventValueChanged];
        [s addTarget:self
                      action:@selector(sliderReleased:)
            forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    }
    [self syncFramingFromDraft]; // the real stage size
    [self refreshControls];
    [self refreshPreview];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (!self.isMovingFromParentViewController && !self.isBeingDismissed) return;
    _stage.background.display = HCGBackgroundDisplayNone;
    [_stage.background releasePlayer];
    if (self.isAIPreview) {
        if (!_adopted) [HACAIGeneration discardResult:_aiResult];
    } else if (!_deleted) {
        NSError *error = nil;
        if (![self save:&error]) NSLog(@"[HCGAnimationCenter] could not save edits: %@", error.localizedDescription);
    }
}

#pragma mark Building blocks

- (UILabel *)header:(NSString *)text {
    UILabel *l = [[UILabel alloc] init];
    l.text = text.uppercaseString;
    l.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    l.textColor = UIColor.secondaryLabelColor;
    [l.heightAnchor constraintGreaterThanOrEqualToConstant:text.length ? 28 : 8].active = YES;
    return l;
}

- (UILabel *)footnote:(NSString *)text {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.numberOfLines = 0;
    l.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    l.textColor = UIColor.secondaryLabelColor;
    return l;
}

- (UISlider *)slider {
    UISlider *s = [[UISlider alloc] init];
    s.minimumTrackTintColor = HACAccentColor();
    return s;
}

- (UILabel *)valueLabel {
    UILabel *l = [[UILabel alloc] init];
    l.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightRegular];
    l.textAlignment = NSTextAlignmentRight;
    [l.widthAnchor constraintEqualToConstant:64].active = YES;
    return l;
}

- (UIView *)row:(NSString *)title control:(UIView *)control value:(UILabel *)value {
    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    NSMutableArray *views = [NSMutableArray arrayWithObjects:label, control, nil];
    if (value) [views addObject:value];
    if ([control isKindOfClass:[UISwitch class]]) {
        [views insertObject:[[UIView alloc] init] atIndex:1]; // spacer
        control.accessibilityLabel = title;
    } else {
        [label.widthAnchor constraintEqualToConstant:56].active = YES;
    }
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:views];
    row.spacing = 10;
    row.alignment = UIStackViewAlignmentCenter;
    return row;
}

#pragma mark State → controls / preview

- (void)selectSpeed {
    NSArray *speeds = Speeds();
    NSInteger best = 2;
    double bestDelta = INFINITY;
    for (NSUInteger i = 0; i < speeds.count; i++) {
        double delta = fabs([speeds[i] doubleValue] - [self current].speed);
        if (delta < bestDelta) {
            bestDelta = delta;
            best = (NSInteger)i;
        }
    }
    _speedSegment.selectedSegmentIndex = best;
}

- (void)refreshControls {
    HCGBackgroundPreset *d = [self current];
    _info.text = [NSString stringWithFormat:@"%@ · clip %@\n%@", HACDescribePreset(d), HACFormatSeconds(d.clipDuration),
                                            HACDescribeTransform(d)];
    _sourceLabel.text = [@"Source: " stringByAppendingString:HACDescribeSource(d)];
    _startSlider.value = (float)d.trimStart;
    _endSlider.value = (float)d.trimEnd;
    _stillSlider.value = (float)d.stillTime;
    _startLabel.text = HACFormatSeconds(d.trimStart);
    _endLabel.text = HACFormatSeconds(d.trimEnd);
    _stillLabel.text = HACFormatSeconds(d.stillTime);
    _rotationSegment.selectedSegmentIndex = hcgbg_rotation_normalize((double)d.rotation, NULL) / 90;
    _flipHSwitch.on = d.flipHorizontal;
    _flipVSwitch.on = d.flipVertical;
    _modeSegment.selectedSegmentIndex = self.framingMode;
    _zoomSlider.value = (float)_zoom;
    _xSlider.value = (float)_centerX;
    _ySlider.value = (float)_centerY;
    _zoomLabel.text = [NSString stringWithFormat:@"%.2f×", _zoom];
    _xLabel.text = [NSString stringWithFormat:@"%.0f%%", _centerX * 100];
    _yLabel.text = [NSString stringWithFormat:@"%.0f%%", _centerY * 100];
    _loopSwitch.on = d.loops;
    [self selectSpeed];
    BOOL original = d.isTransformIdentity && d.scaling == HCGBackgroundScalingFill && !d.hasTransform;
    _resetButton.enabled = !original;
    _resetButton.alpha = original ? 0.5 : 1;
    if (_placementSegment) {
        _placementSegment.selectedSegmentIndex = _placement;
        BOOL lock = _placement == HACSurfaceLock;
        _placementNote.text = !lock     ? (_lockOwn ? @"The Lock Screen has its own settings."
                                                    : @"The Lock Screen uses these settings until you change them there.")
                              : _lockOwn ? @"These settings are only for the Lock Screen."
                                         : @"The Lock Screen uses the Home Screen settings. Changing anything here gives "
                                           @"it its own.";
        _useHomeButton.hidden = !(lock && _lockOwn);
    }
}

- (void)refreshPreview {
    [_stage.background setPreset:[self current] folder:_folder];
    _stage.background.display = HCGBackgroundDisplayPlaying;
}

/// Zoom and position from the draft's scaling and crop rectangle.
- (void)syncFramingFromDraft {
    HCGBackgroundPreset *d = [self current];
    CGSize screen = [self screenSize];
    CGSize o = d.orientedMediaSize;
    HCGBGSize container = {screen.width, screen.height}, oriented = {o.width, o.height};
    HCGBGRect region = {d.crop.origin.x, d.crop.origin.y, d.crop.size.width, d.crop.size.height};
    BOOL regionUsed = d.scaling == HCGBackgroundScalingCrop || d.usesRegionInAllModes;
    if (!regionUsed) region = (HCGBGRect){0, 0, 1, 1};
    HCGBGScaling scaling = (HCGBGScaling)d.scaling;
    if (scaling == HCGBGScalingFill && !d.stretch) scaling = HCGBGScalingCrop; // "fill" = Fill / Crop of the whole frame
    if (scaling == HCGBGScalingCrop && !regionUsed) {
        _zoom = 1;
    } else {
        _zoom = hcgbg_zoom_for_region(scaling, d.stretch, container, oriented, region);
    }
    if (!isfinite(_zoom) || _zoom < 1) _zoom = 1;
    _centerX = region.x + region.width / 2;
    _centerY = region.y + region.height / 2;
}

/// Writes mode, zoom and position into the draft's scaling, stretch and crop.
- (void)applyFramingMode:(HACFramingMode)mode {
    HCGBackgroundPreset *d = [self current];
    HCGBGScaling scaling = mode == HACFramingModeFit ? HCGBGScalingFit
                           : mode == HACFramingModeStretch ? HCGBGScalingFill // older readers: fill
                                                           : HCGBGScalingCrop;
    d.stretch = mode == HACFramingModeStretch;
    d.scaling = (HCGBackgroundScaling)scaling;
    CGSize screen = [self screenSize];
    CGSize o = d.orientedMediaSize;
    _zoom = MAX(1.0, MIN(5.0, _zoom));
    HCGBGRect r = hcgbg_region_from_zoom(scaling, d.stretch, (HCGBGSize){screen.width, screen.height},
                                         (HCGBGSize){o.width, o.height}, _zoom, _centerX, _centerY);
    d.crop = CGRectMake(r.x, r.y, r.width, r.height);
    _centerX = r.x + r.width / 2; // clamped
    _centerY = r.y + r.height / 2;
    BOOL whole = r.x <= 0 && r.y <= 0 && r.width >= 1 && r.height >= 1;
    // The transform object is written only when it matters, so presets that
    // never use it stay readable as before (and byte-identical).
    d.hasTransform = !d.isTransformIdentity || (mode == HACFramingModeFit && !whole);
}

- (void)didEdit {
    if (_placement == HACSurfaceLock && !self.isAIPreview) _lockOwn = YES;
}

- (void)framingChanged {
    [self didEdit];
    [self applyFramingMode:self.framingMode];
    [self refreshControls];
    [self refreshPreview]; // layout only: applied in place, no reload
}

#pragma mark Controls

- (void)placementChanged {
    self.placement = (HACSurface)_placementSegment.selectedSegmentIndex;
}

- (void)setPlacement:(HACSurface)placement {
    if (self.isAIPreview) return;
    placement = placement == HACSurfaceLock ? HACSurfaceLock : HACSurfaceHome;
    if (placement == HACSurfaceLock && !_lockOwn) {
        // Follows the Home Screen until changed here.
        HCGBackgroundPreset *mirror = [_drafts[HACSurfaceHome] copy];
        _drafts[HACSurfaceLock] = mirror;
    }
    _placement = placement;
    [self syncFramingFromDraft];
    _stage.overlay = placement == HACSurfaceLock ? HACStageOverlayLockClock : HACStageOverlayHomeIcons;
    _overlaySegment.selectedSegmentIndex = _stage.overlay;
    [self refreshControls];
    [self refreshPreview];
}

- (void)overlayChanged {
    _stage.overlay = (HACStageOverlay)_overlaySegment.selectedSegmentIndex;
}

- (void)modeChanged {
    [self setFramingMode:(HACFramingMode)_modeSegment.selectedSegmentIndex];
}

- (void)setFramingMode:(HACFramingMode)mode {
    [self didEdit];
    mode = (HACFramingMode)MAX(0, MIN(2, (NSInteger)mode));
    [self applyFramingMode:mode];
    [self refreshControls];
    [self refreshPreview];
}

- (void)setScaling:(NSInteger)scaling {
    [self didEdit];
    HCGBackgroundPreset *d = [self current];
    d.stretch = NO;
    d.scaling = (HCGBackgroundScaling)MAX(0, MIN(2, scaling));
    if (d.scaling == HCGBackgroundScalingFill) {
        _zoom = 1;
        _centerX = _centerY = 0.5;
        d.crop = CGRectMake(0, 0, 1, 1);
        d.hasTransform = !d.isTransformIdentity;
    } else {
        [self applyFramingMode:self.framingMode];
    }
    [self refreshControls];
    [self refreshPreview];
}

- (void)setZoom:(double)zoom centerX:(double)x centerY:(double)y {
    _zoom = zoom;
    _centerX = x;
    _centerY = y;
    [self framingChanged];
}

- (void)setRotation:(NSInteger)degrees {
    HCGBackgroundPreset *d = [self current];
    NSInteger rotation = hcgbg_rotation_normalize((double)degrees, NULL);
    if (rotation == d.rotation) return;
    // Keep the same part of the picture in the middle.
    CGPoint source = SourceFromDisplayed(CGPointMake(_centerX, _centerY), d.rotation, d.flipHorizontal, d.flipVertical);
    d.rotation = rotation;
    CGPoint shown = DisplayedFromSource(source, d.rotation, d.flipHorizontal, d.flipVertical);
    _centerX = shown.x;
    _centerY = shown.y;
    [self framingChanged];
}

- (void)rotateClockwise {
    [self setRotation:[self current].rotation + 90];
}

- (void)rotationChanged {
    [self setRotation:_rotationSegment.selectedSegmentIndex * 90];
}

- (void)flipChanged {
    [self setFlipHorizontal:_flipHSwitch.on vertical:_flipVSwitch.on];
}

- (void)setFlipHorizontal:(BOOL)horizontal vertical:(BOOL)vertical {
    HCGBackgroundPreset *d = [self current];
    CGPoint source = SourceFromDisplayed(CGPointMake(_centerX, _centerY), d.rotation, d.flipHorizontal, d.flipVertical);
    d.flipHorizontal = horizontal;
    d.flipVertical = vertical;
    CGPoint shown = DisplayedFromSource(source, d.rotation, d.flipHorizontal, d.flipVertical);
    _centerX = shown.x;
    _centerY = shown.y;
    [self framingChanged];
}

- (void)resetTransformations {
    [self didEdit];
    [[self current] resetTransform];
    _zoom = 1;
    _centerX = _centerY = 0.5;
    [self refreshControls];
    [self refreshPreview];
}

- (void)loopChanged {
    [self didEdit];
    [self current].loops = _loopSwitch.on;
    [self refreshPreview];
}

- (void)speedChanged {
    [self didEdit];
    [self current].speed = [Speeds()[(NSUInteger)_speedSegment.selectedSegmentIndex] doubleValue];
    [self refreshPreview];
}

- (void)sliderMoved:(UISlider *)slider {
    [self didEdit];
    HCGBackgroundPreset *d = [self current];
    if (slider == _startSlider) {
        d.trimStart = slider.value;
        if (d.trimEnd - d.trimStart < HCGBG_MIN_CLIP_SECONDS) _endSlider.value = (float)(slider.value + HCGBG_MIN_CLIP_SECONDS);
        d.trimEnd = _endSlider.value;
    } else if (slider == _endSlider) {
        d.trimEnd = slider.value;
        if (d.trimEnd - d.trimStart < HCGBG_MIN_CLIP_SECONDS)
            _startSlider.value = (float)MAX(0.0, slider.value - HCGBG_MIN_CLIP_SECONDS);
        d.trimStart = _startSlider.value;
    } else if (slider == _stillSlider) {
        d.stillTime = slider.value;
    } else if (slider == _zoomSlider || slider == _xSlider || slider == _ySlider) {
        _zoom = _zoomSlider.value;
        _centerX = _xSlider.value;
        _centerY = _ySlider.value;
        [self framingChanged];
        return;
    }
    _stage.background.display = HCGBackgroundDisplayPlaying;
    [self refreshControls];
}

- (void)sliderReleased:(UISlider *)slider {
    [[self current] sanitizeWithError:NULL];
    [self refreshControls];
    [self refreshPreview];
}

- (void)panned:(UIPanGestureRecognizer *)pan {
    CGRect frame = _stage.background.mediaFrame;
    if (frame.size.width < 1 || frame.size.height < 1) return;
    if (pan.state == UIGestureRecognizerStateBegan) _panStartCenter = CGPointMake(_centerX, _centerY);
    CGPoint t = [pan translationInView:_stage];
    // Dragging the picture right shows more of its left side. The frame is the
    // displayed picture, which is what the position is normalised to.
    _centerX = _panStartCenter.x - t.x / frame.size.width;
    _centerY = _panStartCenter.y - t.y / frame.size.height;
    [self framingChanged];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    NSString *name = [textField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length) {
        for (HCGBackgroundPreset *d in _drafts) d.name = name; // shared by every placement
        self.title = name;
    }
}

#pragma mark Saving

- (BOOL)save:(NSError **)error {
    [_nameField resignFirstResponder];
    if (self.isAIPreview) return YES;
    if (![self savePlacement:HACSurfaceHome error:error]) return NO;
    if (_lockOwn) return [self savePlacement:HACSurfaceLock error:error];
    if (_lockOwnSaved) {
        if (![[HACLibrary shared] removeOwnLockSettingsOfItem:_item error:error]) return NO;
        _lockOwnSaved = NO;
        _originals[HACSurfaceLock] = [_originals[HACSurfaceHome] copy];
        if (_onChange) _onChange();
    }
    return YES;
}

- (BOOL)savePlacement:(HACSurface)placement error:(NSError **)error {
    HCGBackgroundPreset *draft = _drafts[placement], *original = _originals[placement];
    if (![draft sanitizeWithError:error]) return NO;
    BOOL wasOwn = placement == HACSurfaceHome || _lockOwnSaved;
    BOOL stillChanged = !draft.stillFile || fabs(draft.stillTime - original.stillTime) > 0.01;
    if (wasOwn && !stillChanged && [[draft dictionaryRepresentation] isEqual:[original dictionaryRepresentation]])
        return YES;
    if (stillChanged && ![HACMediaImporter writeStillForItem:draft placement:placement error:error]) return NO;
    HACLibrary *library = [HACLibrary shared];
    if (![library updateItem:draft placement:placement error:error]) return NO;
    // The library may have given the placement its own still file.
    HCGBackgroundPreset *saved = [library presetForItem:draft placement:placement] ?: [draft copy];
    _drafts[placement] = saved;
    _originals[placement] = [saved copy];
    if (placement == HACSurfaceLock) _lockOwnSaved = YES;
    if (placement == _placement) [self refreshPreview];
    if (_onChange) _onChange();
    return YES;
}

- (void)useHomeSettingsForLock {
    if (self.isAIPreview) return;
    _lockOwn = NO;
    _drafts[HACSurfaceLock] = [_drafts[HACSurfaceHome] copy];
    if (_placement == HACSurfaceLock) [self syncFramingFromDraft];
    NSError *error = nil;
    if (![self save:&error]) [self showError:error title:@"Could Not Save"];
    [self refreshControls];
    [self refreshPreview];
}

- (void)showError:(NSError *)error title:(NSString *)title {
    if (!self.viewIfLoaded.window) {
        NSLog(@"[HCGAnimationCenter] %@: %@", title, error.localizedDescription);
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:error.localizedDescription
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark Apply

- (void)applyHome {
    [self applyToSurface:HACSurfaceHome];
}

- (void)applyLock {
    [self applyToSurface:HACSurfaceLock];
}

- (void)applyToSurface:(HACSurface)surface {
    HACSettings *settings = [HACPreferences loadSettings];
    if (surface == HACSurfaceLock && !settings.lockEnabled) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Lock Screen Is Experimental"
                             message:@"In this beta the Lock Screen background is checked at run time: if your iOS "
                                     @"version doesn't offer a safe place for it, nothing is drawn and your normal Lock "
                                     @"Screen shows. Settings then says why."
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Turn On and Apply"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
                                                    [HACPreferences setValue:@YES forKey:HACKeyLockEnabled];
                                                    [self applyToSurface:HACSurfaceLock];
                                                }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (surface == HACSurfaceHome && !settings.homeEnabled) [HACPreferences setValue:@YES forKey:HACKeyHomeEnabled];

    if (self.isAIPreview) {
        [self adoptAIResultThen:^(HCGBackgroundPreset *item) {
            [HACLibrary assignPreset:item toSurface:surface];
            [self finishApplyTo:surface];
        }];
        return;
    }
    NSError *error = nil;
    if (![self save:&error]) {
        [self showError:error title:@"Could Not Save"];
        return;
    }
    // Each screen gets its own placement's settings.
    HCGBackgroundPreset *preset = [[HACLibrary shared] presetForItem:_item placement:surface] ?: [self current];
    [HACLibrary assignPreset:preset toSurface:surface];
    [self finishApplyTo:surface];
}

- (void)finishApplyTo:(HACSurface)surface {
    if (_onChange) _onChange();
    if (!self.viewIfLoaded.window) return; // driven by a test or the preview harness
    NSString *where = surface == HACSurfaceLock ? @"Lock Screen" : @"Home Screen";
    if (![HACPreferences loadSettings].enabled) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:[NSString stringWithFormat:@"Applied to the %@", where]
                             message:@"HCG Animation Center is off, so your normal wallpaper still shows. Turn it on now?"
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Not Now" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Turn On"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
                                                    [HACPreferences setValue:@YES forKey:HACKeyEnabled];
                                                    if (self->_onChange) self->_onChange();
                                                }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIAlertController *done = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Applied to the %@", where]
                                                                  message:@"No respring needed."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:done animated:YES completion:nil];
}

#pragma mark AI preview

- (void)adoptAIResultThen:(void (^)(HCGBackgroundPreset *item))then {
    if (_adopted) return;
    NSError *error = nil;
    NSURL *staged = [HACMediaImporter stageFileAtURL:_aiResult.previewFile error:&error];
    if (!staged) {
        [self showError:error title:@"Could Not Save"];
        return;
    }
    [_spinner startAnimating];
    self.view.userInteractionEnabled = NO;
    static HACMediaImporter *importer;
    if (!importer) importer = [[HACMediaImporter alloc] init];
    HCGBackgroundPreset *draft = [[self current] copy];
    NSDictionary *generator = _aiResult.generatorInfo;
    [importer importStagedFile:staged
                 suggestedName:draft.name
                      progress:nil
                    completion:^(HCGBackgroundPreset *item, NSError *importError) {
                        [self->_spinner stopAnimating];
                        self.view.userInteractionEnabled = YES;
                        if (!item) {
                            [self showError:importError title:@"Could Not Save"];
                            return;
                        }
                        // The user's edits and the generator record go with the adopted item.
                        item.name = draft.name;
                        item.origin = @"ai";
                        item.trimStart = draft.trimStart;
                        item.trimEnd = draft.trimEnd;
                        item.loops = draft.loops;
                        item.speed = draft.speed;
                        item.scaling = draft.scaling;
                        item.crop = draft.crop;
                        item.backgroundColor = draft.backgroundColor;
                        item.rotation = draft.rotation;
                        item.flipHorizontal = draft.flipHorizontal;
                        item.flipVertical = draft.flipVertical;
                        item.stretch = draft.stretch;
                        item.hasTransform = draft.hasTransform;
                        item.stillTime = draft.stillTime;
                        NSMutableDictionary *g = [generator mutableCopy] ?: [NSMutableDictionary dictionary];
                        g[@"kind"] = @"ai";
                        item.generator = g;
                        NSError *e = nil;
                        [HACMediaImporter writeStillAndThumbnailForItem:item error:&e];
                        [[HACLibrary shared] updateItem:item error:&e];
                        self->_adopted = YES;
                        [HACAIGeneration discardResult:self->_aiResult];
                        then(item);
                    }];
}

- (void)saveAI {
    [self adoptAIResultThen:^(HCGBackgroundPreset *item) {
        if (self->_onChange) self->_onChange();
        [self.navigationController popViewControllerAnimated:YES];
    }];
}

- (void)discardAI {
    [HACAIGeneration discardResult:_aiResult];
    _adopted = NO;
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark Export, delete

- (void)exportPreset:(UIButton *)sender {
    NSError *error = nil;
    if (![self save:&error]) {
        [self showError:error title:@"Could Not Save"];
        return;
    }
    NSString *placementName = _placement == HACSurfaceLock ? @"Lock Screen" : @"Home Screen";
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Export"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak HACEditorViewController *weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ Preset (.hcgbackground)", placementName]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
                                                [weakSelf shareExport:NO from:sender];
                                            }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Animation Pack, All Screens (.hcgpack)"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
                                                [weakSelf shareExport:YES from:sender];
                                            }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = sender;
    sheet.popoverPresentationController.sourceRect = sender.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)shareExport:(BOOL)pack from:(UIView *)sender {
    NSError *error = nil;
    HACLibrary *library = [HACLibrary shared];
    NSURL *folder = pack ? [library exportPackForItem:_item error:&error]
                         : [library exportItem:_item placement:_placement error:&error];
    if (!folder) {
        [self showError:error title:@"Could Not Export"];
        return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[ folder ]
                                                                        applicationActivities:nil];
    share.popoverPresentationController.sourceView = sender;
    share.popoverPresentationController.sourceRect = sender.bounds;
    [self presentViewController:share animated:YES completion:nil];
}

- (void)deleteItem {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"Delete “%@”?", [self current].name]
                         message:@"The video and its stills are removed. If it is in use, that screen goes back to your "
                                 @"normal wallpaper."
                  preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
                                                NSError *error = nil;
                                                self->_deleted = YES;
                                                self->_stage.background.display = HCGBackgroundDisplayNone;
                                                [self->_stage.background setPreset:nil folder:nil];
                                                if (![[HACLibrary shared] removeItem:self->_item error:&error]) {
                                                    [self showError:error title:@"Could Not Delete"];
                                                    return;
                                                }
                                                if (self->_onChange) self->_onChange();
                                                [self.navigationController popViewControllerAnimated:YES];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = self.view;
    [self presentViewController:alert animated:YES completion:nil];
}

@end
