//
//  HaloNexusDefinition.m
//  HCG Halo — Hakmi Capital Group
//

#import "HaloNexusDefinition.h"

#include <ctype.h>
#include <math.h>

NSString *const HaloNexusSchemaIdentifier = @"com.hakmicapitalgroup.hcgnexus.halo-border";
NSString *const HaloNexusInterfaceClassName = @"HCGNexusBorderInterface";
NSString *const HaloNexusPrefsBundleName = @"HCGNexusPrefs.bundle";
NSString *const HaloNexusDefinitionFileName = @"HaloBorder.plist";

static const NSUInteger kMaxBytes = 16 * 1024;

static BOOL HaloIsBool(id v) {
    return [v isKindOfClass:[NSNumber class]] && CFGetTypeID((__bridge CFTypeRef)v) == CFBooleanGetTypeID();
}

static BOOL HaloIsInteger(id v) {
    return [v isKindOfClass:[NSNumber class]] && !HaloIsBool(v) && !CFNumberIsFloatType((__bridge CFNumberRef)v);
}

static BOOL HaloIsNumberInRange(id v, double lo, double hi) {
    if (![v isKindOfClass:[NSNumber class]] || HaloIsBool(v)) return NO;
    double d = [v doubleValue];
    return isfinite(d) && d >= lo && d <= hi;
}

static BOOL HaloMatches(NSString *value, NSString *pattern) {
    if (![value isKindOfClass:[NSString class]]) return NO;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    return [re firstMatchInString:value options:NSMatchingAnchored range:NSMakeRange(0, value.length)].range.length == value.length;
}

@interface HaloNexusDefinition ()
@property (nonatomic, readwrite, copy) NSString *path;
@property (nonatomic, readwrite, copy) NSString *nexusVersion;
@property (nonatomic, readwrite) double cornerRadius;
@property (nonatomic, readwrite) BOOL continuousCorners;
@property (nonatomic, readwrite) double outset;
@property (nonatomic, readwrite) double glowMargin;
@property (nonatomic, readwrite) BOOL clipInterior;
@property (nonatomic, readwrite, copy) NSSet<NSString *> *capabilities;
@property (nonatomic, readwrite, copy, nullable) NSString *defaultPreset;
@end

@implementation HaloNexusDefinition

- (BOOL)hasCapability:(NSString *)capability {
    return [self.capabilities containsObject:capability];
}

+ (instancetype)definitionAtPath:(NSString *)path error:(NSString **)error {
    if (!path.length) {
        if (error) *error = @"HCG Nexus with the HCG Halo border interface (" HALO_NEXUS_MIN_VERSION " or a later build that includes it) is not installed: no border definition";
        return nil;
    }
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if (!attributes) {
        if (error) *error = @"HCG Nexus with the HCG Halo border interface (" HALO_NEXUS_MIN_VERSION " or a later build that includes it) is not installed: no border definition";
        return nil;
    }
    if (![attributes.fileType isEqualToString:NSFileTypeRegular] || attributes.fileSize > kMaxBytes) {
        if (error) *error = @"HCG Nexus's border definition is not a small regular file";
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];
    if (!data) {
        if (error) *error = @"HCG Nexus's border definition cannot be read";
        return nil;
    }
    return [self definitionWithData:data path:path error:error];
}

+ (instancetype)definitionWithData:(NSData *)data path:(NSString *)path error:(NSString **)error {
    NSString *problem = nil;
    NSDictionary *d = nil;
    if (data.length > kMaxBytes) {
        problem = @"the border definition is too large";
    } else {
        id parsed = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil];
        if (![parsed isKindOfClass:[NSDictionary class]]) problem = @"the border definition is not a property list dictionary";
        else d = parsed;
    }
    HaloNexusDefinition *def = [[HaloNexusDefinition alloc] init];
    def.path = path ?: @"";
    if (!problem) problem = [self validate:d into:def];
    if (problem) {
        if (error) *error = [NSString stringWithFormat:@"Incompatible HCG Nexus border definition: %@", problem];
        return nil;
    }
    return def;
}

