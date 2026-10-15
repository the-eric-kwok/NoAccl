#import <Foundation/Foundation.h>
#import "NoAcclPolicy.h"

FOUNDATION_EXPORT NSString *NoAcclRuleKey(NSString *bundleID);
FOUNDATION_EXPORT NoAcclDecision NoAcclDecisionFromRecord(id record);
FOUNDATION_EXPORT NSDictionary *NoAcclRecordForDecision(NoAcclDecision decision);
