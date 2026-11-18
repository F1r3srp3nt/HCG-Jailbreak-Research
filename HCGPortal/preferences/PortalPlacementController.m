//
//  PortalPlacementController.m
//  HCG Portal — Hakmi Capital Group
//

#import "PortalPlacementController.h"

#import "PortalPreferences.h"
#import "PortalPreviewView.h"
#import "PortalTheme.h"

#import <objc/runtime.h>

static char kTitleKey;
static void SetTitleFor(UISlider *slider, UILabel *title) {
    objc_setAssociatedObject(slider, &kTitleKey, title, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static UILabel *TitleFor(UISlider *slider) {
    return objc_getAssociatedObject(slider, &kTitleKey);
}

@implementation PortalPlacementController {
    UIScrollView *_scroll;
    PortalPreviewView *_preview;
    UISegmentedControl *_sample;
    UISlider *_size, *_horizontal, *_vertical;
    UILabel *_sizeValue, *_horizontalValue, *_verticalValue;
    UILabel *_result;
    UIButton *_reset;
    PortalPlacement _placement;
    PortalPlacement _dragStart;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Position & Size";
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = PortalTheme.background;
    self.view.tintColor = PortalTheme.cyan;

    _scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scroll.alwaysBounceVertical = YES;
    [self.view addSubview:_scroll];

    _preview = [[PortalPreviewView alloc] initWithFrame:CGRectZero];
    _preview.accessibilityHint = @"Drag the portal to move it. Use the sliders below for exact values.";
    [_scroll addSubview:_preview];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)];
    [_preview addGestureRecognizer:pan];
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinched:)];
    [_preview addGestureRecognizer:pinch];

    _sample = [[UISegmentedControl alloc] initWithItems:@[ @"Empty", @"Notifications", @"+ Media" ]];
    _sample.selectedSegmentIndex = 0;
    _sample.accessibilityLabel = @"Preview content";
    [_sample addTarget:self action:@selector(sampleChanged) forControlEvents:UIControlEventValueChanged];
    [_scroll addSubview:_sample];

    _result = [[UILabel alloc] init];
    _result.numberOfLines = 0;
    _result.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _result.adjustsFontForContentSizeCategory = YES;
    _result.textColor = PortalTheme.textSecondary;
    [_scroll addSubview:_result];

    _size = [self sliderMin:PORTAL_SIZE_MIN max:PORTAL_SIZE_MAX label:@"Size"];
    _horizontal = [self sliderMin:-PORTAL_OFFSET_X_LIMIT max:PORTAL_OFFSET_X_LIMIT label:@"Horizontal position"];
    _vertical = [self sliderMin:PORTAL_OFFSET_Y_MIN max:PORTAL_OFFSET_Y_MAX label:@"Distance below the clock"];
    _sizeValue = [self valueLabel];
    _horizontalValue = [self valueLabel];
    _verticalValue = [self valueLabel];

    _reset = [UIButton buttonWithType:UIButtonTypeSystem];
    [_reset setTitle:@"Reset Position & Size" forState:UIControlStateNormal];
    [_reset setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    _reset.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _reset.backgroundColor = PortalTheme.panel;
    _reset.layer.cornerRadius = 12;
    [_reset addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:_reset];

    [self reload];
}

- (UISlider *)sliderMin:(double)min max:(double)max label:(NSString *)label {
    UISlider *s = [[UISlider alloc] init];
    s.minimumValue = (float)min;
    s.maximumValue = (float)max;
    s.minimumTrackTintColor = PortalTheme.cyan;
    s.maximumTrackTintColor = [PortalTheme.deepViolet colorWithAlphaComponent:0.35];
    s.accessibilityLabel = label;
    [s addTarget:self action:@selector(sliderMoved:) forControlEvents:UIControlEventValueChanged];
    [s addTarget:self action:@selector(save) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [_scroll addSubview:s];
    UILabel *title = [[UILabel alloc] init];
    title.text = label;
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    title.textColor = PortalTheme.textPrimary;
    title.isAccessibilityElement = NO;
    SetTitleFor(s, title);
    [_scroll addSubview:title];
    return s;
}

- (UILabel *)valueLabel {
    UILabel *l = [[UILabel alloc] init];
    l.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightMedium];
    l.textColor = PortalTheme.cyan;
    l.textAlignment = NSTextAlignmentRight;
    l.isAccessibilityElement = NO;
    [_scroll addSubview:l];
    return l;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat W = self.view.bounds.size.width, margin = 20;
    CGFloat inner = W - 2 * margin;
    CGSize screen = _preview.screenSize;
    CGFloat previewH = MIN(self.view.bounds.size.height * 0.55, 460);
    CGFloat previewW = previewH * screen.width / screen.height;
    _preview.frame = CGRectMake((W - previewW) / 2, 16, previewW, previewH);
    CGFloat y = CGRectGetMaxY(_preview.frame) + 14;
    _sample.frame = CGRectMake(margin, y, inner, 32);
    y += 44;
    CGSize fit = [_result sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)];
    _result.frame = CGRectMake(margin, y, inner, fit.height);
    y += fit.height + 14;
    NSArray *rows = @[ @[ _size, _sizeValue ], @[ _horizontal, _horizontalValue ], @[ _vertical, _verticalValue ] ];
    for (NSArray *row in rows) {
        UISlider *s = row[0];
        UILabel *value = row[1];
        TitleFor(s).frame = CGRectMake(margin, y, inner - 80, 22);
        value.frame = CGRectMake(W - margin - 80, y, 80, 22);
        y += 26;
        s.frame = CGRectMake(margin, y, inner, 44); // 44 pt touch height
        y += 52;
    }
    _reset.frame = CGRectMake(margin, y + 6, inner, 50);
    _scroll.contentSize = CGSizeMake(W, CGRectGetMaxY(_reset.frame) + 30);
}

