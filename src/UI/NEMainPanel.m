#import "NEMainPanel.h"
#import "NEUITheme.h"
#import "NEApi.h"
#import "NEPlayer.h"

typedef NS_ENUM(NSInteger, NEPanelTab) {
    NEPanelTabDiscover = 0,
    NEPanelTabSearch,
    NEPanelTabPlayer,
};

@interface NEMainPanel () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
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
@property (nonatomic, strong) UILabel *lyricLabel;

@property (nonatomic, strong) NSArray<NESong *> *songs;
@property (nonatomic, strong) NSArray<NSDictionary *> *lyricLines;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, copy) NSString *hint;

@end

@implementation NEMainPanel

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = NE_BG;
        self.tab = NEPanelTabDiscover;
        [self buildHeader];
        [self buildTable];
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
    if (![[NEApi shared] isLoggedIn]) {
        self.hint = @"未登录 · 点右上角登录";
        [self reload];
        [self loadDiscover];
        return;
    }
    [[NEApi shared] fetchAccount:^(NSString *nickname, NSString *avatar, NSError *error) {
        self.hint = nickname.length ? [NSString stringWithFormat:@"已登录：%@", nickname] : @"已登录";
        [self reload];
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

    NSArray *titles = @[@"发现", @"搜索", @"播放"];
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
    CGFloat playerH = 84;
    self.table.frame = CGRectMake(0, top, w, MAX(0, h - top - playerH));
    self.playerBar.frame = CGRectMake(0, h - playerH, w, playerH);
    [self layoutPlayerBar];
}

- (void)reload {
    if (self.tab == NEPanelTabPlayer) {
        [self refreshPlayerPage];
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

    _lyricLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _lyricLabel.font = [UIFont systemFontOfSize:13];
    _lyricLabel.textColor = NE_TEXT_DIM;
    _lyricLabel.numberOfLines = 2;
    _lyricLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_lyricLabel];
}

- (void)layoutPlayerBar {
    CGFloat w = self.bounds.size.width;
    _nowTitle.frame = CGRectMake(14, 10, w - 90, 18);
    _nowSub.frame = CGRectMake(14, 29, w - 90, 14);
    _playBtn.frame = CGRectMake(w - 58, 16, 44, 44);
    _progress.frame = CGRectMake(14, 50, w - 28, 20);
    _lyricLabel.frame = CGRectMake(16, 72, w - 32, 0);
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
    NESong *song = [NEPlayer shared].currentSong;
    if (!song) return;
    [[NEApi shared] fetchLyricForSong:song complete:^(NSArray<NSDictionary *> *lines, NSError *error) {
        self.lyricLines = lines;
    }];
}

- (void)refreshPlayerBar {
    NEPlayer *p = [NEPlayer shared];
    NESong *s = p.currentSong;
    self.nowTitle.text = s.name ?: @"未在播放";
    self.nowSub.text = s.artist ?: @"";
    [self.playBtn setTitle:(p.isPlaying ? @"❚❚" : @"▶︎") forState:UIControlStateNormal];
    self.progress.maximumValue = MAX(1.0, p.duration);
    if (!self.progress.isTracking) self.progress.value = p.currentTime;

    if (self.tab == NEPanelTabPlayer) [self refreshPlayerPage];
}

- (void)refreshPlayerPage {
    // 播放页：把当前歌词滚动到可见位置（简版）
    NEPlayer *p = [NEPlayer shared];
    if (!self.lyricLines.count || !p.isPlaying) return;
    double t = p.currentTime;
    NSString *line = nil;
    for (NSDictionary *d in self.lyricLines) {
        if ([d[@"t"] doubleValue] <= t + 0.2) line = d[@"text"]; else break;
    }
    self.lyricLabel.text = line ?: @"";
}

#pragma mark - 登录（二维码）

- (void)showLogin {
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
    [close addTarget:vc action:@selector(dismissModalViewControllerAnimated:) forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:close];

    [[NEApi shared] requestQRKey:^(NSString *unikey, NSError *error) {
        if (!unikey) { status.text = error.localizedDescription; return; }
        // 网易云二维码图片
        NSString *img = [NSString stringWithFormat:@"https://music.163.com/login?codekey=%@", unikey];
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            NSData *d = [NSData dataWithContentsOfURL:[NSURL URLWithString:img]];
            dispatch_async(dispatch_get_main_queue(), ^{
                qr.image = d ? [UIImage imageWithData:d] : nil;
                status.text = @"请用网易云 App 扫描上方二维码";
            });
        });
        [self pollLoginWith:unikey status:status];
    }];

    UIViewController *top = [self topMostViewController];
    [top presentViewController:vc animated:YES completion:nil];
}

- (void)pollLoginWith:(NSString *)unikey status:(UILabel *)status {
    [[NEApi shared] pollQRCode:unikey complete:^(NSInteger code, NSString *nickname, NSError *error) {
        if (error) { status.text = error.localizedDescription; return; }
        switch (code) {
            case 800: status.text = @"二维码已过期"; return;
            case 801: status.text = @"等待扫码…";   break;
            case 802: status.text = @"已扫码，请在手机上确认"; break;
            case 803:
                status.text = @"登录成功";
                [self loadAccountThenDiscover];
                return;
            default:  status.text = [NSString stringWithFormat:@"状态 %ld", (long)code]; break;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self pollLoginWith:unikey status:status]; });
    }];
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
