#import "NEMainPanel.h"
#import "NEUITheme.h"
#import "NEApi.h"
#import "NEPlayer.h"
#import "NEQRCode.h"
#import "NEPlayerPage.h"
#import "NEProfilePage.h"
#import "NEDiscoverPage.h"
#import "NESidebar.h"
#import "NELoginView.h"
#import "NESettingsPage.h"

typedef NS_ENUM(NSInteger, NEPanelTab) {
    NEPanelTabDiscover = 0,   // 推荐/发现（也是搜索结果页）
    NEPanelTabProfile,        // 我的（收藏）
    NEPanelTabPlayer,         // 正在播放
};

@interface NEMainPanel () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, NEProfilePageDelegate, NEDiscoverPageDelegate, NESidebarDelegate, NELoginViewDelegate, NESettingsPageDelegate>
@property (nonatomic, assign) NEPanelTab tab;
@property (nonatomic, strong) UIView *headerBar;
@property (nonatomic, strong) NESidebar *sidebar;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UISearchBar *topSearch;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIView *playerBar;
@property (nonatomic, strong) UILabel *nowTitle;
@property (nonatomic, strong) UILabel *nowSub;
@property (nonatomic, strong) UIButton *playBtn;
@property (nonatomic, strong) UISlider *progress;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) NEPlayerPage *playerPage;
@property (nonatomic, strong) NEProfilePage *profilePage;
@property (nonatomic, strong) NEDiscoverPage *discoverPage;
@property (nonatomic, strong) UIButton *loginButton;
/// 当前正在浏览的歌单（用于返回时显示标题）
@property (nonatomic, copy) NSString *currentPlaylistTitle;

@property (nonatomic, strong) NSArray<NESong *> *songs;
/// 列表模式：搜索结果 / 歌单曲目用 table 展示；否则「发现」页展示推荐内容
@property (nonatomic, assign) BOOL browsingList;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, copy) NSString *hint;
@property (nonatomic, strong, nullable) NELoginView *loginView;
@property (nonatomic, strong) NESettingsPage *settingsPage;

@end

@implementation NEMainPanel

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = NE_BG;
        self.tab = NEPanelTabDiscover;
        [self buildHeader];
        [self buildTable];
        [self buildPlayerPage];
        [self buildPlayerBar];
        [self observePlayer];
        [self buildSettingsPage];      // 最后加，保证盖在所有内容之上
    }
    return self;
}

#pragma mark - 启动

- (void)start {
    [self loadAccountThenDiscover];
    [self refreshPlayerBar];           // 显示上次退出时的歌曲（NEPlayer 会恢复）
}

- (void)loadAccountThenDiscover {
    // 每次进入都先向服务端确认登录态，保证重启后能自动恢复
    __weak typeof(self) weakSelf = self;
    [[NEApi shared] restoreSession:^(BOOL loggedIn, NSString *nickname, NSString *avatar) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (loggedIn) {
            self.hint = nickname.length ? [NSString stringWithFormat:@"已登录：%@", nickname] : @"已登录";
        } else {
            self.hint = @"未登录 · 点右上角登录";
        }
        // 登录后按钮自动隐藏（像网易云：已登录就不再显示登录入口）
        self.loginButton.hidden = loggedIn;
        [self.loginButton setTitle:@"登录" forState:UIControlStateNormal];
        [self reload];
        [self.profilePage reloadData];
    }];
    [self loadDiscover];
}

- (void)loadDiscover {
    // 推荐内容由 NEDiscoverPage 自己拉取，这里只负责把视图切回发现页。
    // （以前这里往 table 塞热歌榜，导致发现页永远被列表挡住。）
    self.browsingList = NO;
    [self reload];
}

#pragma mark - 头部

