// Created by 郭耀铭 on 2026/10/15.
#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import "NoAcclPolicy.h"
#import "NoAcclStore.h"

@interface NAStream : NSObject
@property (nonatomic, copy) dispatch_block_t resume;
@property (nonatomic) BOOL active;
@property (nonatomic) NSUInteger generation;
@end
@implementation NAStream
@end

static NSHashTable *managers;
static char accelerometerKey, motionKey;
static __thread BOOL revoking;
static __thread NSUInteger forwardingDepth;
static atomic_bool loggedBlockedRequest;

static NAStream *Stream(CMMotionManager *manager, BOOL motion) {
    const void *key = motion ? &motionKey : &accelerometerKey;
    NAStream *stream = objc_getAssociatedObject(manager, key);
    if (!stream) {
        stream = [NAStream new];
        objc_setAssociatedObject(manager, key, stream, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        @synchronized (managers) { [managers addObject:manager]; }
    }
    return stream;
}

static void NoteBlockedRequest(void) {
    if (atomic_exchange(&loggedBlockedRequest, true)) return;
    NSLog(@"[NoAccl] Blocked first CoreMotion request from %@", NoAcclBundleIdentifier());
}

static BOOL Allowed(void) {
    NoAcclMarkCurrentProcessRequested();
    BOOL allowed = NoAcclDecisionForCurrentProcess() == NoAcclDecisionAllow;
    if (!allowed) NoteBlockedRequest();
    return allowed;
}

static void PolicyChanged(void) {
    NSArray *snapshot;
    @synchronized (managers) { snapshot = managers.allObjects; }
    for (CMMotionManager *manager in snapshot) {
        @synchronized (manager) {
            for (NSNumber *kind in @[@NO, @YES]) {
                NAStream *stream = Stream(manager, kind.boolValue);
                @try {
                    if (Allowed()) {
                        if (!stream.active && stream.resume) stream.resume();
                    } else if (stream.active) {
                        revoking = YES;
                        if (kind.boolValue) [manager stopDeviceMotionUpdates];
                        else [manager stopAccelerometerUpdates];
                        revoking = NO;
                    }
                } @catch (NSException *exception) {
                    revoking = NO;
                    NSLog(@"[NoAccl] Failed to update stream for %@: %@", NoAcclBundleIdentifier(), exception);
                }
            }
        }
    }
}

%group ApplicationHooks
%hook CMMotionManager
- (void)startAccelerometerUpdates {
    if (forwardingDepth) {
        %orig;
        return;
    }
    @synchronized (self) {
        NAStream *stream = Stream(self, NO);
        __weak CMMotionManager *weakManager = self;
        stream.resume = ^{ [weakManager startAccelerometerUpdates]; };
        stream.generation++;
        if (!Allowed()) {
            NoAcclPresentFirstRequestIfNeeded();
            return;
        }
        stream.active = YES;
        forwardingDepth++;
        @try {
            %orig;
        } @finally {
            forwardingDepth--;
        }
    }
}

- (void)startAccelerometerUpdatesToQueue:(NSOperationQueue *)queue withHandler:(CMAccelerometerHandler)handler {
    if (forwardingDepth) {
        %orig;
        return;
    }
    @synchronized (self) {
        NAStream *stream = Stream(self, NO);
        __weak CMMotionManager *weakManager = self;
        stream.resume = ^{ [weakManager startAccelerometerUpdatesToQueue:queue withHandler:handler]; };
        stream.generation++;
        if (!Allowed()) {
            NoAcclPresentFirstRequestIfNeeded();
            return;
        }
        stream.active = YES;
        NSUInteger generation = stream.generation;
        CMAccelerometerHandler filtered = ^(CMAccelerometerData *data, NSError *error) {
            CMMotionManager *manager = weakManager;
            if (!manager) return;
            @synchronized (manager) {
                NAStream *current = Stream(manager, NO);
                if (Allowed() && current.active && current.generation == generation && handler) handler(data, error);
            }
        };
        forwardingDepth++;
        @try {
            %orig(queue, filtered);
        } @finally {
            forwardingDepth--;
        }
    }
}

- (void)stopAccelerometerUpdates {
    @synchronized (self) {
        NAStream *stream = Stream(self, NO);
        stream.active = NO;
        stream.generation++;
        if (!revoking) stream.resume = nil;
        %orig;
    }
}

- (CMAccelerometerData *)accelerometerData {
    if (!Allowed()) {
        NoAcclPresentFirstRequestIfNeeded();
        return nil;
    }
    return %orig;
}

- (void)startDeviceMotionUpdates {
    if (forwardingDepth) {
        %orig;
        return;
    }
    @synchronized (self) {
        NAStream *stream = Stream(self, YES);
        __weak CMMotionManager *weakManager = self;
        stream.resume = ^{ [weakManager startDeviceMotionUpdates]; };
        stream.generation++;
        if (!Allowed()) {
            NoAcclPresentFirstRequestIfNeeded();
            return;
        }
        stream.active = YES;
        forwardingDepth++;
        @try {
            %orig;
        } @finally {
            forwardingDepth--;
        }
    }
}

- (void)startDeviceMotionUpdatesToQueue:(NSOperationQueue *)queue withHandler:(CMDeviceMotionHandler)handler {
    if (forwardingDepth) {
        %orig;
        return;
    }
    @synchronized (self) {
        NAStream *stream = Stream(self, YES);
        __weak CMMotionManager *weakManager = self;
        stream.resume = ^{ [weakManager startDeviceMotionUpdatesToQueue:queue withHandler:handler]; };
        stream.generation++;
        if (!Allowed()) {
            NoAcclPresentFirstRequestIfNeeded();
            return;
        }
        stream.active = YES;
        NSUInteger generation = stream.generation;
        CMDeviceMotionHandler filtered = ^(CMDeviceMotion *data, NSError *error) {
            CMMotionManager *manager = weakManager;
            if (!manager) return;
            @synchronized (manager) {
                NAStream *current = Stream(manager, YES);
                if (Allowed() && current.active && current.generation == generation && handler) handler(data, error);
            }
        };
        forwardingDepth++;
        @try {
            %orig(queue, filtered);
        } @finally {
            forwardingDepth--;
        }
    }
}

- (void)startDeviceMotionUpdatesUsingReferenceFrame:(CMAttitudeReferenceFrame)referenceFrame {
    if (forwardingDepth) {
        %orig;
        return;
    }
    @synchronized (self) {
        NAStream *stream = Stream(self, YES);
        __weak CMMotionManager *weakManager = self;
        stream.resume = ^{ [weakManager startDeviceMotionUpdatesUsingReferenceFrame:referenceFrame]; };
        stream.generation++;
        if (!Allowed()) {
            NoAcclPresentFirstRequestIfNeeded();
            return;
        }
        stream.active = YES;
        forwardingDepth++;
        @try {
            %orig(referenceFrame);
        } @finally {
            forwardingDepth--;
        }
    }
}

- (void)startDeviceMotionUpdatesUsingReferenceFrame:(CMAttitudeReferenceFrame)referenceFrame toQueue:(NSOperationQueue *)queue withHandler:(CMDeviceMotionHandler)handler {
    if (forwardingDepth) {
        %orig;
        return;
    }
    @synchronized (self) {
        NAStream *stream = Stream(self, YES);
        __weak CMMotionManager *weakManager = self;
        stream.resume = ^{ [weakManager startDeviceMotionUpdatesUsingReferenceFrame:referenceFrame toQueue:queue withHandler:handler]; };
        stream.generation++;
        if (!Allowed()) {
            NoAcclPresentFirstRequestIfNeeded();
            return;
        }
        stream.active = YES;
        NSUInteger generation = stream.generation;
        CMDeviceMotionHandler filtered = ^(CMDeviceMotion *data, NSError *error) {
            CMMotionManager *manager = weakManager;
            if (!manager) return;
            @synchronized (manager) {
                NAStream *current = Stream(manager, YES);
                if (Allowed() && current.active && current.generation == generation && handler) handler(data, error);
            }
        };
        forwardingDepth++;
        @try {
            %orig(referenceFrame, queue, filtered);
        } @finally {
            forwardingDepth--;
        }
    }
}

- (void)stopDeviceMotionUpdates {
    @synchronized (self) {
        NAStream *stream = Stream(self, YES);
        stream.active = NO;
        stream.generation++;
        if (!revoking) stream.resume = nil;
        %orig;
    }
}

- (CMDeviceMotion *)deviceMotion {
    if (!Allowed()) {
        NoAcclPresentFirstRequestIfNeeded();
        return nil;
    }
    return %orig;
}

%end
%end

%ctor {
    @autoreleasepool {
        NSString *identifier = NSBundle.mainBundle.bundleIdentifier;
        BOOL isApplication = [NSBundle.mainBundle.bundlePath hasSuffix:@".app"];
        if ([identifier isEqual:@"com.apple.springboard"]) {
            NoAcclStartStoreServer();
            return;
        }
        if (!isApplication || !identifier.length) return;
        managers = [NSHashTable weakObjectsHashTable];
        NoAcclInitializePolicy();
        [NSNotificationCenter.defaultCenter addObserverForName:NoAcclPolicyChanged object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *notification) { PolicyChanged(); }];
        %init(ApplicationHooks);
        NSLog(@"[NoAccl] CoreMotion hooks installed for %@", identifier);
    }
}
