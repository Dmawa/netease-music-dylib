#import "NESettingsPage.h"
#import "NEUITheme.h"
#import "NEAppInfo.h"
#import "NEApi.h"
#import "NEImageCache.h"

@interface NESettingsPage () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, strong) UITableView *table;

@property (nonatomic, strong) UIView *accountHeader;
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *uidLabel;
@property (nonatomic, strong) UILabel *vipLabel;

@property (nonatomic, strong, nullable) NSDictionary *profile;
@property (nonatomic, assign) BOOL loggedIn;
@end

@implementation NESettingsPage

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = NE_BG;
        [self build];
    }
    return self;
}

- (void)build {
    _topBar = [[UIView alloc] initWithFrame:CGRectZero];
    _topBar.backgroundColor = NE_PANEL;
    [self addSubview:_topBar];

    _titleLabel = [UILabel new];
    _titleLabel.text = @"设置";
    _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    _titleLabel.textColor = NE_TEXT;
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    [_topBar addSubview:_titleLabel];

    _closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [_closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [_closeBtn setTitleColor:NE_TEXT_DIM forState:UIControlStateNormal];
    _closeBtn.titleLabel.font = [UIFont systemFontOfSize:18];
    [_closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [_topBar addSubview:_closeBtn];

    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    _table.backgroundColor = UIColor.clearColor;
    _table.separatorColor = NE_STROKE;
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = 54;
    _table.sectionHeaderHeight = 12;
    _table.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [self addSubview:_table];

    [self buildAccountHeader];
    _table.tableHeaderView = _accountHeader;
}

- (void)buildAccountHeader {
    _accountHeader = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 116)];

    _avatar = [[UIImageView alloc] initWithFrame:CGRectMake(18, 24, 56, 56)];
    _avatar.backgroundColor = NE_CARD;
    _avatar.layer.cornerRadius = 28;
    _avatar.layer.cornerCurve = kCACornerCurveContinuous;
    _avatar.clipsToBounds = YES;
    _avatar.contentMode = UIViewContentModeScaleAspectFill;
    [_accountHeader addSubview:_avatar];

    _nameLabel = [UILabel new];
    _nameLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _nameLabel.textColor = NE_TEXT;
    [_accountHeader addSubview:_nameLabel];

    _uidLabel = [UILabel new];
    _uidLabel.font = [UIFont systemFontOfSize:11];
    _uidLabel.textColor = NE_TEXT_DIM;
    [_accountHeader addSubview:_uidLabel];

    _vipLabel = [UILabel new];
    _vipLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    _vipLabel.textColor = NEColor(0xF6D48A, 1.0);
    [_accountHeader addSubview:_vipLabel];
}

- (void)reloadData {
    self.loggedIn = [[NEApi shared] isLoggedIn];
    [self updateHeader];
    [self.table reloadData];

    __weak typeof(self) weakSelf = self;
    [[NEApi shared] fetchProfile:^(NSDictionary *profile, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.profile = profile;
        self.loggedIn = (profile != nil) || [[NEApi shared] isLoggedIn];
        [self updateHeader];
        [self.table reloadData];
    }];
}

- (void)updateHeader {
    if (!self.loggedIn) {
        _nameLabel.text = @"未登录";
        _uidLabel.text = @"登录后可查看账号信息";
        _vipLabel.text = @"—";
        _avatar.image = nil;
        return;
    }

    NSString *nick = self.profile[@"nickname"] ?: @"";
    NSNumber *uid = self.profile[@"userId"];
    _nameLabel.text = nick.length ? nick : @"已登录";
    _uidLabel.text = uid ? [NSString stringWithFormat:@"ID：%@", uid] : @"";

    NSInteger vipType = [self.profile[@"vipType"] integerValue];
    if (vipType == 11) {
        _vipLabel.text = @"黑胶 VIP · 会员中心";
    } else if (vipType == 1) {
        _vipLabel.text = @"音乐包";
    } else {
        _vipLabel.text = @"普通用户";
    }

    NSString *avatarURL = self.profile[@"avatarUrl"];
    if (avatarURL.length) {
        __weak typeof(self) weakSelf = self;
        [[NEImageCache shared] loadImageWithURL:avatarURL completion:^(UIImage *image) {
            __strong typeof(weakSelf) self = weakSelf;
            if (image) self.avatar.image = image;
        }];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width;
    CGFloat H = self.bounds.size.height;

    _topBar.frame = CGRectMake(0, 0, W, 44);
    _titleLabel.frame = CGRectMake(0, 0, W, 44);
    _closeBtn.frame = CGRectMake(W - 48, 0, 44, 44);
    _table.frame = CGRectMake(0, 44, W, H - 44);

    if (_accountHeader) {
        _accountHeader.frame = CGRectMake(0, 0, W, 116);
        _nameLabel.frame = CGRectMake(86, 30, W - 110, 22);
        _uidLabel.frame = CGRectMake(86, 54, W - 110, 16);
        _vipLabel.frame = CGRectMake(86, 74, W - 110, 16);
    }
}

#pragma mark - 交互

- (void)closeTapped {
    if ([self.delegate respondsToSelector:@selector(settingsPageDidClose:)]) {
        [self.delegate settingsPageDidClose:self];
    }
}

- (void)logoutTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"退出登录"
        message:@"确定退出当前账号？" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"退出" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if ([self.delegate respondsToSelector:@selector(settingsPageDidLogout:)]) {
            [self.delegate settingsPageDidLogout:self];
        }
    }]];
    [self presentAlert:alert];
}

- (void)presentAlert:(UIAlertController *)alert {
    UIViewController *host = [self topMostController];
    if (host) [host presentViewController:alert animated:YES completion:nil];
}

- (UIViewController *)topMostController {
    UIWindow *window = self.window;
    if (!window) return nil;
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

- (void)showAbout {
    NSString *message = [NSString stringWithFormat:@"%@\n\n版本：%@\n作者：%@",
                         NE_APP_NAME, NE_APP_VERSION, NE_APP_AUTHOR];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"关于"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:alert];
}

- (void)showMessages {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"我的消息"
        message:@"消息功能暂未接入" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:alert];
}

#pragma mark - 表

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    return self.loggedIn ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 2;      // 我的消息 / 关于
    return 1;                        // 退出登录
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return nil;
    return @"账号";
}

- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)section {
    if (section == 0) return nil;
    UILabel *label = [UILabel new];
    label.font = [UIFont systemFontOfSize:12];
    label.textColor = NE_TEXT_DIM;
    label.text = @"  账号";
    return label;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"settings";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cid];
        cell.backgroundColor = NE_CARD;
        cell.textLabel.textColor = NE_TEXT;
        cell.detailTextLabel.textColor = NE_TEXT_DIM;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UIView *sel = [UIView new];
        sel.backgroundColor = NE_PANEL;
        cell.selectedBackgroundView = sel;
    }

    if (ip.section == 0 && ip.row == 0) {
        cell.textLabel.text = @"我的消息";
        cell.detailTextLabel.text = @"暂无新消息";
    } else if (ip.section == 0 && ip.row == 1) {
        cell.textLabel.text = @"关于";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"v%@", NE_APP_VERSION];
    } else {
        cell.textLabel.text = @"退出登录";
        cell.textLabel.textColor = [UIColor colorWithRed:1 green:0.35 blue:0.35 alpha:1];
        cell.detailTextLabel.text = @"";
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0 && ip.row == 0) { [self showMessages]; return; }
    if (ip.section == 0 && ip.row == 1) { [self showAbout]; return; }
    [self logoutTapped];
}

@end
