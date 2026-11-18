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

@interface HACEditorViewController () <UITextFieldDelegate>
@end

@implementation HACEditorViewController {
    HCGBackgroundPreset *_original;
    HCGBackgroundPreset *_draft;
    HACAIResult *_aiResult;
    NSURL *_folder;
    HACSurface _preferred;
    BOOL _adopted;
    BOOL _deleted;

    HACPreviewStage *_stage;
    UIStackView *_stack;
    UILabel *_info;
    UITextField *_nameField;
    UISlider *_startSlider, *_endSlider, *_zoomSlider, *_stillSlider;
    UILabel *_startLabel, *_endLabel, *_zoomLabel, *_stillLabel;
    UISegmentedControl *_overlaySegment, *_scalingSegment, *_speedSegment;
    UISwitch *_loopSwitch;
    UIView *_cropControls;
    UIActivityIndicatorView *_spinner;
    double _zoom, _centerX, _centerY;
    CGPoint _panStartCenter;
}

- (instancetype)initWithItem:(HCGBackgroundPreset *)item preferredSurface:(HACSurface)surface {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _original = [item copy];
        _draft = [item copy];
        _folder = [HACPreferences mediaFolder];
        _preferred = surface;
        self.title = item.name;
    }
    return self;
}

- (instancetype)initWithAIResult:(HACAIResult *)result draft:(HCGBackgroundPreset *)draft {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _aiResult = result;
        _original = [draft copy];
        _draft = [draft copy];
        _folder = [result.previewFile URLByDeletingLastPathComponent];
        _preferred = HACSurfaceHome;
        self.title = @"AI Preview";
    }
    return self;
}

- (BOOL)isAIPreview {
    return _aiResult != nil;
}

- (HCGBackgroundPreset *)draft {
    return [_draft copy];
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

    // Preview
    _stage = [[HACPreviewStage alloc] initWithFrame:CGRectZero];
    _stage.translatesAutoresizingMaskIntoConstraints = NO;
    _stage.overlay = _preferred == HACSurfaceLock ? HACStageOverlayLockClock : HACStageOverlayHomeIcons;
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
    _nameField.text = _draft.name;
    _nameField.delegate = self;
    _nameField.returnKeyType = UIReturnKeyDone;
    _nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
    [_stack addArrangedSubview:_nameField];

    // Trim
    [_stack addArrangedSubview:[self header:@"Trim"]];
    _startSlider = [self slider];
    _endSlider = [self slider];
    _startLabel = [self valueLabel];
    _endLabel = [self valueLabel];
    for (UISlider *s in @[ _startSlider, _endSlider ]) {
        s.minimumValue = 0;
        s.maximumValue = (float)_draft.duration;
    }
    _startSlider.value = (float)_draft.trimStart;
    _endSlider.value = (float)_draft.trimEnd;
    [_stack addArrangedSubview:[self row:@"Start" control:_startSlider value:_startLabel]];
    [_stack addArrangedSubview:[self row:@"End" control:_endSlider value:_endLabel]];

    // Scaling
    [_stack addArrangedSubview:[self header:@"Scaling"]];
    _scalingSegment = [[UISegmentedControl alloc] initWithItems:@[ @"Fill", @"Fit", @"Crop" ]];
    _scalingSegment.selectedSegmentIndex = _draft.scaling;
    [_scalingSegment addTarget:self action:@selector(scalingChanged) forControlEvents:UIControlEventValueChanged];
    [_stack addArrangedSubview:_scalingSegment];
    _zoomSlider = [self slider];
    _zoomSlider.minimumValue = 1;
    _zoomSlider.maximumValue = 5;
    _zoomLabel = [self valueLabel];
    UIStackView *crop = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self row:@"Zoom" control:_zoomSlider value:_zoomLabel],
        [self footnote:@"Drag the preview to choose which part of the video fills the screen."],
    ]];
    crop.axis = UILayoutConstraintAxisVertical;
    crop.spacing = 6;
    _cropControls = crop;
    [_stack addArrangedSubview:crop];
    HCGBGSize container = {screen.width, screen.height}, media = {_draft.mediaSize.width, _draft.mediaSize.height};
    CGRect c = _draft.crop;
    _zoom = hcgbg_zoom_for_crop(container, media, (HCGBGRect){c.origin.x, c.origin.y, c.size.width, c.size.height});
    _centerX = c.origin.x + c.size.width / 2;
    _centerY = c.origin.y + c.size.height / 2;
    _zoomSlider.value = (float)_zoom;

    // Playback
    [_stack addArrangedSubview:[self header:@"Playback"]];
    _loopSwitch = [[UISwitch alloc] init];
    _loopSwitch.on = _draft.loops;
    _loopSwitch.onTintColor = HACAccentColor();
    [_loopSwitch addTarget:self action:@selector(loopChanged) forControlEvents:UIControlEventValueChanged];
    [_stack addArrangedSubview:[self row:@"Loop" control:_loopSwitch value:nil]];
    NSMutableArray *speedTitles = [NSMutableArray array];
    for (NSNumber *n in Speeds()) [speedTitles addObject:[NSString stringWithFormat:@"%g×", n.doubleValue]];
    _speedSegment = [[UISegmentedControl alloc] initWithItems:speedTitles];
    [_speedSegment addTarget:self action:@selector(speedChanged) forControlEvents:UIControlEventValueChanged];
    [self selectSpeed];
    [_stack addArrangedSubview:_speedSegment];
    [_stack addArrangedSubview:[self footnote:@"Backgrounds always play muted. Without Loop, the clip plays once each "
                                              @"time the screen shows it, then holds its last frame."]];

    // Still
    [_stack addArrangedSubview:[self header:@"Still Image"]];
    _stillSlider = [self slider];
    _stillLabel = [self valueLabel];
    _stillSlider.minimumValue = 0;
    _stillSlider.maximumValue = (float)_draft.duration;
    _stillSlider.value = (float)_draft.stillTime;
    [_stack addArrangedSubview:[self row:@"Frame" control:_stillSlider value:_stillLabel]];
    [_stack addArrangedSubview:[self footnote:@"Shown instead of the video when Reduce Motion or Low Power Mode is on, "
                                              @"when the device is hot, or if the video can't play."]];

    // Actions
    [_stack addArrangedSubview:[self header:@""]];
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
        UIButton *export = HACMakeButton(@"Export Preset…", @"square.and.arrow.up", NO);
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

    for (UISlider *s in @[ _startSlider, _endSlider, _zoomSlider, _stillSlider ]) {
        [s addTarget:self action:@selector(sliderMoved:) forControlEvents:UIControlEventValueChanged];
        [s addTarget:self
                      action:@selector(sliderReleased:)
            forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    }
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
        [self saveDraftQuietly];
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
    [label.widthAnchor constraintEqualToConstant:56].active = YES;
    NSMutableArray *views = [NSMutableArray arrayWithObjects:label, control, nil];
    if (value) [views addObject:value];
    if ([control isKindOfClass:[UISwitch class]]) {
        [views insertObject:[[UIView alloc] init] atIndex:1]; // spacer
        [label.widthAnchor constraintEqualToConstant:56].active = NO;
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
        double delta = fabs([speeds[i] doubleValue] - _draft.speed);
        if (delta < bestDelta) {
            bestDelta = delta;
            best = (NSInteger)i;
        }
    }
    _speedSegment.selectedSegmentIndex = best;
}

