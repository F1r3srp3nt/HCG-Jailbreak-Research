//
//  HACLibraryViewController.m
//  HCG Animation Center — Hakmi Capital Group
//

#import "HACLibraryViewController.h"
#import "HACEditorViewController.h"
#import "HACLibrary.h"
#import "HACMediaImporter.h"
#import "HACPreferences.h"
#import "HACTheme.h"

#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *const kCell = @"item";
static NSString *const kHeader = @"header";
static NSString *const kLivePhotoType = @"com.apple.live-photo";

#pragma mark - Cell

@interface HACLibraryCell : UICollectionViewCell
@property (nonatomic, readonly) UIImageView *imageView;
@property (nonatomic, readonly) UILabel *nameLabel;
@property (nonatomic, readonly) UILabel *badgeLabel;
@property (nonatomic, readonly) UILabel *durationLabel;
@end

@implementation HACLibraryCell

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _imageView = [[UIImageView alloc] init];
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        _imageView.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
        _imageView.layer.cornerRadius = 12;
        _imageView.layer.cornerCurve = kCACornerCurveContinuous;
        _imageView.tintColor = UIColor.secondaryLabelColor;
        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        _nameLabel.textAlignment = NSTextAlignmentCenter;
        _badgeLabel = [[UILabel alloc] init];
        _badgeLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
        _badgeLabel.textColor = UIColor.whiteColor;
        _badgeLabel.backgroundColor = HACAccentColor();
        _badgeLabel.textAlignment = NSTextAlignmentCenter;
        _badgeLabel.layer.cornerRadius = 8;
        _badgeLabel.clipsToBounds = YES;
        _durationLabel = [[UILabel alloc] init];
        _durationLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightSemibold];
        _durationLabel.textColor = UIColor.whiteColor;
        _durationLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
        _durationLabel.textAlignment = NSTextAlignmentCenter;
        _durationLabel.layer.cornerRadius = 6;
        _durationLabel.clipsToBounds = YES;
        for (UIView *v in @[ _imageView, _nameLabel, _badgeLabel, _durationLabel ]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:v];
        }
        [NSLayoutConstraint activateConstraints:@[
            [_imageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_imageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_imageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_imageView.bottomAnchor constraintEqualToAnchor:_nameLabel.topAnchor constant:-4],
            [_nameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_nameLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_nameLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
            [_nameLabel.heightAnchor constraintEqualToConstant:18],
            [_badgeLabel.topAnchor constraintEqualToAnchor:_imageView.topAnchor constant:6],
            [_badgeLabel.leadingAnchor constraintEqualToAnchor:_imageView.leadingAnchor constant:6],
            [_badgeLabel.heightAnchor constraintEqualToConstant:16],
            [_durationLabel.bottomAnchor constraintEqualToAnchor:_imageView.bottomAnchor constant:-6],
            [_durationLabel.trailingAnchor constraintEqualToAnchor:_imageView.trailingAnchor constant:-6],
            [_durationLabel.heightAnchor constraintEqualToConstant:16],
        ]];
    }
    return self;
}

@end

#pragma mark - Progress overlay

@interface HACProgressOverlay : UIView
@property (nonatomic, readonly) UILabel *label;
@property (nonatomic, readonly) UIProgressView *bar;
@property (nonatomic, readonly) UIButton *cancelButton;
@end

