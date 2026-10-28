// Created by 郭耀铭 on 2026/10/28.
#import <Foundation/Foundation.h>

FOUNDATION_EXPORT void NoAcclStartStoreServer(void);

@interface NoAcclStore : NSObject
- (id)objectForKey:(NSString *)key;
- (BOOL)boolForKey:(NSString *)key default:(BOOL)fallback;
- (NSDictionary *)dictionaryRepresentation;
- (BOOL)setObject:(id)value forKey:(NSString *)key;
- (BOOL)removeObjectForKey:(NSString *)key;
- (void)registerPreferenceChangeBlock:(dispatch_block_t)block;
@end