- (void)refreshControls {
    _info.text = [NSString stringWithFormat:@"%@ · clip %@", HACDescribePreset(_draft), HACFormatSeconds(_draft.clipDuration)];
    _startLabel.text = HACFormatSeconds(_draft.trimStart);
    _endLabel.text = HACFormatSeconds(_draft.trimEnd);
    _stillLabel.text = HACFormatSeconds(_draft.stillTime);
    _zoomLabel.text = [NSString stringWithFormat:@"%.1f×", _zoom];
    _cropControls.hidden = _draft.scaling != HCGBackgroundScalingCrop;
    _scalingSegment.selectedSegmentIndex = _draft.scaling;
    _loopSwitch.on = _draft.loops;
}

- (void)refreshPreview {
    [_stage.background setPreset:_draft folder:_folder];
    _stage.background.display = HCGBackgroundDisplayPlaying;
}

- (void)overlayChanged {
    _stage.overlay = (HACStageOverlay)_overlaySegment.selectedSegmentIndex;
}

- (void)scalingChanged {
    [self setScaling:_scalingSegment.selectedSegmentIndex];
}

- (void)setScaling:(NSInteger)scaling {
    _draft.scaling = (HCGBackgroundScaling)MAX(0, MIN(2, scaling));
    if (_draft.scaling == HCGBackgroundScalingCrop) [self updateCrop];
    [self refreshControls];
    [self refreshPreview];
}

- (void)setZoom:(double)zoom centerX:(double)x centerY:(double)y {
    _zoom = zoom;
    _centerX = x;
    _centerY = y;
    _zoomSlider.value = (float)zoom;
    [self updateCrop];
    [self refreshControls];
    [self refreshPreview];
}

- (void)updateCrop {
    CGSize screen = _stage.screenSize;
    HCGBGRect r = hcgbg_crop_from_zoom((HCGBGSize){screen.width, screen.height},
                                       (HCGBGSize){_draft.mediaSize.width, _draft.mediaSize.height}, _zoom, _centerX,
                                       _centerY);
    _draft.crop = CGRectMake(r.x, r.y, r.width, r.height);
    _centerX = r.x + r.width / 2; // clamped
    _centerY = r.y + r.height / 2;
}