- (void)buildHeader {
    // ---------- 左侧竖排导航 ----------
    _sidebar = [[NESidebar alloc] initWithFrame:CGRectZero];
    _sidebar.delegate = self;

    NESidebarItem *i0 = [NESidebarItem new];
    i0.title = @"发现"; i0.iconName = @"safari"; i0.iconNameSelected = @"safari.fill"; i0.tag = 0;
    NESidebarItem *i1 = [NESidebarItem new];
    i1.title = @"我的"; i1.iconName = @"person"; i1.iconNameSelected = @"person.fill"; i1.tag = 1;
    NESidebarItem *i2 = [NESidebarItem new];
    i2.title = @"播放"; i2.iconName = @"play.circle"; i2.iconNameSelected = @"play.circle.fill"; i2.tag = 2;
    _sidebar.items = @[i0, i1, i2];
    _sidebar.selectedIndex = 0;
    [self addSubview:_sidebar];

    // ---------- 顶栏：搜索框 + 登录 ----------
    _topBar = [[UIView alloc] initWithFrame:CGRectZero];
    [self addSubview:_topBar];

    _topSearch = [[UISearchBar alloc] initWithFrame:CGRectZero];
    _topSearch.placeholder = @"搜索歌曲 / 歌手 / 歌单";
    _topSearch.delegate = self;
    _topSearch.searchBarStyle = UISearchBarStyleMinimal;
    _topSearch.tintColor = NE_BRAND;
    _topSearch.backgroundImage = [UIImage new];            // 去掉默认边框
    UITextField *tf = [_topSearch valueForKey:@"searchField"];
    if ([tf isKindOfClass:[UITextField class]]) {
        tf.backgroundColor = NE_CARD;
        tf.layer.cornerRadius = 16;
        tf.layer.cornerCurve = kCACornerCurveContinuous;
        tf.textColor = NE_TEXT;
        tf.attributedPlaceholder = [[NSAttributedString alloc]
            initWithString:@"搜索歌曲 / 歌手 / 歌单"
                attributes:@{NSForegroundColorAttributeName: NE_TEXT_DIM}];
    }
    [_topBar addSubview:_topSearch];

    UIButton *login = [UIButton buttonWithType:UIButtonTypeCustom];
    self.loginButton = login;
    [login setTitle:@"登录" forState:UIControlStateNormal];
    login.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    login.backgroundColor = NE_BRAND;
    login.layer.cornerRadius = 15;
    login.layer.cornerCurve = kCACornerCurveContinuous;
    [login addTarget:self action:@selector(showLogin) forControlEvents:UIControlEventTouchUpInside];
    [_topBar addSubview:login];

    [self highlightTab];
}

- (void)sidebar:(id)sidebar didSelectIndex:(NSInteger)index {
    self.settingsPage.hidden = YES;      // 切 tab 时关掉设置页
    self.tab = (NEPanelTab)index;
    if (self.tab == NEPanelTabDiscover) self.browsingList = NO;
    [self highlightTab];
    [self reload];
}

- (void)highlightTab {
    self.sidebar.selectedIndex = self.tab;
    self.topSearch.hidden = (self.tab == NEPanelTabPlayer);
}

#pragma mark - 列表

- (void)buildTable {
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.backgroundColor = UIColor.clearColor;
    _table.separatorColor = NE_STROKE;
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = 58;
    _table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self addSubview:_table];

}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width;
    CGFloat H = self.bounds.size.height;

    // 侧边栏宽度：宽屏 76，窄屏 60
    BOOL compact = (W < 620);
    CGFloat sideW = compact ? 60 : 76;
    if (fabs(self.sidebar.bounds.size.width - sideW) > 0.5) {
        self.sidebar.compact = compact;
    }
    self.sidebar.frame = CGRectMake(0, 44, sideW, H - 44);

    CGFloat contentX = sideW;
    CGFloat contentW = W - sideW;

    // 顶栏
    self.topBar.frame = CGRectMake(contentX, 8, contentW, 44);
    CGFloat loginW = 62, gap = 10;
    self.loginButton.frame = CGRectMake(contentW - loginW - 12, 8, loginW, 30);
    self.topSearch.frame = CGRectMake(8, 2, contentW - loginW - gap - 16, 40);

    CGFloat top = 58;
    CGFloat playerH = 64;
    CGRect content = CGRectMake(contentX, top, contentW, MAX(0, H - top - playerH));

    self.table.frame = content;
    self.playerPage.frame = content;
    self.profilePage.frame = content;
    self.discoverPage.frame = content;

    self.playerBar.frame = CGRectMake(0, H - playerH, W, playerH);
    self.settingsPage.frame = self.bounds;      // 设置页覆盖整个面板
    [self layoutPlayerBar];
}