@implementation HACProgressOverlay

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        UIView *card = [[UIView alloc] init];
        card.backgroundColor = UIColor.secondarySystemBackgroundColor;
        card.layer.cornerRadius = 16;
        card.translatesAutoresizingMaskIntoConstraints = NO;
        _label = [[UILabel alloc] init];
        _label.numberOfLines = 0;
        _label.textAlignment = NSTextAlignmentCenter;
        _bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        _bar.progressTintColor = HACAccentColor();
        _cancelButton = HACMakeButton(@"Cancel", nil, NO);
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ _label, _bar, _cancelButton ]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 14;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:stack];
        [self addSubview:card];
        [NSLayoutConstraint activateConstraints:@[
            [card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [card.widthAnchor constraintEqualToConstant:280],
            [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],
            [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
            [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
            [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        ]];
    }
    return self;
}

@end

#pragma mark - Controller

@interface HACLibraryViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout,
                                        PHPickerViewControllerDelegate, UIDocumentPickerDelegate>
@end

@implementation HACLibraryViewController {
    BOOL _choosing;
    HACSurface _surface;
    NSArray<HCGBackgroundPreset *> *_items;
    UICollectionView *_collection;
    UILabel *_summary;
    HACMediaImporter *_importer;
    HACProgressOverlay *_overlay;
    NSMutableArray<NSDictionary *> *_queue; // @{url, name}
    NSMutableArray<NSString *> *_problems;
    NSUInteger _imported;
    void (^_queueCompletion)(NSUInteger, NSArray<NSString *> *);
    NSCache<NSString *, UIImage *> *_thumbnails;
    BOOL _pickingPresetFolder;
}

- (instancetype)initBrowsing {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        self.title = @"Media Library";
        [self commonInit];
    }
    return self;
}

- (instancetype)initChoosingForSurface:(HACSurface)surface {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _choosing = YES;
        _surface = surface;
        self.title = surface == HACSurfaceLock ? @"Lock Screen" : @"Home Screen";
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    _importer = [[HACMediaImporter alloc] init];
    _queue = [NSMutableArray array];
    _problems = [NSMutableArray array];
    _thumbnails = [[NSCache alloc] init];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    HACApplyTheme(self);
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 12;
    layout.minimumLineSpacing = 16;
    layout.sectionInset = UIEdgeInsetsMake(8, 16, 24, 16);
    layout.headerReferenceSize = CGSizeMake(0, 64);
    _collection = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    _collection.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _collection.backgroundColor = UIColor.clearColor;
    _collection.dataSource = self;
    _collection.delegate = self;
    _collection.alwaysBounceVertical = YES;
    [_collection registerClass:[HACLibraryCell class] forCellWithReuseIdentifier:kCell];
    [_collection registerClass:[UICollectionReusableView class]
        forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
               withReuseIdentifier:kHeader];
    [self.view addSubview:_collection];

    __weak HACLibraryViewController *weakSelf = self;
    UIMenu *menu = [UIMenu menuWithTitle:@"Import"
                                children:@[
                                    [UIAction actionWithTitle:@"From Photos"
                                                        image:[UIImage systemImageNamed:@"photo.on.rectangle"]
                                                   identifier:nil
                                                      handler:^(UIAction *a) {
                                                          [weakSelf pickFromPhotos];
                                                      }],
                                    [UIAction actionWithTitle:@"From Files"
                                                        image:[UIImage systemImageNamed:@"folder"]
                                                   identifier:nil
                                                      handler:^(UIAction *a) {
                                                          [weakSelf pickFromFiles:NO];
                                                      }],
                                    [UIAction actionWithTitle:@"HCG Preset or Pack (.hcgbackground, .hcgpack)"
                                                        image:[UIImage systemImageNamed:@"shippingbox"]
                                                   identifier:nil
                                                      handler:^(UIAction *a) {
                                                          [weakSelf pickFromFiles:YES];
                                                      }],
                                ]];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"plus"] menu:menu];
    self.navigationItem.rightBarButtonItem.accessibilityLabel = @"Import";
    [self reloadLibrary];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadLibrary];
}

- (void)reloadLibrary {
    [[HACLibrary shared] reload];
    _items = [HACLibrary shared].items;
    [_thumbnails removeAllObjects];
    [_collection reloadData];
}

#pragma mark Data

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)_items.count + (_choosing ? 1 : 0);
}

- (HCGBackgroundPreset *)itemAt:(NSIndexPath *)indexPath {
    NSInteger i = indexPath.item - (_choosing ? 1 : 0);
    return i >= 0 && i < (NSInteger)_items.count ? _items[(NSUInteger)i] : nil;
}

