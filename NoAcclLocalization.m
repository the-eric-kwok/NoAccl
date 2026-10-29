// Created by 郭耀铭 on 2026/10/28.
#import "NoAcclLocalization.h"
#import <rootless.h>

NSString *NoAcclLocalizedString(NSString *key) {
    static NSBundle *bundle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Injected apps must use NoAccl's resources instead of the host app's localizations.
        NSBundle *resources = [NSBundle bundleWithPath:ROOT_PATH_NS(@"/Library/PreferenceBundles/NoAcclPrefs.bundle")];
        NSString *language = [NSBundle preferredLocalizationsFromArray:resources.localizations ?: @[@"en"]
            forPreferences:NSLocale.preferredLanguages].firstObject;
        NSString *path = [resources pathForResource:language ofType:@"lproj"];
        bundle = path ? [NSBundle bundleWithPath:path] : resources;
    });
    return [bundle localizedStringForKey:key value:key table:nil] ?: key;
}
