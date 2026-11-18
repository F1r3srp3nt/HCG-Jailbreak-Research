//
//  VortexEffectPaneController.m
//  HCG Vortex — Hakmi Capital Group
//

#import "VortexEffectPaneController.h"
#import "VortexPreferences.h"

#import <Preferences/PSSpecifier.h>

@implementation VortexEffectPaneController

- (NSString *)paneName {
    return [self.specifier propertyForKey:@"pane"] ?: @"";
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:[self paneName] target:self];
        self.title = [self.specifier name];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.table.tableHeaderView = nil; // the branded header is for the root pane only
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if ([key isEqualToString:VortexKeyTornadoPreset]) {
        // Choosing a preset writes its values; "custom" keeps the current ones.
        NSDictionary *values = [VortexPreferences valuesForTornadoPreset:value];
        for (NSString *k in values) [VortexPreferences writeValue:values[k] forKey:k];
        [super setPreferenceValue:value specifier:specifier];
        [self reloadSpecifiers];
        return;
    }
    [super setPreferenceValue:value specifier:specifier];
    if ([[VortexPreferences keysForEffectPane:@"Tornado"] containsObject:key]) {
        // A hand-tuned value no longer matches a named preset.
        [VortexPreferences writeValue:@"custom" forKey:VortexKeyTornadoPreset];
        [self reloadSpecifierID:VortexKeyTornadoPreset animated:NO];
    }
}

- (void)resetPane:(PSSpecifier *)specifier {
    NSArray<NSString *> *keys = [VortexPreferences keysForEffectPane:[self paneName]];
    [self confirmWithTitle:@"Reset to Defaults"
                   message:[NSString stringWithFormat:@"Return the %@ settings to their defaults? Other settings are kept.",
                                                      [self.specifier name] ?: @"effect"]
               actionTitle:@"Reset"
               destructive:NO
                   handler:^{
                       for (NSString *key in keys) [VortexPreferences writeValue:nil forKey:key];
                       [VortexPreferences postChangeNotification];
                       [self reloadSpecifiers];
                   }];
}

- (NSString *)reduceMotionStatus:(PSSpecifier *)specifier {
    return UIAccessibilityIsReduceMotionEnabled() ? @"On: icon effects use the stock animation" : @"Off";
}

@end