- (UIImage *)thumbnailFor:(HCGBackgroundPreset *)item {
    // The thumbnail is the source frame; show it the way the Home Screen
    // placement turns and flips it.
    NSString *key = [NSString stringWithFormat:@"%@/%ld%d%d", item.identifier, (long)item.rotation, item.flipHorizontal,
                                               item.flipVertical];
    UIImage *image = [_thumbnails objectForKey:key];
    if (image) return image;
    image = HACOrientedImage([UIImage imageWithContentsOfFile:[[HACLibrary shared] thumbnailURLForItem:item].path], item);
    if (image) [_thumbnails setObject:image forKey:key];
    return image;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    HACLibraryCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kCell forIndexPath:indexPath];
    HCGBackgroundPreset *item = [self itemAt:indexPath];
    HACSettings *settings = [HACPreferences loadSettings];
    if (!item) {
        cell.imageView.image = [UIImage systemImageNamed:@"iphone"];
        cell.imageView.contentMode = UIViewContentModeCenter;
        cell.nameLabel.text = @"None (system)";
        BOOL current = ![settings presetForSurface:_surface] || ![settings surfaceEnabled:_surface];
        cell.badgeLabel.text = current ? @"  In use  " : nil;
        cell.badgeLabel.hidden = !current;
        cell.durationLabel.hidden = YES;
        cell.accessibilityLabel = @"None: use the system wallpaper";
        return cell;
    }
    cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
    cell.imageView.image = [self thumbnailFor:item] ?: [UIImage systemImageNamed:@"film"];
    cell.nameLabel.text = item.name;
    NSMutableArray *badges = [NSMutableArray array];
    BOOL home = [[settings presetForSurface:HACSurfaceHome].identifier isEqualToString:item.identifier] && settings.homeEnabled;
    BOOL lock = [[settings presetForSurface:HACSurfaceLock].identifier isEqualToString:item.identifier] && settings.lockEnabled;
    if (home) [badges addObject:@"Home"];
    if (lock) [badges addObject:@"Lock"];
    cell.badgeLabel.text = badges.count ? [NSString stringWithFormat:@"  %@  ", [badges componentsJoinedByString:@" · "]] : nil;
    cell.badgeLabel.hidden = badges.count == 0;
    cell.durationLabel.hidden = NO;
    cell.durationLabel.text = [NSString stringWithFormat:@" %@%@ ", HACFormatSeconds(item.clipDuration),
                                                         [item.origin isEqualToString:@"gif"] ? @" GIF" : @""];
    cell.accessibilityLabel = [NSString stringWithFormat:@"%@, %@%@", item.name, HACDescribePreset(item),
                                                         badges.count ? [@", in use on " stringByAppendingString:[badges componentsJoinedByString:@" and "]] : @""];
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {
    UICollectionReusableView *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                                          withReuseIdentifier:kHeader
                                                                                 forIndexPath:indexPath];
    if (!_summary) {
        _summary = [[UILabel alloc] init];
        _summary.numberOfLines = 0;
        _summary.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        _summary.textColor = UIColor.secondaryLabelColor;
        _summary.translatesAutoresizingMaskIntoConstraints = NO;
    }
    if (_summary.superview != header) {
        [_summary removeFromSuperview];
        [header addSubview:_summary];
        [NSLayoutConstraint activateConstraints:@[
            [_summary.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
            [_summary.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
            [_summary.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        ]];
    }
    NSString *problem = [HACLibrary shared].loadProblem;
    NSString *usage = [NSByteCountFormatter stringFromByteCount:(long long)[[HACLibrary shared] mediaBytes]
                                                     countStyle:NSByteCountFormatterCountStyleFile];
    NSString *lead = _choosing ? @"Choose a background to preview, then tap Apply."
                               : (_items.count ? @"Tap a background to edit and preview it." : @"Tap + to import a video or GIF.");
    _summary.text = [NSString stringWithFormat:@"%@ %lu item%@, %@.%@%@", lead, (unsigned long)_items.count,
                                               _items.count == 1 ? @"" : @"s", usage, problem.length ? @"\n" : @"", problem];
    return header;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                    layout:(UICollectionViewLayout *)layout
    sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat width = (collectionView.bounds.size.width - 32 - 24) / 3;
    CGSize screen = UIScreen.mainScreen.bounds.size;
    return CGSizeMake(floor(width), floor(width * MAX(screen.width, screen.height) / MIN(screen.width, screen.height)) + 22);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    HCGBackgroundPreset *item = [self itemAt:indexPath];
    if (!item) {
        [HACLibrary assignPreset:nil toSurface:_surface];
        if (_onChange) _onChange();
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    HACEditorViewController *editor = [[HACEditorViewController alloc] initWithItem:item
                                                                   preferredSurface:_choosing ? _surface : HACSurfaceHome];
    __weak HACLibraryViewController *weakSelf = self;
    editor.onChange = ^{
        HACLibraryViewController *strong = weakSelf;
        [strong reloadLibrary];
        if (strong.onChange) strong.onChange();
    };
    [self.navigationController pushViewController:editor animated:YES];
}

#pragma mark Pickers

- (void)pickFromPhotos {
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
    config.selectionLimit = 10;
    // Videos, and images so GIFs can be chosen; still images and Live Photos are refused with a reason.
    config.filter = [PHPickerFilter anyFilterMatchingSubfilters:@[ PHPickerFilter.videosFilter, PHPickerFilter.imagesFilter ]];
    config.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (!results.count) return;
    dispatch_group_t group = dispatch_group_create();
    NSMutableArray<NSDictionary *> *staged = [NSMutableArray array];
    NSMutableArray<NSString *> *problems = [NSMutableArray array];
    NSObject *lock = [[NSObject alloc] init];
    for (PHPickerResult *result in results) {
        NSItemProvider *provider = result.itemProvider;
        NSString *name = provider.suggestedName ?: @"Imported";
        NSString *type = nil;
        if ([provider hasItemConformingToTypeIdentifier:UTTypeGIF.identifier]) {
            type = UTTypeGIF.identifier;
        } else if ([provider hasItemConformingToTypeIdentifier:kLivePhotoType]) {
            @synchronized(lock) {
                [problems addObject:[NSString stringWithFormat:@"%@: Live Photos aren't supported as live backgrounds "
                                                               @"yet. To use one, save it as a video in Photos first "
                                                               @"(Share › Save as Video) and import that.",
                                                               name]];
            }
            continue;
        } else if ([provider hasItemConformingToTypeIdentifier:UTTypeMovie.identifier]) {
            type = UTTypeMovie.identifier;
        } else {
            @synchronized(lock) {
                [problems addObject:[NSString stringWithFormat:@"%@: still images can't be live backgrounds. Choose a "
                                                               @"video or an animated GIF.",
                                                               name]];
            }
            continue;
        }
        dispatch_group_enter(group);
        [provider loadFileRepresentationForTypeIdentifier:type
                                        completionHandler:^(NSURL *url, NSError *error) {
                                            // The file only exists during this call: stage a copy now.
                                            NSError *stageError = nil;
                                            NSURL *copy = url ? [HACMediaImporter stageFileAtURL:url error:&stageError] : nil;
                                            @synchronized(lock) {
                                                if (copy) {
                                                    [staged addObject:@{@"url" : copy, @"name" : name}];
                                                } else {
                                                    [problems addObject:[NSString stringWithFormat:@"%@: %@", name,
                                                                                                   (stageError ?: error).localizedDescription
                                                                                                       ?: @"could not be read"]];
                                                }
                                            }
                                            dispatch_group_leave(group);
                                        }];
    }
    [self showProgress:@"Preparing…" fraction:0];
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [self enqueueStaged:staged problems:problems completion:nil];
    });
}

- (void)pickFromFiles:(BOOL)presetFolder {
    _pickingPresetFolder = presetFolder;
    NSArray<UTType *> *types = presetFolder ? @[ UTTypeFolder ] : @[ UTTypeMovie, UTTypeGIF ];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types
                                                                                                         asCopy:!presetFolder];
    picker.allowsMultipleSelection = !presetFolder;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (_pickingPresetFolder) {
        NSURL *folder = urls.firstObject;
        BOOL scoped = [folder startAccessingSecurityScopedResource];
        NSError *error = nil;
        HCGBackgroundPreset *item = [[HACLibrary shared] importPresetFolder:folder error:&error];
        if (item) [HACMediaImporter writeStillAndThumbnailForItem:item error:NULL];
        if (scoped) [folder stopAccessingSecurityScopedResource];
        [self reloadLibrary];
        if (!item) [self showProblems:@[ error.localizedDescription ?: @"The preset could not be imported." ] imported:0];
        return;
    }
    [self importFileURLs:urls completion:nil];
}

