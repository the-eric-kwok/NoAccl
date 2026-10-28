// Created by 郭耀铭 on 2026/10/15.
#import "NoAcclPolicy.h"
#import "NoAcclRule.h"
#import <UIKit/UIKit.h>
#import "NoAcclStore.h"
#import <stdatomic.h>

NSString * const NoAcclPolicyChanged = @"NoAcclPolicyChanged";
static NoAcclStore *preferences;
static atomic_int cachedDecision;
static atomic_bool requestMarkQueued;
static BOOL temporaryDenied;
static BOOL promptScheduled;
static BOOL retryScheduled;
static BOOL pendingRequest;
static UIAlertController *permissionAlert;
static id lastRule;

static BOOL PersistObject(id value, NSString *key) {
    return key.length && [preferences setObject:value forKey:key];
}

static void RemovePersistedObject(NSString *key) {
    if (key.length) [preferences removeObjectForKey:key];
}

NSString *NoAcclBundleIdentifier(void) {
    return NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
}

static void Broadcast(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.noaccl.tweak/ReloadPrefs"), NULL, NULL, YES);
}

static void Refresh(BOOL notifyObservers) {
    id rule = [preferences objectForKey:NoAcclRuleKey(NoAcclBundleIdentifier())];
    if (!(rule == lastRule || [rule isEqual:lastRule])) temporaryDenied = NO;
    lastRule = rule;
    NoAcclDecision decision = NoAcclDecisionFromRecord(rule);
    if (decision == NoAcclDecisionAsk && temporaryDenied) decision = NoAcclDecisionTemporaryDeny;
    if (![preferences boolForKey:@"Enabled" default:YES]) decision = NoAcclDecisionAllow;
    atomic_store(&cachedDecision, (int)decision);
    if (decision != NoAcclDecisionAsk && permissionAlert) {
        [permissionAlert dismissViewControllerAnimated:YES completion:nil];
        permissionAlert = nil;
        promptScheduled = NO;
    }
    if (notifyObservers) {
        [NSNotificationCenter.defaultCenter postNotificationName:NoAcclPolicyChanged object:nil];
    }
}

static void RetryPendingRequest(void) {
    if (!pendingRequest || retryScheduled) return;
    retryScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        retryScheduled = NO;
        if (pendingRequest) NoAcclPresentFirstRequestIfNeeded();
    });
}

void NoAcclInitializePolicy(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        preferences = [NoAcclStore new];
        [preferences registerPreferenceChangeBlock:^{
            dispatch_async(dispatch_get_main_queue(), ^{ Refresh(YES); });
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *notification) {
                if (pendingRequest) NoAcclPresentFirstRequestIfNeeded();
            }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIWindowDidBecomeKeyNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *notification) {
                if (pendingRequest) NoAcclPresentFirstRequestIfNeeded();
            }];
        // Observers may read policy again, so initialization must not notify them inside dispatch_once.
        Refresh(NO);
    });
}

NoAcclDecision NoAcclDecisionForCurrentProcess(void) {
    NoAcclInitializePolicy();
    return (NoAcclDecision)atomic_load(&cachedDecision);
}

BOOL NoAcclEnabled(void) {
    NoAcclInitializePolicy();
    return [preferences boolForKey:@"Enabled" default:YES];
}

void NoAcclSetEnabled(BOOL enabled) {
    NoAcclInitializePolicy();
    PersistObject(@(enabled), @"Enabled");
    Refresh(YES);
    Broadcast();
}

void NoAcclSetDecisionForBundle(NSString *bundleID, NoAcclDecision decision) {
    NoAcclInitializePolicy();
    if (!bundleID.length) return;
    if (decision == NoAcclDecisionTemporaryDeny) {
        if ([bundleID isEqual:NoAcclBundleIdentifier()]) {
            temporaryDenied = YES;
            Refresh(YES);
        }
        return;
    }
    // A separate key per app avoids lost updates when two processes grant access concurrently.
    NSDictionary *record = NoAcclRecordForDecision(decision);
    if (!PersistObject(record, NoAcclRuleKey(bundleID))) {
        NSLog(@"[NoAccl] Permission was not saved for %@", bundleID);
        return;
    }
    if ([bundleID isEqual:NoAcclBundleIdentifier()]) temporaryDenied = NO;
    Refresh(YES);
    Broadcast();
}

