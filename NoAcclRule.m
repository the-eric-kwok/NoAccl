#import "NoAcclRule.h"

NSString *NoAcclRuleKey(NSString *bundleID) {
    return bundleID.length ? [@"Rule." stringByAppendingString:bundleID] : nil;
}

NoAcclDecision NoAcclDecisionFromRecord(id record) {
    if (![record isKindOfClass:NSDictionary.class]) return NoAcclDecisionAsk;
    NSInteger value = [record[@"decision"] integerValue];
    return value == NoAcclDecisionAllow || value == NoAcclDecisionPermanentDeny ?
        (NoAcclDecision)value : NoAcclDecisionAsk;
}

NSDictionary *NoAcclRecordForDecision(NoAcclDecision decision) {
    BOOL valid = decision == NoAcclDecisionAllow || decision == NoAcclDecisionPermanentDeny ||
        decision == NoAcclDecisionAsk;
    if (!valid) return @{};
    return @{@"decision": @(decision), @"revision": NSUUID.UUID.UUIDString};
}