- (void)importFileURLs:(NSArray<NSURL *> *)urls completion:(void (^)(NSUInteger, NSArray<NSString *> *))completion {
    NSMutableArray *staged = [NSMutableArray array];
    NSMutableArray *problems = [NSMutableArray array];
    for (NSURL *url in urls) {
        BOOL scoped = [url startAccessingSecurityScopedResource];
        NSError *error = nil;
        NSURL *copy = [HACMediaImporter stageFileAtURL:url error:&error];
        if (scoped) [url stopAccessingSecurityScopedResource];
        if (copy) {
            [staged addObject:@{@"url" : copy, @"name" : url.lastPathComponent ?: @"Imported"}];
        } else {
            [problems addObject:[NSString stringWithFormat:@"%@: %@", url.lastPathComponent,
                                                           error.localizedDescription ?: @"could not be read"]];
        }
    }
    [self enqueueStaged:staged problems:problems completion:completion];
}

#pragma mark Import queue

- (void)enqueueStaged:(NSArray<NSDictionary *> *)staged
             problems:(NSArray<NSString *> *)problems
           completion:(void (^)(NSUInteger, NSArray<NSString *> *))completion {
    [_queue addObjectsFromArray:staged];
    [_problems addObjectsFromArray:problems];
    if (completion) _queueCompletion = [completion copy];
    if (!_importer.busy) [self importNext];
}

