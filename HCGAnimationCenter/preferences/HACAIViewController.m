//
//  HACAIViewController.m
//  HCG Animation Center — Hakmi Capital Group
//

#import "HACAIViewController.h"
#import "HACAIGeneration.h"
#import "HACEditorViewController.h"
#import "HACTheme.h"

#import <AVFoundation/AVFoundation.h>

@implementation HACAIViewController {
    UILabel *_accessLabel;
    UITextView *_prompt;
    UISegmentedControl *_style;
    UIButton *_generate;
    UIProgressView *_progress;
    UILabel *_phase;
    BOOL _running;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"AI Backgrounds";
    HACApplyTheme(self);
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:safe.topAnchor constant:16],
        [stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
    ]];

    UILabel *intro = [[UILabel alloc] init];
    intro.numberOfLines = 0;
    intro.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    intro.text = @"Describe a background and HCG AI makes a short looping video. You see it as a preview first: nothing "
                 @"is saved or applied until you choose Apply or Save to Library.";
    [stack addArrangedSubview:intro];

    _accessLabel = [[UILabel alloc] init];
    _accessLabel.numberOfLines = 0;
    _accessLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _accessLabel.textColor = UIColor.secondaryLabelColor;
    [stack addArrangedSubview:_accessLabel];

    _prompt = [[UITextView alloc] init];
    _prompt.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _prompt.layer.cornerRadius = 10;
    _prompt.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    _prompt.accessibilityLabel = @"Description";
    [_prompt.heightAnchor constraintEqualToConstant:96].active = YES;
    [stack addArrangedSubview:_prompt];

    _style = [[UISegmentedControl alloc] initWithItems:@[ @"Calm", @"Vivid", @"Abstract" ]];
    _style.selectedSegmentIndex = 0;
    [stack addArrangedSubview:_style];

    _generate = HACMakeButton(@"Generate Preview", @"sparkles", YES);
    [_generate addTarget:self action:@selector(generateTapped) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:_generate];
    _progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _progress.progressTintColor = HACAccentColor();
    _progress.hidden = YES;
    _phase = [[UILabel alloc] init];
    _phase.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _phase.textColor = UIColor.secondaryLabelColor;
    [stack addArrangedSubview:_progress];
    [stack addArrangedSubview:_phase];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshAccess];
}

- (void)refreshAccess {
    id<HACAIGenerationProvider> provider = [HACAIGeneration provider];
    HACAIAccess *access = [provider currentAccess];
    NSString *state = @[ @"Not connected", @"Sign in needed", @"Not included in your access", @"Available" ][(NSUInteger)access.state];
    _accessLabel.text = [NSString stringWithFormat:@"%@: %@. %@", provider.providerName, state, access.explanation];
    BOOL allowed = access.state == HACAIAccessAllowed;
    _generate.enabled = allowed && !_running;
    _prompt.editable = allowed;
    _prompt.alpha = allowed ? 1 : 0.5;
}

- (void)generateTapped {
    [self generateWithPrompt:_prompt.text ?: @""];
}

- (void)generateWithPrompt:(NSString *)prompt {
    id<HACAIGenerationProvider> provider = [HACAIGeneration provider];
    if ([provider currentAccess].state != HACAIAccessAllowed) {
        [self refreshAccess];
        return;
    }
    HACAIRequest *request = [[HACAIRequest alloc] init];
    request.prompt = prompt;
    request.style = @[ @"calm", @"vivid", @"abstract" ][(NSUInteger)MAX(0, _style.selectedSegmentIndex)];
    CGRect native = UIScreen.mainScreen.nativeBounds;
    request.pixelSize = CGSizeMake(MIN(native.size.width, native.size.height), MAX(native.size.width, native.size.height));
    NSString *problem = [request validationProblem];
    if (problem) {
        _phase.text = problem;
        return;
    }
    _running = YES;
    _progress.hidden = NO;
    _progress.progress = 0;
    [self refreshAccess];
    __weak HACAIViewController *weakSelf = self;
    [provider generate:request
        progress:^(double fraction, NSString *phase) {
            dispatch_async(dispatch_get_main_queue(), ^{
                HACAIViewController *strong = weakSelf;
                [strong->_progress setProgress:(float)fraction animated:YES];
                strong->_phase.text = phase;
            });
        }
        completion:^(HACAIResult *result, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf finishedWithResult:result error:error];
            });
        }];
}

- (void)finishedWithResult:(HACAIResult *)result error:(NSError *)error {
    _running = NO;
    _progress.hidden = YES;
    [self refreshAccess];
    if (!result) {
        _phase.text = error.localizedDescription ?: @"Generation failed.";
        return;
    }
    // Build a draft for the preview (probe the local file); nothing is stored yet.
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:result.previewFile options:nil];
    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    CGRect r = CGRectApplyAffineTransform(CGRectMake(0, 0, track.naturalSize.width, track.naturalSize.height),
                                          track.preferredTransform);
    HCGBackgroundPreset *draft = [HCGBackgroundPreset presetWithMediaFile:result.previewFile.lastPathComponent
                                                                mediaSize:CGSizeMake(fabs(r.size.width), fabs(r.size.height))
                                                                 duration:CMTimeGetSeconds(asset.duration)
                                                                   origin:@"ai"];
    draft.name = result.suggestedName.length ? result.suggestedName : @"AI Background";
    draft.generator = result.generatorInfo;
    NSError *invalid = nil;
    if (!track || ![draft sanitizeWithError:&invalid]) {
        [HACAIGeneration discardResult:result];
        _phase.text = invalid.localizedDescription ?: @"The generated preview can't be played.";
        return;
    }
    _phase.text = @"Preview ready.";
    HACEditorViewController *editor = [[HACEditorViewController alloc] initWithAIResult:result draft:draft];
    editor.onChange = self.onChange;
    [self.navigationController pushViewController:editor animated:YES];
}

@end
