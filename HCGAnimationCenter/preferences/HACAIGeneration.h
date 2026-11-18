//
//  HACAIGeneration.h
//  HCG Animation Center — Hakmi Capital Group
//
//  Interface for AI-generated backgrounds through HCG AI (a later phase;
//  docs/AI-BACKGROUNDS.md). This beta defines the contract and ships only a
//  provider that reports HCG AI as not connected: there is no network code.
//
//  Rules every provider and the UI follow:
//    1. Access comes from HCG's central access controls (the provider asks
//       them; Animation Center never decides entitlement itself).
//    2. Generation produces a PREVIEW only: a local video file shown in the
//       preview screen. Nothing is added to the library, assigned or applied.
//    3. Only the user's explicit "Apply to Home Screen", "Apply to Lock Screen"
//       or "Save to Library" tap adopts the result (+adoptResult:…). "Discard"
//       deletes the preview.
//

#import <Foundation/Foundation.h>

#import "HCGBackgroundPreset.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HACAIAccessState) {
    HACAIAccessUnavailable = 0, ///< HCG AI is not connected (this beta)
    HACAIAccessSignedOut = 1,   ///< needs an HCG account sign-in
    HACAIAccessNotEntitled = 2, ///< signed in, but HCG's access controls don't allow AI backgrounds
    HACAIAccessAllowed = 3,
};

@interface HACAIAccess : NSObject
@property (nonatomic, readonly) HACAIAccessState state;
@property (nonatomic, readonly, copy) NSString *explanation;
+ (instancetype)accessWithState:(HACAIAccessState)state explanation:(NSString *)explanation;
@end

@interface HACAIRequest : NSObject
@property (nonatomic, copy) NSString *prompt;          ///< 1–500 characters
@property (nonatomic, copy) NSString *style;           ///< e.g. "calm", "vivid", "abstract"
@property (nonatomic) NSTimeInterval durationSeconds;  ///< 2–10
@property (nonatomic) CGSize pixelSize;                ///< the screen, portrait
/// nil if valid, else why not.
- (nullable NSString *)validationProblem;
@end

@interface HACAIResult : NSObject
@property (nonatomic, copy) NSURL *previewFile;  ///< local video, owned by the preview until adopted or discarded
@property (nonatomic, copy) NSString *suggestedName;
/// Recorded in the preset's "generator" (provider, model, request ID, prompt).
@property (nonatomic, copy) NSDictionary<NSString *, id> *generatorInfo;
@end

typedef void (^HACAIProgress)(double fraction, NSString *phase);
typedef void (^HACAICompletion)(HACAIResult *_Nullable result, NSError *_Nullable error);

@protocol HACAIGenerationProvider <NSObject>
@property (nonatomic, readonly, copy) NSString *providerName;
/// Asks HCG's central access controls. Must not block for long.
- (HACAIAccess *)currentAccess;
- (void)generate:(HACAIRequest *)request progress:(HACAIProgress)progress completion:(HACAICompletion)completion;
- (void)cancel;
@end

/// The provider shipped in this beta: HCG AI is not connected.
@interface HACAIUnavailableProvider : NSObject <HACAIGenerationProvider>
@end

@interface HACAIGeneration : NSObject
+ (id<HACAIGenerationProvider>)provider;
/// Development and tests only (e.g. a local test provider in the preview harness).
+ (void)registerProvider:(nullable id<HACAIGenerationProvider>)provider;
/// Removes the preview file. Call on Discard and when the preview closes unadopted.
+ (void)discardResult:(HACAIResult *)result;
@end

NS_ASSUME_NONNULL_END