- (void)importNext {
    NSDictionary *next = _queue.firstObject;
    if (!next) {
        [self hideProgress];
        [self reloadLibrary];
        if (_onChange) _onChange();
        NSArray *problems = [_problems copy];
        NSUInteger imported = _imported;
        [_problems removeAllObjects];
        _imported = 0;
        void (^completion)(NSUInteger, NSArray<NSString *> *) = _queueCompletion;
        _queueCompletion = nil;
        if (completion) {
            completion(imported, problems);
        } else if (problems.count) {
            [self showProblems:problems imported:imported];
        }
        return;
    }
    [_queue removeObjectAtIndex:0];
    NSString *name = next[@"name"];
    __weak HACLibraryViewController *weakSelf = self;
    [self showProgress:[NSString stringWithFormat:@"Importing “%@”", name] fraction:0];
    [_importer importStagedFile:next[@"url"]
                  suggestedName:name
                       progress:^(double fraction, NSString *phase) {
                           [weakSelf showProgress:[NSString stringWithFormat:@"%@\n%@", name, phase] fraction:fraction];
                       }
                     completion:^(HCGBackgroundPreset *item, NSError *error) {
                         HACLibraryViewController *strong = weakSelf;
                         if (!strong) return;
                         if (item) {
                             strong->_imported++;
                         } else {
                             [strong->_problems addObject:[NSString stringWithFormat:@"%@: %@", name,
                                                                                     error.localizedDescription ?: @"failed"]];
                         }
                         [strong reloadLibrary];
                         [strong importNext];
                     }];
}

- (void)cancelImports {
    for (NSDictionary *pending in _queue) [[NSFileManager defaultManager] removeItemAtURL:pending[@"url"] error:NULL];
    [_queue removeAllObjects];
    [_importer cancel];
}

- (void)showProgress:(NSString *)text fraction:(double)fraction {
    if (!_overlay) {
        _overlay = [[HACProgressOverlay alloc] initWithFrame:self.view.bounds];
        _overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_overlay.cancelButton addTarget:self action:@selector(cancelImports) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:_overlay];
    }
    _overlay.label.text = text;
    [_overlay.bar setProgress:(float)fraction animated:YES];
}

- (void)hideProgress {
    [_overlay removeFromSuperview];
    _overlay = nil;
}

- (void)showProblems:(NSArray<NSString *> *)problems imported:(NSUInteger)imported {
    NSString *title = imported ? [NSString stringWithFormat:@"Imported %lu, %lu not imported", (unsigned long)imported,
                                                            (unsigned long)problems.count]
                               : @"Not Imported";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:[problems componentsJoinedByString:@"\n\n"]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
