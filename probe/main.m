// Created by 郭耀铭 on 2026/10/15.
#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>

@interface ProbeController : UIViewController
@property (nonatomic) NSMutableArray<CMMotionManager *> *managers;
@property (nonatomic) UILabel *status;
@property (nonatomic) NSUInteger accelerometerCount;
@property (nonatomic) NSUInteger motionCount;
@property (nonatomic) NSUInteger pollCount;
@property (nonatomic) NSUInteger errors;
@property (nonatomic) NSTimer *timer;
@property (nonatomic) BOOL running;
@property (nonatomic) NSString *latest;
@end
@implementation ProbeController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.managers = [NSMutableArray array];
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:30]]];
    UILabel *title = [UILabel new];
    title.text = @"NoAccl · 真机验证";
    title.font = [UIFont boldSystemFontOfSize:24];
    [stack addArrangedSubview:title];
    for (NSString *name in @[@"开始全部接口", @"停止全部接口", @"清零计数", @"打开 NoAccl 设置"]) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:name forState:UIControlStateNormal];
        [button addTarget:self action:@selector(perform:) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:button];
    }
    self.status = [UILabel new];
    self.status.numberOfLines = 0;
    self.status.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
    [stack addArrangedSubview:self.status];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
    [self refresh];
}
- (void)perform:(UIButton *)button {
    NSString *title = button.currentTitle;
    if ([title isEqual:@"开始全部接口"]) [self start];
    else if ([title isEqual:@"停止全部接口"]) [self stop];
    else if ([title isEqual:@"打开 NoAccl 设置"]) [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"prefs:root=NoAcclPrefs"] options:@{} completionHandler:nil];
    else { self.accelerometerCount = self.motionCount = self.pollCount = self.errors = 0; self.latest = @""; }
    [self refresh];
}
- (void)stop {
    for (CMMotionManager *manager in self.managers) {
        [manager stopAccelerometerUpdates];
        [manager stopDeviceMotionUpdates];
    }
    self.running = NO;
}
- (void)start {
    [self stop];
    [self.managers removeAllObjects];
    self.running = YES;
    __weak ProbeController *weakSelf = self;
    for (NSUInteger index = 0; index < 6; index++) {
        CMMotionManager *manager = [CMMotionManager new];
        manager.accelerometerUpdateInterval = 0.1;
        manager.deviceMotionUpdateInterval = 0.1;
        [self.managers addObject:manager];
        CMDeviceMotionHandler handler = ^(CMDeviceMotion *data, NSError *error) {
            if (data) { weakSelf.motionCount++; weakSelf.latest = [NSString stringWithFormat:@"DM x=%.4f", data.userAcceleration.x]; }
            if (error) weakSelf.errors++;
        };
        if (index == 0) [manager startAccelerometerUpdates];
        if (index == 1) [manager startAccelerometerUpdatesToQueue:NSOperationQueue.mainQueue withHandler:^(CMAccelerometerData *data, NSError *error) {
            if (data) { weakSelf.accelerometerCount++; weakSelf.latest = [NSString stringWithFormat:@"ACC x=%.4f", data.acceleration.x]; }
            if (error) weakSelf.errors++;
        }];
        if (index == 2) [manager startDeviceMotionUpdates];
        if (index == 3) [manager startDeviceMotionUpdatesToQueue:NSOperationQueue.mainQueue withHandler:handler];
        if (index == 4) [manager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryZVertical];
        if (index == 5) [manager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryZVertical toQueue:NSOperationQueue.mainQueue withHandler:handler];
    }
}
- (void)refresh {
    for (CMMotionManager *manager in self.managers) {
        if (manager.accelerometerData) self.pollCount++;
        if (manager.deviceMotion) self.pollCount++;
    }
    self.status.text = [NSString stringWithFormat:@"请求：%@\n加速度回调：%lu\n设备运动回调：%lu\n轮询非空：%lu\n错误：%lu\n%@",
        self.running ? @"已启动" : @"已停止", (unsigned long)self.accelerometerCount, (unsigned long)self.motionCount,
        (unsigned long)self.pollCount, (unsigned long)self.errors, self.latest ?: @""];
}
@end
@interface ProbeApp : UIResponder <UIApplicationDelegate>
@property (nonatomic) UIWindow *window;
@end
@implementation ProbeApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [ProbeController new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(ProbeApp.class)); }
}
