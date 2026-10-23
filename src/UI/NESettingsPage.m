#import "NESettingsPage.h"
#import "NEUITheme.h"
#import "NEAppInfo.h"
#import "NEApi.h"
#import "NEImageCache.h"

typedef NS_ENUM(NSInteger, NESettingsAction) {
    NESettingsActionPlaceholder = 0,   // 暂未接入
    NESettingsActionMessages,
    NESettingsActionShare,
    NESettingsActionAbout,
    NESettingsActionSwitchAccount,
    NESettingsActionLogout,
};

@interface NESettingsPage () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, strong) UITableView *table;

@property (nonatomic, strong) UIView *accountHeader;
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *uidLabel;
@property (nonatomic, strong) UIView *vipCard;
@property (nonatomic, strong) UILabel *vipTitle;
@property (nonatomic, strong) UILabel *vipDesc;
@property (nonatomic, strong) UIButton *vipBtn;
@property (nonatomic, strong) UILabel *checkLabel;

@property (nonatomic, strong, nullable) NSDictionary *profile;
@property (nonatomic, assign) BOOL loggedIn;
/** 分组标题与行 */
@property (nonatomic, strong) NSArray<NSArray<NSString *> *> *sections;
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
    _titleLabel.text = @"我的";
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
    _table.rowHeight = 52;
    _table.sectionHeaderHeight = 10;
    _table.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [self addSubview:_table];

    [self buildAccountHeader];
    _table.tableHeaderView = _accountHeader;

    [self rebuildSections];
}

- (void)rebuildSections {
    if (self.loggedIn) {
        self.sections = @[
            @[@"我的消息", @"我的云贝", @"徽章中心", @"装扮中心"],
            @[@"边听边存", @"音乐黑名单", @"青少年模式", @"音乐闹钟"],
            @[@"我的客服", @"我的订单", @"分享网易云音乐", @"关于"],
            @[@"手机专属邮箱", @"切换账号", @"退出登录"],
        ];
    } else {
        self.sections = @[
            @[@"我的消息", @"我的云贝", @"徽章中心", @"装扮中心"],
            @[@"边听边存", @"音乐黑名单", @"青少年模式", @"音乐闹钟"],
            @[@"我的客服", @"我的订单", @"分享网易云音乐", @"关于"],
        ];
    }
}

- (void)buildAccountHeader {
    _accountHeader = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 196)];

    _avatar = [[UIImageView alloc] initWithFrame:CGRectMake(18, 16, 56, 56)];
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

    // VIP 卡片（近似的黑胶会员卡）
    _vipCard = [[UIView alloc] initWithFrame:CGRectZero];
    _vipCard.backgroundColor = NEColor(0xF6D48A, 0.14);
    _vipCard.layer.cornerRadius = 12;
    _vipCard.layer.cornerCurve = kCACornerCurveContinuous;
    [_accountHeader addSubview:_vipCard];

    _vipTitle = [UILabel new];
    _vipTitle.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    _vipTitle.textColor = NEColor(0xF6D48A, 1.0);
    _vipTitle.text = @"黑胶 VIP";
    [_vipCard addSubview:_vipTitle];

    _vipDesc = [UILabel new];
    _vipDesc.font = [UIFont systemFontOfSize:11];
    _vipDesc.textColor = NEColor(0xF6D48A, 0.75);
    _vipDesc.text = @"尊享超 30 项黑胶 VIP 特权";
    [_vipCard addSubview:_vipDesc];

    _vipBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [_vipBtn setTitle:@"会员中心" forState:UIControlStateNormal];
    _vipBtn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [_vipBtn setTitleColor:NEColor(0x2A2113, 1.0) forState:UIControlStateNormal];
    _vipBtn.backgroundColor = NEColor(0xF6D48A, 1.0);
    _vipBtn.layer.cornerRadius = 13;
    _vipBtn.layer.cornerCurve = kCACornerCurveContinuous;
    [_vipBtn addTarget:self action:@selector(vipTapped) forControlEvents:UIControlEventTouchUpInside];
    [_vipCard addSubview:_vipBtn];

    _checkLabel = [UILabel new];
    _checkLabel.font = [UIFont systemFontOfSize:11];
    _checkLabel.textColor = NEColor(0xF6D48A, 0.65);
    _checkLabel.text = @"每日打卡，加速等级成长";
    [_vipCard addSubview:_checkLabel];
}

- (void)reloadData {
    self.loggedIn = [[NEApi shared] isLoggedIn];
    [self rebuildSections];
    [self updateHeader];
    [self.table reloadData];

    __weak typeof(self) weakSelf = self;
    [[NEApi shared] fetchProfile:^(NSDictionary *profile, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.profile = profile;
        self.loggedIn = (profile != nil) || [[NEApi shared] isLoggedIn];
        [self rebuildSections];
        [self updateHeader];
        [self.table reloadData];
    }];
}