- (void)reload {
    BOOL isPlayer   = (self.tab == NEPanelTabPlayer);
    BOOL isProfile  = (self.tab == NEPanelTabProfile);
    BOOL isDiscover = (self.tab == NEPanelTabDiscover);

    // 搜索结果 / 歌单曲目 用 table 展示时，必须把发现页藏起来，
    // 否则两个视图会重叠；没进列表模式时发现页必须可见。
    BOOL showTable = (isDiscover && self.browsingList);

    self.playerPage.hidden   = !isPlayer;
    self.profilePage.hidden  = !isProfile;
    self.discoverPage.hidden = (!isDiscover || showTable);
    self.table.hidden        = !showTable;

    if (isDiscover && !showTable) {
        [self.discoverPage reloadData];
        return;
    }

    if (isPlayer) {
        [self.playerPage refresh];
        return;
    }
    if (isProfile) {
        [self.profilePage reloadData];
        return;
    }
    [self setNeedsLayout];
    [self.table reloadData];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (self.loading) return 1;
    if (!self.songs.count) return 1;
    return self.songs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"song";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
        cell.backgroundColor = UIColor.clearColor;
        cell.textLabel.textColor = NE_TEXT;
        cell.detailTextLabel.textColor = NE_TEXT_DIM;
        cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UIView *sel = [UIView new];
        sel.backgroundColor = NE_CARD;
        cell.selectedBackgroundView = sel;
    }

    if (self.loading) {
        cell.textLabel.text = @"加载中…";
        cell.detailTextLabel.text = @"";
        return cell;
    }
    if (!self.songs.count) {
        cell.textLabel.text = @"暂无内容";
        cell.detailTextLabel.text = self.hint ?: @"";
        return cell;
    }

    NESong *s = self.songs[ip.row];
    cell.textLabel.text = s.name;
    NSString *sub = s.artist;
    if (s.vipOnly) sub = [sub stringByAppendingString:@"   VIP"];
    cell.detailTextLabel.text = sub;
    cell.textLabel.textColor = [s.songID isEqualToString:[NEPlayer shared].currentSong.songID]
        ? NE_BRAND : NE_TEXT;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (self.loading || ip.row >= (NSInteger)self.songs.count) return;
    [[NEPlayer shared] playQueue:self.songs atIndex:ip.row];
    self.tab = NEPanelTabPlayer;
    [self highlightTab];
    [self reload];
}

#pragma mark - NEDiscoverPageDelegate

- (void)discoverPage:(id)page didOpenPlaylistID:(NSString *)playlistID title:(NSString *)title {
    if (!playlistID.length) return;
    self.currentPlaylistTitle = title;
    self.browsingList = YES;
    self.loading = YES;
    [self reload];

    __weak typeof(self) weakSelf = self;
    [[NEApi shared] fetchPlaylistSongs:playlistID complete:^(NSArray<NESong *> *songs, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.loading = NO;
        self.songs = error ? @[] : songs;
        self.hint = error ? error.localizedDescription
                          : [NSString stringWithFormat:@"%@ · %lu 首", title ?: @"", (unsigned long)songs.count];
        [self reload];
    }];
}

- (void)discoverPage:(id)page didPlaySong:(NESong *)song {
    if (!song) return;
    [[NEPlayer shared] playQueue:@[song] atIndex:0];
    self.tab = NEPanelTabPlayer;
    [self highlightTab];
    [self reload];
}

- (void)discoverPage:(id)page didLoadSongs:(NSArray<NESong *> *)songs title:(NSString *)title {
    if (!songs.count) return;
    self.currentPlaylistTitle = title;
    self.songs = songs;
    self.browsingList = YES;
    self.loading = NO;
    self.hint = [NSString stringWithFormat:@"%@ · %lu 首", title ?: @"", (unsigned long)songs.count];
    self.tab = NEPanelTabDiscover;
    [self highlightTab];
    [self reload];
}

#pragma mark - NEProfilePageDelegate

- (void)profilePage:(id)page didSelectPlaylist:(NEPlaylist *)playlist {
    if (!playlist.playlistID.length) return;
    self.currentPlaylistTitle = playlist.name;
    // 切回列表视图展示该歌单曲目
    self.tab = NEPanelTabDiscover;
    self.browsingList = YES;
    [self highlightTab];
    self.loading = YES;
    [self reload];

    __weak typeof(self) weakSelf = self;
    [[NEApi shared] fetchPlaylistSongs:playlist.playlistID complete:^(NSArray<NESong *> *songs, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.loading = NO;
        if (error) {
            self.hint = error.localizedDescription;
            self.songs = @[];
        } else {
            self.songs = songs;
            self.hint = [NSString stringWithFormat:@"%@ · %lu 首",
                         playlist.name ?: @"歌单", (unsigned long)songs.count];
        }
        [self reload];
    }];
}