+ (NSString *)validate:(NSDictionary *)d into:(HaloNexusDefinition *)def {
    NSSet *required = [NSSet setWithArray:@[ @"schema", @"schemaVersion", @"interfaceVersion", @"interfaceClass", @"nexusVersion",
                                             @"shape", @"anchors", @"capabilities" ]];
    NSSet *keys = [NSSet setWithArray:d.allKeys];
    if (![required isSubsetOfSet:keys]) return @"required keys are missing";
    NSMutableSet *extra = [keys mutableCopy];
    [extra minusSet:required];
    [extra removeObject:@"style"];
    if (extra.count) return [NSString stringWithFormat:@"unknown keys %@", [extra.allObjects componentsJoinedByString:@", "]];

    if (![d[@"schema"] isEqual:HaloNexusSchemaIdentifier]) return @"wrong schema identifier";
    if (!HaloIsInteger(d[@"schemaVersion"])) return @"schemaVersion is not an integer";
    if ([d[@"schemaVersion"] integerValue] != HALO_NEXUS_SCHEMA_VERSION)
        return [NSString stringWithFormat:@"schema version %@ (this HCG Halo reads version %d)", d[@"schemaVersion"], HALO_NEXUS_SCHEMA_VERSION];
    if (!HaloIsInteger(d[@"interfaceVersion"]) || [d[@"interfaceVersion"] integerValue] != HALO_NEXUS_INTERFACE_VERSION)
        return [NSString stringWithFormat:@"interface version %@ (this HCG Halo supports version %d)", d[@"interfaceVersion"], HALO_NEXUS_INTERFACE_VERSION];
    if (![d[@"interfaceClass"] isEqual:HaloNexusInterfaceClassName]) return @"unexpected interface class name";
    if (!HaloMatches(d[@"nexusVersion"], @"[0-9][0-9A-Za-z.~+-]{0,31}")) return @"invalid nexusVersion";
    if ([self compareVersion:d[@"nexusVersion"] to:@HALO_NEXUS_MIN_VERSION] < 0)
        return [NSString stringWithFormat:@"HCG Nexus %@ is older than " HALO_NEXUS_MIN_VERSION, d[@"nexusVersion"]];

    NSDictionary *shape = d[@"shape"];
    if (![shape isKindOfClass:[NSDictionary class]] ||
        ![[NSSet setWithArray:shape.allKeys] isEqualToSet:[NSSet setWithArray:@[ @"kind", @"cornerRadius", @"cornerCurve" ]]])
        return @"shape must have exactly kind, cornerRadius and cornerCurve";
    if (![shape[@"kind"] isEqual:@"rounded-rect"]) return @"unsupported shape kind";
    if (!HaloIsNumberInRange(shape[@"cornerRadius"], 0, 64)) return @"shape.cornerRadius out of range";
    if (![@[ @"continuous", @"circular" ] containsObject:shape[@"cornerCurve"] ?: @""]) return @"unsupported cornerCurve";

    NSDictionary *anchors = d[@"anchors"];
    if (![anchors isKindOfClass:[NSDictionary class]] ||
        ![[NSSet setWithArray:anchors.allKeys] isEqualToSet:[NSSet setWithArray:@[ @"host", @"outset", @"glowMargin", @"clipInterior" ]]])
        return @"anchors must have exactly host, outset, glowMargin and clipInterior";
    if (![anchors[@"host"] isEqual:@"panel"]) return @"unsupported anchor host";
    if (!HaloIsNumberInRange(anchors[@"outset"], 0, 12)) return @"anchors.outset out of range";
    if (!HaloIsNumberInRange(anchors[@"glowMargin"], 8, 64)) return @"anchors.glowMargin out of range";
    if (!HaloIsBool(anchors[@"clipInterior"])) return @"anchors.clipInterior is not a boolean";

    NSArray *caps = d[@"capabilities"];
    NSSet *known = [NSSet setWithArray:@[ @"live-geometry", @"open-close-events", @"presentation-progress", @"workspace-events",
                                          @"orientation", @"keyboard-resize" ]];
    if (![caps isKindOfClass:[NSArray class]]) return @"capabilities is not a list";
    NSMutableSet *capSet = [NSMutableSet set];
    for (id c in caps) {
        if (![c isKindOfClass:[NSString class]] || ![known containsObject:c] || [capSet containsObject:c]) return @"unknown or repeated capability";
        [capSet addObject:c];
    }
    if (![capSet containsObject:@"live-geometry"] || ![capSet containsObject:@"open-close-events"])
        return @"live-geometry and open-close-events are required";

    NSString *defaultPreset = nil;
    if (d[@"style"]) {
        NSDictionary *style = d[@"style"];
        if (![style isKindOfClass:[NSDictionary class]]) return @"style is not a dictionary";
        NSMutableSet *styleKeys = [NSMutableSet setWithArray:style.allKeys];
        [styleKeys removeObject:@"defaultPreset"];
        if (styleKeys.count) return @"style may only contain defaultPreset";
        if (style[@"defaultPreset"]) {
            if (!HaloMatches(style[@"defaultPreset"], @"builtin\\.[a-z0-9-]{1,32}")) return @"invalid style.defaultPreset";
            defaultPreset = style[@"defaultPreset"];
        }
    }

    def.nexusVersion = d[@"nexusVersion"];
    def.cornerRadius = [shape[@"cornerRadius"] doubleValue];
    def.continuousCorners = [shape[@"cornerCurve"] isEqual:@"continuous"];
    def.outset = [anchors[@"outset"] doubleValue];
    def.glowMargin = [anchors[@"glowMargin"] doubleValue];
    def.clipInterior = [anchors[@"clipInterior"] boolValue];
    def.capabilities = capSet;
    def.defaultPreset = defaultPreset;
    return nil;
}