- (void)loopChanged {
    _draft.loops = _loopSwitch.on;
    [self refreshPreview];
}

- (void)speedChanged {
    _draft.speed = [Speeds()[(NSUInteger)_speedSegment.selectedSegmentIndex] doubleValue];
    [self refreshPreview];
}

- (void)sliderMoved:(UISlider *)slider {
    if (slider == _startSlider) {
        _draft.trimStart = slider.value;
        if (_draft.trimEnd - _draft.trimStart < HCGBG_MIN_CLIP_SECONDS) _endSlider.value = (float)(slider.value + HCGBG_MIN_CLIP_SECONDS);
        _draft.trimEnd = _endSlider.value;
    } else if (slider == _endSlider) {
        _draft.trimEnd = slider.value;
        if (_draft.trimEnd - _draft.trimStart < HCGBG_MIN_CLIP_SECONDS)
            _startSlider.value = (float)MAX(0.0, slider.value - HCGBG_MIN_CLIP_SECONDS);
        _draft.trimStart = _startSlider.value;
    } else if (slider == _stillSlider) {
        _draft.stillTime = slider.value;
    } else if (slider == _zoomSlider) {
        _zoom = slider.value;
        [self updateCrop];
        [self refreshPreview]; // layout only: applied in place
    }
    _stage.background.display = HCGBackgroundDisplayPlaying;
    [self refreshControls];
}

- (void)sliderReleased:(UISlider *)slider {
    [_draft sanitizeWithError:NULL];
    _startSlider.value = (float)_draft.trimStart;
    _endSlider.value = (float)_draft.trimEnd;
    _stillSlider.value = (float)_draft.stillTime;
    [self refreshControls];
    [self refreshPreview];
}

- (void)panned:(UIPanGestureRecognizer *)pan {
    if (_draft.scaling != HCGBackgroundScalingCrop) return;
    CGRect frame = _stage.background.mediaFrame;
    if (frame.size.width < 1 || frame.size.height < 1) return;
    if (pan.state == UIGestureRecognizerStateBegan) _panStartCenter = CGPointMake(_centerX, _centerY);
    CGPoint t = [pan translationInView:_stage];
    // Dragging the picture right shows more of its left side.
    _centerX = _panStartCenter.x - t.x / frame.size.width;
    _centerY = _panStartCenter.y - t.y / frame.size.height;
    [self updateCrop];
    [self refreshPreview];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    NSString *name = [textField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length) {
        _draft.name = name;
        self.title = name;
    }
}

#pragma mark Saving

- (BOOL)saveDraft:(NSError **)error {
    [_nameField resignFirstResponder];
    if (![_draft sanitizeWithError:error]) return NO;
    BOOL stillChanged = fabs(_draft.stillTime - _original.stillTime) > 0.01 || !_draft.stillFile;
    if (stillChanged && ![HACMediaImporter writeStillAndThumbnailForItem:_draft error:error]) return NO;
    if ([[_draft dictionaryRepresentation] isEqual:[_original dictionaryRepresentation]] && !stillChanged) return YES;
    if (![[HACLibrary shared] updateItem:_draft error:error]) return NO;
    _original = [_draft copy];
    if (_onChange) _onChange();
    return YES;
}

- (void)saveDraftQuietly {
    NSError *error = nil;
    if (![self saveDraft:&error]) NSLog(@"[HCGAnimationCenter] could not save edits: %@", error.localizedDescription);
}

- (void)showError:(NSError *)error title:(NSString *)title {
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
    if (![self saveDraft:&error]) {
        [self showError:error title:@"Could Not Save"];
        return;
    }
    [HACLibrary assignPreset:_draft toSurface:surface];
    [self finishApplyTo:surface];
}

- (void)finishApplyTo:(HACSurface)surface {
    if (_onChange) _onChange();
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
    HCGBackgroundPreset *draft = [_draft copy];
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
    if (![self saveDraft:&error]) {
        [self showError:error title:@"Could Not Save"];
        return;
    }
    NSURL *folder = [[HACLibrary shared] exportItem:_draft error:&error];
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
        alertControllerWithTitle:[NSString stringWithFormat:@"Delete “%@”?", _draft.name]
                         message:@"The video and its still are removed. If it is in use, that screen goes back to your "
                                 @"normal wallpaper."
                  preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
                                                NSError *error = nil;
                                                self->_deleted = YES;
                                                self->_stage.background.display = HCGBackgroundDisplayNone;
                                                [self->_stage.background setPreset:nil folder:nil];
                                                if (![[HACLibrary shared] removeItem:self->_original error:&error]) {
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
