// Created by 郭耀铭 on 2026/10/15.
#import <Preferences/PSViewController.h>
#import <dlfcn.h>
#import "../NoAcclPolicy.h"

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
@end
@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *applicationType;
@end

@interface NoAcclPrefsController : PSViewController <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating>
@property (nonatomic) UITableView *table;
@property (nonatomic) NSArray<NSDictionary *> *applications;
@property (nonatomic) NSArray<NSDictionary *> *filtered;
@property (nonatomic) UISearchController *search;
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
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"搜索应用名称或标识符";
    self.table.tableHeaderView = self.search.searchBar;
    self.definesPresentationContext = YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_LAZY);
    NSMutableDictionary *apps = [NSMutableDictionary dictionary];
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if ([workspaceClass respondsToSelector:@selector(defaultWorkspace)]) {
        for (LSApplicationProxy *proxy in [[workspaceClass defaultWorkspace] allInstalledApplications]) {
            NSString *identifier = proxy.bundleIdentifier;
            if (!identifier.length || [identifier isEqual:@"com.apple.springboard"]) continue;
            apps[identifier] = @{@"id": identifier, @"name": proxy.localizedName ?: identifier, @"installed": @YES};
        }
    }
    for (NSString *identifier in NoAcclAllDecisions()) {
        if (!apps[identifier]) apps[identifier] = @{@"id": identifier, @"name": identifier, @"installed": @NO};
    }
    self.applications = [apps.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedStandardCompare:b[@"name"]];
    }];
    [self updateSearchResultsForSearchController:self.search];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)controller {
    NSString *query = controller.searchBar.text ?: @"";
    self.filtered = query.length ? [self.applications filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(NSDictionary *app, NSDictionary *bindings) {
            return [app[@"name"] localizedCaseInsensitiveContainsString:query] ||
                [app[@"id"] localizedCaseInsensitiveContainsString:query];
        }]] : self.applications;
    [self.table reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 1 ? self.filtered.count : 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"开启后默认拒绝。允许后加入白名单；“拒绝，下次再说”只影响本次应用进程。设备运动数据也受保护，可能影响姿态功能。";
    if (section == 1) return @"未设置的应用会在首次前台请求时询问。后台请求默认阻断。仅保护成功注入的应用及支持的 Core Motion 接口。";
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (indexPath.section == 0) {
        cell.textLabel.text = @"启用保护";
        UISwitch *toggle = [UISwitch new];
        toggle.on = NoAcclEnabled();
        [toggle addTarget:self action:@selector(toggleProtection:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else if (indexPath.section == 2) {
        cell.textLabel.text = @"重置全部权限";
        cell.textLabel.textColor = UIColor.systemRedColor;
    } else {
        NSDictionary *app = self.filtered[indexPath.row];
        NSInteger decision = [NoAcclAllDecisions()[app[@"id"]] integerValue];
        NSString *status = decision == NoAcclDecisionAllow ? @"允许" : decision == NoAcclDecisionPermanentDeny ? @"永久拒绝" : @"询问（默认阻断）";
        cell.textLabel.text = app[@"name"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@%@", status, app[@"id"], [app[@"installed"] boolValue] ? @"" : @" · 未安装"];
        cell.detailTextLabel.numberOfLines = 2;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}
- (void)toggleProtection:(UISwitch *)toggle { NoAcclSetEnabled(toggle.on); }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) return;
    if (indexPath.section == 2) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重置全部权限？"
            message:@"应用将在下次前台请求时重新询问。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"重置" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            NoAcclResetAllDecisions();
            [self.table reloadData];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    NSDictionary *app = self.filtered[indexPath.row];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:app[@"name"] message:app[@"id"] preferredStyle:UIAlertControllerStyleAlert];
    NSArray *titles = @[@"允许", @"永久拒绝", @"下次询问"];
    NSArray *values = @[@(NoAcclDecisionAllow), @(NoAcclDecisionPermanentDeny), @(NoAcclDecisionAsk)];
    for (NSUInteger index = 0; index < titles.count; index++) {
        [alert addAction:[UIAlertAction actionWithTitle:titles[index] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            NoAcclSetDecisionForBundle(app[@"id"], [values[index] integerValue]);
            [self.table reloadData];
        }]];
    }
    if (![app[@"installed"] boolValue]) {
        [alert addAction:[UIAlertAction actionWithTitle:@"删除历史规则" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            NoAcclRemoveDecisionForBundle(app[@"id"]);
            [self viewWillAppear:NO];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