#pragma mark - 搜索

- (void)searchBarSearchButtonClicked:(UISearchBar *)bar {
    if (bar != self.topSearch) return;
    [bar resignFirstResponder];

    NSString *kw = [bar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!kw.length) {
        self.songs = @[];
        self.currentPlaylistTitle = nil;
        self.hint = @"";
        self.tab = NEPanelTabDiscover;
        self.browsingList = NO;
        [self highlightTab];
        [self reload];
        return;
    }

    // search merged into the top search bar
    self.tab = NEPanelTabDiscover;
    self.browsingList = YES;
    [self highlightTab];
    self.currentPlaylistTitle = [NSString stringWithFormat:@"搜索：%@", kw];
    self.songs = @[];
    self.loading = YES;
    [self reload];

    __weak typeof(self) weakSelf = self;
    [[NEApi shared] searchSongs:kw limit:50 complete:^(NSArray<NESong *> *songs, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.loading = NO;
        if (error) {
            self.songs = @[];
            self.hint = error.localizedDescription;
        } else {
            self.songs = songs;
            self.hint = songs.count
                ? [NSString stringWithFormat:@"“%@” \u00b7 %lu 个结果", kw, (unsigned long)songs.count]
                : [NSString stringWithFormat:@"没有找到“%@”", kw];
        }
        [self reload];
    }];
}

#pragma mark - 播放页

- (void)buildPlayerPage {
    _playerPage = [[NEPlayerPage alloc] initWithFrame:CGRectZero];
    _playerPage.hidden = YES;
    [self addSubview:_playerPage];

    _profilePage = [[NEProfilePage alloc] initWithFrame:CGRectZero];
    _profilePage.hidden = YES;
    _profilePage.delegate = self;
    [self addSubview:_profilePage];

    _discoverPage = [[NEDiscoverPage alloc] initWithFrame:CGRectZero];
    _discoverPage.hidden = YES;
    _discoverPage.delegate = self;
    [self addSubview:_discoverPage];
}

#pragma mark - 设置页

- (void)buildSettingsPage {
    _settingsPage = [[NESettingsPage alloc] initWithFrame:CGRectZero];
    _settingsPage.hidden = YES;
    _settingsPage.delegate = self;
    [self addSubview:_settingsPage];
}

- (void)profilePageDidTapSettings:(id)page {
    self.settingsPage.hidden = NO;
    [self.settingsPage reloadData];
}

- (void)settingsPageDidClose:(id)page {
    self.settingsPage.hidden = YES;
}

- (void)settingsPageDidLogout:(id)page {
    [[NEApi shared] logout];
    self.settingsPage.hidden = YES;
    [self loadAccountThenDiscover];
    [self.profilePage reloadData];
}

- (void)settingsPageDidRequestSwitchAccount:(id)page {
    [[NEApi shared] logout];
    self.settingsPage.hidden = YES;
    [self loadAccountThenDiscover];
    [self.profilePage reloadData];
    // 登出后直接弹登录（扫码 / 其他登录方式）
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self) [self showLogin];
    });
}

#pragma mark - 播放条