#pragma mark Model

- (void)reload {
    PortalSettings *settings = [PortalPreferences loadSettings];
    _placement = settings.placement;
    [_preview reloadWithSettings:settings];
    [self showPlacement];
}

- (void)showPlacement {
    [_preview setPlacement:_placement];
    _size.value = (float)_placement.size;
    _horizontal.value = (float)_placement.offsetX;
    _vertical.value = (float)_placement.offsetY;
    _sizeValue.text = [NSString stringWithFormat:@"%.0f pt", _placement.size];
    _horizontalValue.text = [NSString stringWithFormat:@"%+.0f pt", _placement.offsetX];
    _verticalValue.text = [NSString stringWithFormat:@"%.0f pt", _placement.offsetY];
    _size.accessibilityValue = _sizeValue.text;
    _horizontal.accessibilityValue = _horizontalValue.text;
    _vertical.accessibilityValue = _verticalValue.text;
    PortalLayout l = _preview.layout;
    NSString *what;
    switch (l.mode) {
        case PORTAL_LAYOUT_FULL: what = @"Shown at the chosen size."; break;
        case PORTAL_LAYOUT_REDUCED: what = [NSString stringWithFormat:@"Reduced to %.0f pt to stay clear of what is below it.", l.diameter]; break;
        case PORTAL_LAYOUT_COMPACT: what = @"Collapsed to a compact orb: there is little room between the clock and what is below it."; break;
        default: what = @"Hidden: no room between the clock and what is below it. It returns when there is."; break;
    }
    _result.text = [NSString stringWithFormat:@"%@ The portal always stays below the clock and widgets and above notifications, "
                                              @"media controls, the flashlight and the camera. On the phone the real Lock "
                                              @"Screen is measured.",
                                              what];
    [self.view setNeedsLayout];
}

- (void)save {
    portal_placement_clamp(&_placement);
    CFPreferencesSetAppValue((__bridge CFStringRef)PortalKeySize, (__bridge CFPropertyListRef) @(round(_placement.size)),
                             (__bridge CFStringRef)PortalPreferencesDomain);
    CFPreferencesSetAppValue((__bridge CFStringRef)PortalKeyOffsetX, (__bridge CFPropertyListRef) @(round(_placement.offsetX)),
                             (__bridge CFStringRef)PortalPreferencesDomain);
    [PortalPreferences setValue:@(round(_placement.offsetY)) forKey:PortalKeyOffsetY]; // synchronises and notifies
}

#pragma mark Input

- (void)sliderMoved:(UISlider *)slider {
    if (slider == _size) _placement.size = round(slider.value);
    if (slider == _horizontal) _placement.offsetX = round(slider.value);
    if (slider == _vertical) _placement.offsetY = round(slider.value);
    [self showPlacement];
}

- (void)dragged:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateBegan) _dragStart = _placement;
    CGPoint a = [_preview screenPointFromPoint:CGPointZero];
    CGPoint b = [_preview screenPointFromPoint:[pan translationInView:_preview]];
    _placement.offsetX = round(_dragStart.offsetX + (b.x - a.x));
    _placement.offsetY = round(_dragStart.offsetY + (b.y - a.y));
    portal_placement_clamp(&_placement);
    [self showPlacement];
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) [self save];
}

- (void)pinched:(UIPinchGestureRecognizer *)pinch {
    if (pinch.state == UIGestureRecognizerStateBegan) _dragStart = _placement;
    _placement.size = round(_dragStart.size * pinch.scale);
    portal_placement_clamp(&_placement);
    [self showPlacement];
    if (pinch.state == UIGestureRecognizerStateEnded || pinch.state == UIGestureRecognizerStateCancelled) [self save];
}

- (void)sampleChanged {
    _preview.showsNotifications = _sample.selectedSegmentIndex >= 1;
    _preview.showsMedia = _sample.selectedSegmentIndex == 2;
    [self showPlacement];
}

- (void)resetTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset Position & Size"
                                                                   message:@"Return the portal's size and position to the "
                                                                           @"defaults? Colours and other settings are kept."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
                                                [PortalPreferences removeKeys:[PortalPreferences placementKeys]];
                                                [self reload];
                                            }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
