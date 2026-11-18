//
//  HACAIGeneration.m
//  HCG Animation Center — Hakmi Capital Group
//

#import "HACAIGeneration.h"

@implementation HACAIAccess

+ (instancetype)accessWithState:(HACAIAccessState)state explanation:(NSString *)explanation {
    HACAIAccess *access = [[self alloc] init];
    access->_state = state;
    access->_explanation = [explanation copy];
    return access;
}

@end

@implementation HACAIRequest

- (instancetype)init {
    if ((self = [super init])) {
        _prompt = @"";
        _style = @"calm";
        _durationSeconds = 6;
    }
    return self;
}

- (NSString *)validationProblem {
    NSString *prompt = [_prompt stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (prompt.length == 0) return @"Describe the background you want.";
    if (prompt.length > 500) return @"Keep the description under 500 characters.";
    if (!(_durationSeconds >= 2 && _durationSeconds <= 10)) return @"Choose a length between 2 and 10 seconds.";
    if (_pixelSize.width < 16 || _pixelSize.height < 16) return @"Unknown screen size.";
    return nil;
}

@end

@implementation HACAIResult
@end

@implementation HACAIUnavailableProvider

- (NSString *)providerName {
    return @"HCG AI";
}

- (HACAIAccess *)currentAccess {
    return [HACAIAccess accessWithState:HACAIAccessUnavailable
                            explanation:@"HCG AI isn't connected in this beta. When it is, generating a background will "
                                        @"use your HCG account, and HCG's central access controls will decide who can "
                                        @"use it. This version sends nothing anywhere."];
}

- (void)generate:(HACAIRequest *)request progress:(HACAIProgress)progress completion:(HACAICompletion)completion {
    completion(nil, [NSError errorWithDomain:@"com.hakmicapitalgroup.animationcenter.ai"
                                        code:1
                                    userInfo:@{NSLocalizedDescriptionKey : [self currentAccess].explanation}]);
}

- (void)cancel {
}

@end

static id<HACAIGenerationProvider> gProvider;

@implementation HACAIGeneration

+ (id<HACAIGenerationProvider>)provider {
    if (!gProvider) gProvider = [[HACAIUnavailableProvider alloc] init];
    return gProvider;
}

+ (void)registerProvider:(id<HACAIGenerationProvider>)provider {
    gProvider = provider;
}

+ (void)discardResult:(HACAIResult *)result {
    if (result.previewFile.isFileURL) [[NSFileManager defaultManager] removeItemAtURL:result.previewFile error:NULL];
}

@end
