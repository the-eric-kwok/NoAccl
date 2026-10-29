// Created by 郭耀铭 on 2026/10/15.
#import <Preferences/PSViewController.h>
#import <UIKit/UIImage+Private.h>
#import <dlfcn.h>
#import "../NoAcclPolicy.h"
#import "../NoAcclLocalization.h"

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
@end
@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *applicationType;
@end

@interface NoAcclPrefsController : PSViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic) UITableView *table;
@property (nonatomic) NSArray<NSDictionary *> *applications;
@property (nonatomic) NSCache<NSString *, UIImage *> *icons;
@property (nonatomic) NSDictionary *decisions;
@end

@implementation NoAcclPrefsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"NoAccl";
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.delegate = self;
    self.table.dataSource = self;
    [self.view addSubview:self.table];
    self.icons = [NSCache new];
    self.icons.countLimit = 64;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reloadApplications)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reloadApplications)
        name:NoAcclPolicyChanged object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadApplications];
}

- (void)reloadApplications {
    if (!self.isViewLoaded) return;
    dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_LAZY);
    NSMutableDictionary *apps = [NSMutableDictionary dictionary];
    NSSet<NSString *> *requested = NoAcclRequestedBundleIDs();
    NSDictionary *decisions = NoAcclAllDecisions();
    self.decisions = decisions;
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if ([workspaceClass respondsToSelector:@selector(defaultWorkspace)]) {
        for (LSApplicationProxy *proxy in [[workspaceClass defaultWorkspace] allInstalledApplications]) {
            NSString *identifier = proxy.bundleIdentifier;
            if (!identifier.length || [identifier isEqual:@"com.apple.springboard"] ||
                (![requested containsObject:identifier] && !decisions[identifier])) continue;
            apps[identifier] = @{@"id": identifier, @"name": proxy.localizedName ?: identifier, @"installed": @YES};
        }
    }
    NSMutableSet *visibleIDs = [requested mutableCopy];
    [visibleIDs addObjectsFromArray:decisions.allKeys];
    for (NSString *identifier in visibleIDs) {
        if (!apps[identifier]) apps[identifier] = @{@"id": identifier, @"name": identifier, @"installed": @NO};
    }
    self.applications = [apps.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedStandardCompare:b[@"name"]];
    }];
    [self.table reloadData];
}

- (UIImage *)iconForApplication:(NSDictionary *)app {
    if (![app[@"installed"] boolValue]) return [UIImage systemImageNamed:@"app"];
    NSString *identifier = app[@"id"];
    UIImage *icon = [self.icons objectForKey:identifier];
    if (!icon && [UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
        icon = [UIImage _applicationIconImageForBundleIdentifier:identifier
            format:MIIconVariantSmall scale:self.view.traitCollection.displayScale];
        if (icon) [self.icons setObject:icon forKey:identifier];
    }
    return icon ?: [UIImage systemImageNamed:@"app"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 1 ? self.applications.count : 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return NoAcclLocalizedString(@"When enabled, only allowed apps can access motion data.");
    if (section == 1) return NoAcclLocalizedString(@"Shows apps that requested motion data or have a saved permission.");
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (indexPath.section == 0) {
        cell.textLabel.text = NoAcclLocalizedString(@"Enable Protection");
        UISwitch *toggle = [UISwitch new];
        toggle.on = NoAcclEnabled();
        [toggle addTarget:self action:@selector(toggleProtection:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else if (indexPath.section == 2) {
        cell.textLabel.text = NoAcclLocalizedString(@"Reset All Permissions");
        cell.textLabel.textColor = UIColor.systemRedColor;
    } else {
        NSDictionary *app = self.applications[indexPath.row];
        NSInteger decision = [self.decisions[app[@"id"]] integerValue];
        NSString *status = NoAcclLocalizedString(decision == NoAcclDecisionAllow ? @"Allow" : decision == NoAcclDecisionPermanentDeny ? @"Deny" : @"Ask (Block by Default)");
        UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
        content.text = app[@"name"];
        NSString *suffix = [app[@"installed"] boolValue] ? @"" : [NSString stringWithFormat:@" · %@", NoAcclLocalizedString(@"Not Installed")];
        content.secondaryText = [NSString stringWithFormat:@"%@ · %@%@", status, app[@"id"], suffix];
        content.secondaryTextProperties.numberOfLines = 2;
        content.image = [self iconForApplication:app];
        content.imageProperties.maximumSize = CGSizeMake(32, 32);
        content.imageProperties.reservedLayoutSize = CGSizeMake(32, 32);
        content.imageProperties.cornerRadius = 7;
        cell.contentConfiguration = content;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}
- (void)toggleProtection:(UISwitch *)toggle { NoAcclSetEnabled(toggle.on); }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) return;
    if (indexPath.section == 2) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NoAcclLocalizedString(@"Reset All Permissions?")
            message:NoAcclLocalizedString(@"Apps will ask again the next time they request motion data in the foreground.") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NoAcclLocalizedString(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:NoAcclLocalizedString(@"Reset") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            NoAcclResetAllDecisions();
            [self reloadApplications];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    NSDictionary *app = self.applications[indexPath.row];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:app[@"name"] message:app[@"id"] preferredStyle:UIAlertControllerStyleAlert];
    NSArray *titles = @[NoAcclLocalizedString(@"Allow"), NoAcclLocalizedString(@"Deny"), NoAcclLocalizedString(@"Ask Next Time")];
    NSArray *values = @[@(NoAcclDecisionAllow), @(NoAcclDecisionPermanentDeny), @(NoAcclDecisionAsk)];
    for (NSUInteger index = 0; index < titles.count; index++) {
        [alert addAction:[UIAlertAction actionWithTitle:titles[index] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            NoAcclSetDecisionForBundle(app[@"id"], [values[index] integerValue]);
            [self reloadApplications];
        }]];
    }
    if (![app[@"installed"] boolValue]) {
        [alert addAction:[UIAlertAction actionWithTitle:NoAcclLocalizedString(@"Delete Saved Permission") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            NoAcclRemoveDecisionForBundle(app[@"id"]);
            [self viewWillAppear:NO];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:NoAcclLocalizedString(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