- (void)buildPlayerBar {
    _playerBar = [[UIView alloc] initWithFrame:CGRectZero];
    _playerBar.backgroundColor = NE_PANEL;
    _playerBar.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    _playerBar.layer.borderColor = NE_STROKE.CGColor;
    [self addSubview:_playerBar];

    _nowTitle = [[UILabel alloc] initWithFrame:CGRectZero];
    _nowTitle.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _nowTitle.textColor = NE_TEXT;
    _nowTitle.text = @"未在播放";
    [_playerBar addSubview:_nowTitle];

    _nowSub = [[UILabel alloc] initWithFrame:CGRectZero];
    _nowSub.font = [UIFont systemFontOfSize:11];
    _nowSub.textColor = NE_TEXT_DIM;
    [_playerBar addSubview:_nowSub];

    _playBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [_playBtn setTitle:@"▶︎" forState:UIControlStateNormal];
    [_playBtn setTitleColor:NE_TEXT forState:UIControlStateNormal];
    _playBtn.titleLabel.font = [UIFont systemFontOfSize:18];
    [_playBtn addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [_playerBar addSubview:_playBtn];

    _progress = [[UISlider alloc] initWithFrame:CGRectZero];
    _progress.minimumTrackTintColor = NE_BRAND;
    _progress.maximumTrackTintColor = NE_CARD;
    [_progress addTarget:self action:@selector(seekEnd) forControlEvents:UIControlEventTouchUpInside];
    [_playerBar addSubview:_progress];

}

- (void)layoutPlayerBar {
    CGFloat w = self.bounds.size.width;
    _nowTitle.frame = CGRectMake(14, 10, w - 90, 18);
    _nowSub.frame = CGRectMake(14, 30, w - 90, 14);
    _playBtn.frame = CGRectMake(w - 56, 12, 44, 44);
    // 细进度条贴在播放条顶部
    _progress.frame = CGRectMake(0, 0, w, 2);
}

- (void)toggle { [[NEPlayer shared] togglePlayPause]; }

- (void)seekEnd {
    [[NEPlayer shared] seekTo:self.progress.value];
}

- (void)observePlayer {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(playerChanged:) name:NEPlayerStateChangedNotification object:nil];
    [nc addObserver:self selector:@selector(trackChanged:) name:NEPlayerTrackChangedNotification object:nil];
}

- (void)playerChanged:(NSNotification *)note { [self refreshPlayerBar]; }

- (void)trackChanged:(NSNotification *)note {
    [self refreshPlayerBar];
    [self.playerPage refresh];
}

- (void)refreshPlayerBar {
    NEPlayer *p = [NEPlayer shared];
    NESong *s = p.currentSong;
    self.nowTitle.text = s.name ?: @"未在播放";
    self.nowSub.text = s.artist ?: @"";
    [self.playBtn setTitle:(p.isPlaying ? @"❚❚" : @"▶︎") forState:UIControlStateNormal];
    self.progress.maximumValue = MAX(1.0, p.duration);
    if (!self.progress.isTracking) self.progress.value = p.currentTime;

}


#pragma mark - 登录（二维码）

- (void)showLogin {
    // 已登录：给退出入口
    if ([[NEApi shared] isLoggedIn]) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已登录"
            message:@"是否退出当前账号？" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"退出登录" style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction *x) {
            [[NEApi shared] logout];
            [self loadAccountThenDiscover];
        }]];
        [[self topMostViewController] presentViewController:a animated:YES completion:nil];
        return;
    }

    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    vc.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;

    NELoginView *login = [[NELoginView alloc] initWithFrame:CGRectZero];
    login.delegate = self;
    login.hostController = vc;        // Cookie 兜底登录需要它来弹窗
    [vc.view addSubview:login];
    self.loginView = login;

    // 居中卡片，宽高自适应
    CGFloat maxW = 360, maxH = 520;
    CGSize screen = vc.view.bounds.size;
    CGFloat w = MIN(maxW, screen.width - 60);
    CGFloat h = MIN(maxH, screen.height - 120);
    login.frame = CGRectMake((screen.width - w) / 2, (screen.height - h) / 2, w, h);
    login.autoresizingMask = UIViewAutoresizingFlexibleTopMargin |
                             UIViewAutoresizingFlexibleBottomMargin |
                             UIViewAutoresizingFlexibleLeftMargin |
                             UIViewAutoresizingFlexibleRightMargin;

    [[self topMostViewController] presentViewController:vc animated:YES completion:^{
        [login start];
    }];
}

#pragma mark - NELoginViewDelegate

- (void)loginViewDidLogin:(id)view nickname:(NSString *)nickname {
    [self dismissLoginAnimated];
    [self loadAccountThenDiscover];
    [self.profilePage reloadData];
}

- (void)loginViewDidCancel:(id)view {
    [self dismissLoginAnimated];
}

- (void)dismissLoginAnimated {
    [self.loginView stop];
    UIViewController *vc = [self topMostViewController];
    if (vc.presentingViewController) {
        [vc dismissViewControllerAnimated:YES completion:nil];
    }
    self.loginView = nil;
}

#pragma mark - 找到当前最顶层 VC（iOS13 起 keyWindow 不可靠）

- (UIViewController *)topMostViewController {
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { window = w; break; }
            }
            if (window) break;
        }
    }
    if (!window) window = [UIApplication sharedApplication].windows.firstObject;

    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

@end
