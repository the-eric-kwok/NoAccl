// Created by 郭耀铭 on 2026/10/15.
#import "NoAcclPolicy.h"
#import "NoAcclRule.h"
#import <UIKit/UIKit.h>
#import <Cephei/HBPreferences.h>
#import <stdatomic.h>

NSString * const NoAcclPolicyChanged = @"NoAcclPolicyChanged";
static HBPreferences *preferences;
static atomic_int cachedDecision;
static BOOL temporaryDenied;
static BOOL promptScheduled;
static BOOL pendingRequest;
static UIAlertController *permissionAlert;
static id lastRule;

NSString *NoAcclBundleIdentifier(void) {
    return NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
}

static void Broadcast(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.noaccl.tweak/ReloadPrefs"), NULL, NULL, YES);
}

static void Refresh(void) {
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
    [NSNotificationCenter.defaultCenter postNotificationName:NoAcclPolicyChanged object:nil];
}

void NoAcclInitializePolicy(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        preferences = [[HBPreferences alloc] initWithIdentifier:@"com.noaccl.tweak"];
        [preferences registerDefaults:@{@"Enabled": @YES}];
        [preferences registerPreferenceChangeBlock:^{
            dispatch_async(dispatch_get_main_queue(), ^{ Refresh(); });
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *notification) {
                if (pendingRequest) NoAcclPresentFirstRequestIfNeeded();
            }];
        Refresh();
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
    [preferences setBool:enabled forKey:@"Enabled"];
    Refresh();
    Broadcast();
}

void NoAcclSetDecisionForBundle(NSString *bundleID, NoAcclDecision decision) {
    NoAcclInitializePolicy();
    if (!bundleID.length) return;
    if (decision == NoAcclDecisionTemporaryDeny) {
        if ([bundleID isEqual:NoAcclBundleIdentifier()]) {
            temporaryDenied = YES;
            Refresh();
        }
        return;
    }
    // A separate key per app avoids lost updates when two processes grant access concurrently.
    NSDictionary *record = NoAcclRecordForDecision(decision);
    [preferences setObject:record forKey:NoAcclRuleKey(bundleID)];
    if ([bundleID isEqual:NoAcclBundleIdentifier()]) temporaryDenied = NO;
    Refresh();
    Broadcast();
}

void NoAcclRemoveDecisionForBundle(NSString *bundleID) {
    NoAcclInitializePolicy();
    if (!bundleID.length) return;
    [preferences removeObjectForKey:NoAcclRuleKey(bundleID)];
    if ([bundleID isEqual:NoAcclBundleIdentifier()]) temporaryDenied = NO;
    Refresh();
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

void NoAcclResetAllDecisions(void) {
    for (NSString *bundleID in NoAcclAllDecisions()) {
        [preferences setObject:NoAcclRecordForDecision(NoAcclDecisionAsk) forKey:NoAcclRuleKey(bundleID)];
    }
    temporaryDenied = NO;
    Refresh();
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
    if (NoAcclDecisionForCurrentProcess() != NoAcclDecisionAsk) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        pendingRequest = YES;
        if (promptScheduled || NoAcclDecisionForCurrentProcess() != NoAcclDecisionAsk) return;
        UIViewController *controller = VisibleController();
        if (!controller || [controller isKindOfClass:UIAlertController.class]) return;
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
