// Created by 郭耀铭 on 2026/10/28.
#import "NoAcclStore.h"
#import "NoAcclRule.h"
#import <notify.h>
#import <dlfcn.h>
#import <rootless.h>
#define LIGHTMESSAGING_USE_ROCKETBOOTSTRAP 0
#define LIGHTMESSAGING_TIMEOUT 500
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincompatible-pointer-types-discards-qualifiers"
#import <LightMessaging/LightMessaging.h>
#pragma clang diagnostic pop

static NSString *const StorePath = @"/var/mobile/Library/Preferences/com.noaccl.tweak.plist";
static const char *StoreNotification = "com.noaccl.tweak/ReloadPrefs";
static NSDictionary *serverState;

static NSString *CallerBundle(LMMessage *message, BOOL *settings) {
    mach_msg_audit_trailer_t *trailer = (void *)((uint8_t *)message + ((message->head.msgh_size + 3) & ~3));
    if (trailer->msgh_trailer_type != MACH_MSG_TRAILER_FORMAT_0 ||
        trailer->msgh_trailer_size < sizeof(mach_msg_audit_trailer_t)) return nil;
    if (trailer->msgh_audit.val[1] != 501) return nil;
    int (*pidpath)(int, void *, uint32_t) = dlsym(RTLD_DEFAULT, "proc_pidpath");
    char path[4096] = {0};
    if (!pidpath || pidpath(trailer->msgh_audit.val[5], path, sizeof(path)) <= 0) return nil;
    NSString *executable = @(path);
    *settings = [executable isEqual:@"/Applications/Preferences.app/Preferences"];
    NSString *bundlePath = executable.stringByDeletingLastPathComponent;
    if (![bundlePath.pathExtension isEqual:@"app"]) return nil;
    return [NSBundle bundleWithPath:bundlePath].bundleIdentifier;
}

static BOOL ValidValue(NSString *key, id value) {
    if ([key isEqual:@"Enabled"] || [key hasPrefix:@"Requested."]) return [value isKindOfClass:NSNumber.class];
    if (![key hasPrefix:@"Rule."] || ![value isKindOfClass:NSDictionary.class]) return NO;
    NSNumber *decision = value[@"decision"];
    NSString *revision = value[@"revision"];
    return [decision isKindOfClass:NSNumber.class] &&
        (decision.integerValue == NoAcclDecisionAsk || decision.integerValue == NoAcclDecisionAllow ||
         decision.integerValue == NoAcclDecisionPermanentDeny) &&
        [revision isKindOfClass:NSString.class] && revision.length > 0;
}

static void HandleStoreMessage(CFMachPortRef port, void *bytes, CFIndex size, void *info) {
    @autoreleasepool {
        LMMessage *message = bytes;
        if (size < sizeof(LMMessage)) {
            mach_msg_destroy(&message->head);
            return;
        }
        mach_port_t replyPort = message->head.msgh_remote_port;
        if ((message->head.msgh_bits & MACH_MSGH_BITS_COMPLEX) ||
            message->data.in_line.length > size - offsetof(LMMessage, data.in_line.bytes)) {
            LMSendPropertyListReply(replyPort, @{@"ok": @NO});
            message->head.msgh_remote_port = MACH_PORT_NULL;
            mach_msg_destroy(&message->head);
            return;
        }
        BOOL settings = NO;
        NSString *caller = CallerBundle(message, &settings);
        id request = LMResponseConsumePropertyList((LMResponseBuffer *)message);
        NSDictionary *response = @{@"ok": @NO};
        if (caller.length && [request isKindOfClass:NSDictionary.class]) {
            NSString *key = request[@"key"];
            NSString *operation = request[@"operation"];
            BOOL read = [operation isEqual:@"read"];
            BOOL validKey = [key isKindOfClass:NSString.class] && key.length < 300 &&
                ([key isEqual:@"Enabled"] || [key hasPrefix:@"Rule."] || [key hasPrefix:@"Requested."]);
            BOOL ownKey = validKey && ([key isEqual:NoAcclRuleKey(caller)] ||
                [key isEqual:[@"Requested." stringByAppendingString:caller]]);
            BOOL ok = read;
            if (!read && validKey && (settings || ownKey)) {
                NSMutableDictionary *next = [serverState mutableCopy];
                if ([operation isEqual:@"set"] && ValidValue(key, request[@"value"])) {
                    next[key] = request[@"value"];
                    ok = YES;
                } else if ([operation isEqual:@"remove"]) {
                    [next removeObjectForKey:key];
                    ok = YES;
                }
                if (ok) {
                    NSError *error;
                    NSData *data = [NSPropertyListSerialization dataWithPropertyList:next
                        format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
                    ok = data && [data writeToFile:StorePath options:NSDataWritingAtomic error:&error];
                    if (ok) {
                        serverState = next;
                        notify_post(StoreNotification);
                    } else NSLog(@"[NoAccl] Shared rule save failed: %@", error);
                }
            }
            NSMutableDictionary *visible = [NSMutableDictionary dictionary];
            if (settings) [visible addEntriesFromDictionary:serverState];
            else for (NSString *item in @[@"Enabled", NoAcclRuleKey(caller), [@"Requested." stringByAppendingString:caller]]) {
                if (serverState[item]) visible[item] = serverState[item];
            }
            response = @{@"ok": @(ok), @"state": visible};
        }
        LMSendPropertyListReply(replyPort, response);
    }
}

void NoAcclStartStoreServer(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *state = [[NSDictionary dictionaryWithContentsOfFile:StorePath] mutableCopy];
        if (![state[@"StoreVersion"] isEqual:@1]) {
            NSMutableDictionary *legacy = [[NSDictionary dictionaryWithContentsOfFile:
                ROOT_PATH_NS(@"/var/mobile/Library/Preferences/com.noaccl.tweak.plist")] mutableCopy] ?: [NSMutableDictionary dictionary];
            [legacy addEntriesFromDictionary:state ?: @{}];
            legacy[@"StoreVersion"] = @1;
            if ([legacy writeToFile:StorePath atomically:YES]) state = legacy;
            else NSLog(@"[NoAccl] Shared preferences migration failed");
        }
        serverState = state ?: @{};
        kern_return_t cy = LMStartService("cy:com.noaccl.preferences", CFRunLoopGetMain(), HandleStoreMessage);
        kern_return_t lh = LMStartService("lh:com.noaccl.preferences", CFRunLoopGetMain(), HandleStoreMessage);
        NSLog(@"[NoAccl] Shared preferences service cy=%d lh=%d", cy, lh);
    });
}