+ (NSString *)installedPathNextToBundle:(NSBundle *)bundle {
    NSString *preferenceBundles = [bundle.bundlePath stringByDeletingLastPathComponent];
    if (!preferenceBundles.length) return nil;
    NSString *path = [[preferenceBundles stringByAppendingPathComponent:HaloNexusPrefsBundleName]
        stringByAppendingPathComponent:HaloNexusDefinitionFileName];
    return [[NSFileManager defaultManager] fileExistsAtPath:path] ? path : nil;
}

#pragma mark Debian version order

static int HaloVersionOrder(unichar c) {
    if (c >= '0' && c <= '9') return 0;
    if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) return c;
    if (c == '~') return -1;
    return c ? c + 256 : 0;
}

static NSInteger HaloVerRevCmp(NSString *a, NSString *b) {
    NSUInteger i = 0, j = 0, la = a.length, lb = b.length;
    while (i < la || j < lb) {
        int firstDiff = 0;
        while ((i < la && !isdigit([a characterAtIndex:i])) || (j < lb && !isdigit([b characterAtIndex:j]))) {
            int ac = HaloVersionOrder(i < la ? [a characterAtIndex:i] : 0);
            int bc = HaloVersionOrder(j < lb ? [b characterAtIndex:j] : 0);
            if (ac != bc) return ac < bc ? -1 : 1;
            i++;
            j++;
        }
        while (i < la && [a characterAtIndex:i] == '0') i++;
        while (j < lb && [b characterAtIndex:j] == '0') j++;
        while (i < la && j < lb && isdigit([a characterAtIndex:i]) && isdigit([b characterAtIndex:j])) {
            if (!firstDiff) firstDiff = [a characterAtIndex:i] - [b characterAtIndex:j];
            i++;
            j++;
        }
        if (i < la && isdigit([a characterAtIndex:i])) return 1;
        if (j < lb && isdigit([b characterAtIndex:j])) return -1;
        if (firstDiff) return firstDiff < 0 ? -1 : 1;
    }
    return 0;
}

+ (NSInteger)compareVersion:(NSString *)a to:(NSString *)b {
    NSRange ra = [a rangeOfString:@"-" options:NSBackwardsSearch];
    NSRange rb = [b rangeOfString:@"-" options:NSBackwardsSearch];
    NSString *ua = ra.location == NSNotFound ? a : [a substringToIndex:ra.location];
    NSString *ub = rb.location == NSNotFound ? b : [b substringToIndex:rb.location];
    NSInteger c = HaloVerRevCmp(ua, ub);
    if (c) return c;
    NSString *va = ra.location == NSNotFound ? @"" : [a substringFromIndex:ra.location + 1];
    NSString *vb = rb.location == NSNotFound ? @"" : [b substringFromIndex:rb.location + 1];
    return HaloVerRevCmp(va, vb);
}

@end
