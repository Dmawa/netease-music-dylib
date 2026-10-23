#import "NEMainPanel.h"
#import "NEUITheme.h"
#import "NEApi.h"
#import "NEPlayer.h"
#import "NEQRCode.h"
#import "NEPlayerPage.h"
#import "NEProfilePage.h"

typedef NS_ENUM(NSInteger, NEPanelTab) {
    NEPanelTabDiscover = 0,   // 推荐/发现
    NEPanelTabProfile,        // 我的（收藏）
    NEPanelTabSearch,
    NEPanelTabPlayer,
};

@interface NEMainPanel () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, NEProfilePageDelegate>
@property (nonatomic, assign) NEPanelTab tab;
@property (nonatomic, strong) UIView *headerBar;
@property (nonatomic, strong) NSMutableArray<UIButton *> *tabButtons;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIView *playerBar;
@property (nonatomic, strong) UILabel *nowTitle;
@property (nonatomic, strong) UILabel *nowSub;
@property (nonatomic, strong) UIButton *playBtn;
@property (nonatomic, strong) UISlider *progress;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) NEPlayerPage *playerPage;
@property (nonatomic, strong) NEProfilePage *profilePage;
@property (nonatomic, strong) UIButton *loginButton;
/// 当前正在浏览的歌单（用于返回时显示标题）
@property (nonatomic, copy) NSString *currentPlaylistTitle;

@property (nonatomic, strong) NSArray<NESong *> *songs;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, copy) NSString *hint;
@property (nonatomic, strong, nullable) UIViewController *loginVC;

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
    }
    return self;
}

#pragma mark - 启动

- (void)start {
    [self loadAccountThenDiscover];
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
        [self.loginButton setTitle:(loggedIn ? @"已登录" : @"登录")
                           forState:UIControlStateNormal];
        self.loginButton.alpha = loggedIn ? 0.5 : 1.0;
        [self reload];
        [self.profilePage reloadData];
    }];
    [self loadDiscover];
}

- (void)loadDiscover {
    if (self.loading) return;
    self.loading = YES;
    [self reload];
    [[NEApi shared] fetchToplist:^(NSArray<NESong *> *songs, NSError *error) {
        self.loading = NO;
        if (error) { self.hint = error.localizedDescription; [self reload]; return; }
        self.songs = songs;
        [self reload];
    }];
}

#pragma mark - 头部

- (void)buildHeader {
    _headerBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.bounds.size.width, 52)];
    _headerBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self addSubview:_headerBar];

    NSArray *titles = @[@"发现", @"我的", @"搜索", @"播放"];
    _tabButtons = [NSMutableArray array];
    CGFloat x = 12;
    for (NSInteger i = 0; i < titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.tag = i;
        [b setTitle:titles[i] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        CGSize fit = [b sizeThatFits:CGSizeMake(200, 30)];
        b.frame = CGRectMake(x, 12, fit.width + 18, 28);
        b.layer.cornerRadius = 14;
        b.layer.cornerCurve = kCACornerCurveContinuous;
        [b addTarget:self action:@selector(switchTab:) forControlEvents:UIControlEventTouchUpInside];
        [_headerBar addSubview:b];
        [_tabButtons addObject:b];
        x += b.frame.size.width + 8;
    }

    UIButton *login = [UIButton buttonWithType:UIButtonTypeCustom];
    self.loginButton = login;
    [login setTitle:@"登录" forState:UIControlStateNormal];
    login.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    login.backgroundColor = NE_BRAND;
    login.layer.cornerRadius = 14;
    login.layer.cornerCurve = kCACornerCurveContinuous;
    login.frame = CGRectMake(self.bounds.size.width - 76, 12, 64, 28);
    login.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [login addTarget:self action:@selector(showLogin) forControlEvents:UIControlEventTouchUpInside];
    [_headerBar addSubview:login];

    [self highlightTab];
}

- (void)switchTab:(UIButton *)sender {
    self.tab = (NEPanelTab)sender.tag;
    [self highlightTab];
    self.searchBar.hidden = (self.tab != NEPanelTabSearch);
    [self reload];
}

- (void)highlightTab {
    for (UIButton *b in self.tabButtons) {
        BOOL on = (b.tag == self.tab);
        b.backgroundColor = on ? NE_CARD : UIColor.clearColor;
        [b setTitleColor:(on ? NE_TEXT : NE_TEXT_DIM) forState:UIControlStateNormal];
    }
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

    _searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
    _searchBar.placeholder = @"搜索歌曲 / 歌手";
    _searchBar.delegate = self;
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.tintColor = NE_BRAND;
    _searchBar.hidden = YES;
    [self addSubview:_searchBar];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    self.headerBar.frame = CGRectMake(0, 0, w, 52);

    CGFloat top = 52;
    if (!self.searchBar.hidden) {
        self.searchBar.frame = CGRectMake(8, top, w - 16, 44);
        top += 44;
    }
    CGFloat playerH = 64;
    CGRect content = CGRectMake(0, top, w, MAX(0, h - top - playerH));
    self.table.frame = content;
    self.playerPage.frame = content;
    self.profilePage.frame = content;
    self.playerBar.frame = CGRectMake(0, h - playerH, w, playerH);
    [self layoutPlayerBar];
}

