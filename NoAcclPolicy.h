#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, NoAcclDecision) {
    NoAcclDecisionAsk = 0,
    NoAcclDecisionAllow = 1,
    NoAcclDecisionTemporaryDeny = 2,
    NoAcclDecisionPermanentDeny = 3,
};
FOUNDATION_EXPORT NSString * const NoAcclPolicyChanged;
FOUNDATION_EXPORT NSString *NoAcclBundleIdentifier(void);
FOUNDATION_EXPORT NoAcclDecision NoAcclDecisionForCurrentProcess(void);
FOUNDATION_EXPORT void NoAcclSetDecisionForBundle(NSString *bundleID, NoAcclDecision decision);
FOUNDATION_EXPORT void NoAcclRemoveDecisionForBundle(NSString *bundleID);
FOUNDATION_EXPORT void NoAcclResetAllDecisions(void);
FOUNDATION_EXPORT NSDictionary *NoAcclAllDecisions(void);
FOUNDATION_EXPORT BOOL NoAcclEnabled(void);
FOUNDATION_EXPORT void NoAcclSetEnabled(BOOL enabled);
FOUNDATION_EXPORT void NoAcclPresentFirstRequestIfNeeded(void);
FOUNDATION_EXPORT void NoAcclInitializePolicy(void);
