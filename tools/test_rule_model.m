#import <Foundation/Foundation.h>
#import "../NoAcclRule.h"

static NSUInteger failures;

static void AssertEqualInteger(NSInteger actual, NSInteger expected, NSString *name) {
    if (actual != expected) {
        failures++;
        fprintf(stderr, "%s: expected %ld, got %ld\n", name.UTF8String, (long)expected, (long)actual);
    }
}

static void AssertEqualString(NSString *actual, NSString *expected, NSString *name) {
    if (![actual isEqualToString:expected]) {
        failures++;
        fprintf(stderr, "%s: expected %s, got %s\n", name.UTF8String, expected.UTF8String, actual.UTF8String);
    }
}

int main(void) {
    @autoreleasepool {
        AssertEqualString(NoAcclRuleKey(@"com.example.app"), @"Rule.com.example.app", @"rule key");
        AssertEqualInteger(NoAcclDecisionFromRecord(nil), NoAcclDecisionAsk, @"missing record");
        AssertEqualInteger(NoAcclDecisionFromRecord(@"invalid"), NoAcclDecisionAsk, @"invalid record");
        AssertEqualInteger(NoAcclDecisionFromRecord(@{@"decision": @(NoAcclDecisionAllow)}),
            NoAcclDecisionAllow, @"allow record");
        AssertEqualInteger(NoAcclDecisionFromRecord(@{@"decision": @(NoAcclDecisionPermanentDeny)}),
            NoAcclDecisionPermanentDeny, @"permanent deny record");
        AssertEqualInteger(NoAcclDecisionFromRecord(@{@"decision": @(NoAcclDecisionTemporaryDeny)}),
            NoAcclDecisionAsk, @"temporary deny is runtime-only");
        AssertEqualInteger(NoAcclDecisionFromRecord(@{@"decision": @99}), NoAcclDecisionAsk, @"unknown record");

        NSDictionary *record = NoAcclRecordForDecision(NoAcclDecisionPermanentDeny);
        AssertEqualInteger([record[@"decision"] integerValue], NoAcclDecisionPermanentDeny, @"record decision");
        NSString *revision = [record[@"revision"] isKindOfClass:NSString.class] ? record[@"revision"] : nil;
        if (!revision.length) failures++;
    }
    return failures ? 1 : 0;
}