void NoAcclRemoveDecisionForBundle(NSString *bundleID) {
    NoAcclInitializePolicy();
    if (!bundleID.length) return;
    RemovePersistedObject(NoAcclRuleKey(bundleID));
    RemovePersistedObject([@"Requested." stringByAppendingString:bundleID]);
    if ([bundleID isEqual:NoAcclBundleIdentifier()]) temporaryDenied = NO;
    Refresh(YES);
    Broadcast();
}

NSDictionary *NoAcclAllDecisions(void) {
    NoAcclInitializePolicy();
    NSMutableDictionary *rules = [NSMutableDictionary dictionary];
    [[preferences dictionaryRepresentation] enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        if ([key hasPrefix:@"Rule."]) rules[[key substringFromIndex:5]] = [value isKindOfClass:NSDictionary.class] ? value[@"decision"] ?: @0 : @0;
    }];
    return rules;
}

NSSet<NSString *> *NoAcclRequestedBundleIDs(void) {
    NoAcclInitializePolicy();
    NSMutableSet *bundleIDs = [NSMutableSet set];
    [[preferences dictionaryRepresentation] enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        if ([key hasPrefix:@"Requested."] && [value boolValue]) {
            [bundleIDs addObject:[key substringFromIndex:10]];
        }
    }];
    return bundleIDs;
}

void NoAcclMarkCurrentProcessRequested(void) {
    NoAcclInitializePolicy();
    NSString *bundleID = NoAcclBundleIdentifier();
    if (!bundleID.length) return;
    if (atomic_exchange(&requestMarkQueued, true)) return;
    NSString *key = [@"Requested." stringByAppendingString:bundleID];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!PersistObject(@YES, key)) atomic_store(&requestMarkQueued, false);
    });
}

void NoAcclResetAllDecisions(void) {
    for (NSString *bundleID in NoAcclAllDecisions()) {
        PersistObject(NoAcclRecordForDecision(NoAcclDecisionAsk), NoAcclRuleKey(bundleID));
    }
    temporaryDenied = NO;
    Refresh(YES);
    Broadcast();
}

static UIViewController *VisibleController(void) {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.isKeyWindow || window.hidden) continue;
            UIViewController *controller = window.rootViewController;
            while (controller.presentedViewController) controller = controller.presentedViewController;
            return controller.viewIfLoaded.window ? controller : nil;
        }
    }
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (!window.isKeyWindow || window.hidden) continue;
        UIViewController *controller = window.rootViewController;
        while (controller.presentedViewController) controller = controller.presentedViewController;
        return controller.viewIfLoaded.window ? controller : nil;
    }
    return nil;
}

void NoAcclPresentFirstRequestIfNeeded(void) {
    pendingRequest = YES;
    if (NoAcclDecisionForCurrentProcess() != NoAcclDecisionAsk) {
        pendingRequest = NO;
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (promptScheduled || NoAcclDecisionForCurrentProcess() != NoAcclDecisionAsk) {
            if (NoAcclDecisionForCurrentProcess() != NoAcclDecisionAsk) pendingRequest = NO;
            return;
        }
        UIViewController *controller = VisibleController();
        if (!controller) {
            RetryPendingRequest();
            return;
        }
        if ([controller isKindOfClass:UIAlertController.class]) return;
        promptScheduled = YES;
        NSString *name = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: NoAcclBundleIdentifier();
        permissionAlert = [UIAlertController alertControllerWithTitle:@"NoAccl · 加速度计访问"
            message:[NSString stringWithFormat:@"“%@”请求运动传感器数据。未允许前不会提供加速度或设备运动数据。", name]
            preferredStyle:UIAlertControllerStyleAlert];
        NSArray *titles = @[@"允许", @"拒绝，下次再说", @"永久拒绝"];
        for (NSInteger index = 0; index < titles.count; index++) {
            NoAcclDecision decision = (NoAcclDecision)(index + 1);
            [permissionAlert addAction:[UIAlertAction actionWithTitle:titles[index]
                style:index == 2 ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault
                handler:^(__unused UIAlertAction *action) {
                    permissionAlert = nil;
                    promptScheduled = NO;
                    pendingRequest = NO;
                    NoAcclSetDecisionForBundle(NoAcclBundleIdentifier(), decision);
                }]];
        }
        [controller presentViewController:permissionAlert animated:YES completion:nil];
    });
}