@implementation NoAcclStore {
    NSDictionary *_state;
    NSLock *_lock;
    dispatch_queue_t _queue;
    dispatch_block_t _changed;
    LMConnection _connections[2];
    int _token;
}
- (instancetype)init {
    if ((self = [super init])) {
        _state = @{};
        _lock = [NSLock new];
        _queue = dispatch_queue_create("com.noaccl.preferences", DISPATCH_QUEUE_SERIAL);
        strlcpy(_connections[0].serverName, "cy:com.noaccl.preferences", sizeof(_connections[0].serverName));
        strlcpy(_connections[1].serverName, "lh:com.noaccl.preferences", sizeof(_connections[1].serverName));
        [self exchange:@{@"operation": @"read"}];
        __weak NoAcclStore *weakSelf = self;
        notify_register_dispatch(StoreNotification, &_token, _queue, ^(int token) {
            NoAcclStore *store = weakSelf;
            [store exchange:@{@"operation": @"read"}];
            [store changed];
        });
    }
    return self;
}
- (BOOL)exchange:(NSDictionary *)request {
    [_lock lock];
    BOOL ok = NO;
    BOOL received = NO;
    for (NSUInteger index = 0; index < 2; index++) {
        LMResponseBuffer buffer;
        kern_return_t result = LMConnectionSendTwoWayPropertyList(&_connections[index], 0, request, &buffer);
        if (result != KERN_SUCCESS) continue;
        id response = LMResponseConsumePropertyList(&buffer);
        if ([response isKindOfClass:NSDictionary.class] && [response[@"state"] isKindOfClass:NSDictionary.class]) {
            _state = [response[@"state"] copy];
            ok = [response[@"ok"] boolValue];
            received = YES;
        }
        break;
    }
    if (!received) _state = @{};
    [_lock unlock];
    return ok;
}
- (void)changed {
    dispatch_async(dispatch_get_main_queue(), ^{ if (self->_changed) self->_changed(); });
}
- (id)objectForKey:(NSString *)key {
    [_lock lock];
    id value = _state[key];
    [_lock unlock];
    return value;
}
- (BOOL)boolForKey:(NSString *)key default:(BOOL)fallback {
    id value = [self objectForKey:key];
    return value ? [value boolValue] : fallback;
}
- (NSDictionary *)dictionaryRepresentation {
    [self exchange:@{@"operation": @"read"}];
    [_lock lock];
    NSDictionary *state = _state;
    [_lock unlock];
    return state;
}
- (BOOL)setObject:(id)value forKey:(NSString *)key {
    BOOL ok = [self exchange:@{@"operation": @"set", @"key": key, @"value": value}];
    if (ok) [self changed];
    return ok;
}
- (BOOL)removeObjectForKey:(NSString *)key {
    BOOL ok = [self exchange:@{@"operation": @"remove", @"key": key}];
    if (ok) [self changed];
    return ok;
}
- (void)registerPreferenceChangeBlock:(dispatch_block_t)block { _changed = [block copy]; }
- (void)dealloc {
    notify_cancel(_token);
    for (NSUInteger index = 0; index < 2; index++) {
        if (_connections[index].serverPort) mach_port_deallocate(mach_task_self(), _connections[index].serverPort);
    }
}
@end