- (void)updateHeader {
    if (!self.loggedIn) {
        _nameLabel.text = @"未登录";
        _uidLabel.text = @"登录后可同步账号信息";
        _vipTitle.text = @"未开通会员";
        _vipDesc.text = @"登录后可查看会员权益";
        _avatar.image = nil;
        return;
    }

    _nameLabel.text = self.profile[@"nickname"] ?: @"已登录";
    NSNumber *uid = self.profile[@"userId"];
    _uidLabel.text = uid ? [NSString stringWithFormat:@"ID：%@", uid] : @"";

    NSInteger vipType = [self.profile[@"vipType"] integerValue];
    if (vipType == 11) {
        _vipTitle.text = @"黑胶 VIP";
    } else if (vipType == 1) {
        _vipTitle.text = @"音乐包";
    } else {
        _vipTitle.text = @"普通用户";
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
        _accountHeader.frame = CGRectMake(0, 0, W, 196);
        _nameLabel.frame = CGRectMake(86, 22, W - 110, 22);
        _uidLabel.frame = CGRectMake(86, 48, W - 110, 16);

        _vipCard.frame = CGRectMake(14, 92, W - 28, 92);
        CGFloat cw = _vipCard.bounds.size.width;
        _vipTitle.frame = CGRectMake(14, 12, cw - 110, 20);
        _vipDesc.frame = CGRectMake(14, 34, cw - 110, 14);
        _vipBtn.frame = CGRectMake(cw - 88, 10, 76, 26);
        _checkLabel.frame = CGRectMake(14, 60, cw - 28, 16);
    }
}

#pragma mark - 交互

- (void)closeTapped {
    if ([self.delegate respondsToSelector:@selector(settingsPageDidClose:)]) {
        [self.delegate settingsPageDidClose:self];
    }
}

- (void)vipTapped {
    [self showAlertWithTitle:@"会员中心" message:@"会员中心暂未接入"];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
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
    UIViewController *host = [self topMostController];
    if (host) [host presentViewController:alert animated:YES completion:nil];
}

- (void)shareApp {
    NSString *text = [NSString stringWithFormat:@"%@ v%@（作者 %@）",
                      NE_APP_NAME, NE_APP_VERSION, NE_APP_AUTHOR];
    UIActivityViewController *vc = [[UIActivityViewController alloc]
        activityItems:@[text] applicationActivities:nil];
    UIViewController *host = [self topMostController];
    if (!host) return;
    vc.popoverPresentationController.sourceView = self;
    vc.popoverPresentationController.sourceRect = self.bounds;
    [host presentViewController:vc animated:YES completion:nil];
}

- (void)confirmLogoutWithSwitchAccount:(BOOL)switchAccount {
    NSString *title = switchAccount ? @"切换账号" : @"退出登录";
    NSString *message = switchAccount ? @"将退出当前账号并打开登录" : @"确定退出当前账号？";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (switchAccount) {
            if ([self.delegate respondsToSelector:@selector(settingsPageDidRequestSwitchAccount:)]) {
                [self.delegate settingsPageDidRequestSwitchAccount:self];
            }
        } else if ([self.delegate respondsToSelector:@selector(settingsPageDidLogout:)]) {
            [self.delegate settingsPageDidLogout:self];
        }
    }]];
    UIViewController *host = [self topMostController];
    if (host) [host presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 表

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.sections[(NSUInteger)section].count;
}

- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)section {
    return [UIView new];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"settings";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
        cell.backgroundColor = NE_CARD;
        cell.textLabel.textColor = NE_TEXT;
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UIView *sel = [UIView new];
        sel.backgroundColor = NE_PANEL;
        cell.selectedBackgroundView = sel;
    }

    NSString *title = self.sections[(NSUInteger)ip.section][(NSUInteger)ip.row];
    cell.textLabel.text = title;
    cell.textLabel.textColor = [title isEqualToString:@"退出登录"]
        ? [UIColor colorWithRed:1 green:0.35 blue:0.35 alpha:1]
        : NE_TEXT;
    return cell;
}

- (NESettingsAction)actionForIndexPath:(NSIndexPath *)ip {
    NSString *title = self.sections[(NSUInteger)ip.section][(NSUInteger)ip.row];
    if ([title isEqualToString:@"我的消息"]) return NESettingsActionMessages;
    if ([title isEqualToString:@"分享网易云音乐"]) return NESettingsActionShare;
    if ([title isEqualToString:@"关于"]) return NESettingsActionAbout;
    if ([title isEqualToString:@"切换账号"]) return NESettingsActionSwitchAccount;
    if ([title isEqualToString:@"退出登录"]) return NESettingsActionLogout;
    return NESettingsActionPlaceholder;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSString *title = self.sections[(NSUInteger)ip.section][(NSUInteger)ip.row];

    switch ([self actionForIndexPath:ip]) {
        case NESettingsActionMessages:
            [self showAlertWithTitle:@"我的消息" message:@"暂无新消息"];
            break;
        case NESettingsActionShare:
            [self shareApp];
            break;
        case NESettingsActionAbout:
            [self showAbout];
            break;
        case NESettingsActionSwitchAccount:
            [self confirmLogoutWithSwitchAccount:YES];
            break;
        case NESettingsActionLogout:
            [self confirmLogoutWithSwitchAccount:NO];
            break;
        default:
            [self showAlertWithTitle:title message:@"该功能暂未接入"];
            break;
    }
}

@end