- (void)reload {
    BOOL isPlayer  = (self.tab == NEPanelTabPlayer);
    BOOL isProfile = (self.tab == NEPanelTabProfile);
    BOOL isSearch  = (self.tab == NEPanelTabSearch);

    self.playerPage.hidden  = !isPlayer;
    self.profilePage.hidden = !isProfile;
    self.table.hidden = (isPlayer || isProfile);
    self.searchBar.hidden = !isSearch;

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

#pragma mark - NEProfilePageDelegate

- (void)profilePage:(id)page didSelectPlaylist:(NEPlaylist *)playlist {
    if (!playlist.playlistID.length) return;
    self.currentPlaylistTitle = playlist.name;
    // 切回列表视图展示该歌单曲目
    self.tab = NEPanelTabDiscover;
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
    [bar resignFirstResponder];
    NSString *kw = bar.text;
    if (!kw.length) return;
    self.loading = YES;
    [self reload];
    [[NEApi shared] searchSongs:kw limit:30 complete:^(NSArray<NESong *> *songs, NSError *error) {
        self.loading = NO;
        if (error) { self.hint = error.localizedDescription; self.songs = @[]; [self reload]; return; }
        self.songs = songs;
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
    vc.view.backgroundColor = NE_BG;

    UILabel *tip = [[UILabel alloc] initWithFrame:CGRectMake(20, 30, 280, 22)];
    tip.text = @"网易云音乐扫码登录";
    tip.textColor = NE_TEXT;
    tip.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [vc.view addSubview:tip];

    UIImageView *qr = [[UIImageView alloc] initWithFrame:CGRectMake(90, 70, 180, 180)];
    qr.backgroundColor = UIColor.whiteColor;
    qr.contentMode = UIViewContentModeScaleAspectFit;
    [vc.view addSubview:qr];

    UILabel *status = [[UILabel alloc] initWithFrame:CGRectMake(20, 262, 280, 60)];
    status.numberOfLines = 0;
    status.textAlignment = NSTextAlignmentCenter;
    status.textColor = NE_TEXT_DIM;
    status.font = [UIFont systemFontOfSize:12];
    status.text = @"正在获取二维码…";
    [vc.view addSubview:status];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(20, 330, 280, 40);
    [close setTitle:@"关闭" forState:UIControlStateNormal];
    [close addTarget:self action:@selector(closeLoginVC) forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:close];
    self.loginVC = vc;

    [[NEApi shared] requestQRKey:^(NSString *unikey, NSError *error) {
        if (!unikey) { status.text = error.localizedDescription; return; }
        // 二维码由本地生成：网易云没有可直连的图片接口，
        // 服务端页面是靠前端 JS 画出来的，所以这里用自带编码器绘制
        NSString *content = [NSString stringWithFormat:
            @"https://music.163.com/login?codekey=%@", unikey];
        UIImage *img = [NEQRCode imageWithText:content size:180];
        qr.image = img;
        status.text = img ? @"请用网易云 App 扫描上方二维码" : @"二维码生成失败";
        [self pollLoginWith:unikey status:status];
    }];

    UIViewController *top = [self topMostViewController];
    [top presentViewController:vc animated:YES completion:nil];
}

- (void)pollLoginWith:(NSString *)unikey status:(UILabel *)status {
    // 登录页已被关闭就停止轮询，避免后台无限请求
    if (!self.loginVC) return;
    [[NEApi shared] pollQRCode:unikey complete:^(NSInteger code, NSString *nickname, NSError *error) {
        if (!self.loginVC) return;
        if (error) { status.text = error.localizedDescription; return; }
        switch (code) {
            case 800: status.text = @"二维码已过期"; return;
            case 801: status.text = @"等待扫码…";   break;
            case 802: status.text = @"已扫码，请在手机上确认"; break;
            case 803: {
                // 关键：803 之后服务端会下发 MUSIC_U，需要确认已经拿到并落盘，
                // 否则「登录成功」只是假象，重启就掉登录。
                if (![[NEApi shared] isLoggedIn]) {
                    status.text = @"登录成功，但未取到登录凭证，正在重试…";
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), ^{
                        [self pollLoginWith:unikey status:status];
                    });
                    return;
                }
                status.text = @"登录成功";
                [self loadAccountThenDiscover];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{ [self closeLoginVC]; });
                return;
            }
            default:  status.text = [NSString stringWithFormat:@"状态 %ld", (long)code]; break;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self pollLoginWith:unikey status:status]; });
    }];
}

- (void)closeLoginVC {
    UIViewController *vc = self.loginVC;
    self.loginVC = nil;
    [vc dismissViewControllerAnimated:YES completion:nil];
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
