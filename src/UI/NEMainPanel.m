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
#import "NEFeedPage.h"
#import "NEImageCache.h"

typedef NS_ENUM(NSInteger, NEPanelTab) {
    NEPanelTabRecommend = 0,  // 推荐（每日推荐/漫游/心动入口 + 搜索结果/歌单）
    NEPanelTabDiscover,       // 发现（排行榜）
    NEPanelTabRoam,           // 漫游（随机推荐）
    NEPanelTabPodcast,        // 播客
    NEPanelTabNotes,          // 笔记
    NEPanelTabProfile,        // 我的（放在最后）
    NEPanelTabPlayer,         // 正在播放（无侧边栏项，点底部播放条进入）
};

/// 带封面的内容行：歌曲 / 歌单 / 榜单通用
@interface NEContentCell : UITableViewCell
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subLabel;
- (void)configureTitle:(NSString *)title sub:(NSString *)sub cover:(NSString *)coverURL;
@end

@implementation NEContentCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuse {
    if ((self = [super initWithStyle:style reuseIdentifier:reuse])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        UIView *sel = [UIView new];
        sel.backgroundColor = NE_CARD;
        self.selectedBackgroundView = sel;

        _cover = [[UIImageView alloc] initWithFrame:CGRectZero];
        _cover.contentMode = UIViewContentModeScaleAspectFill;
        _cover.clipsToBounds = YES;
        _cover.layer.cornerRadius = 6;
        _cover.layer.cornerCurve = kCACornerCurveContinuous;
        _cover.backgroundColor = NE_CARD;
        [self.contentView addSubview:_cover];

        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        _titleLabel.textColor = NE_TEXT;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_titleLabel];

        _subLabel = [UILabel new];
        _subLabel.font = [UIFont systemFontOfSize:12];
        _subLabel.textColor = NE_TEXT_DIM;
        _subLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_subLabel];
    }
    return self;
}

- (void)configureTitle:(NSString *)title sub:(NSString *)sub cover:(NSString *)coverURL {
    _titleLabel.text = [title isKindOfClass:[NSString class]] ? title : @"";
    _subLabel.text = [sub isKindOfClass:[NSString class]] ? sub : @"";
    _cover.image = nil;
    if ([coverURL isKindOfClass:[NSString class]] && coverURL.length) {
        __weak typeof(self) weakSelf = self;
        [[NEImageCache shared] loadImageWithURL:coverURL completion:^(UIImage *image) {
            if (image) weakSelf.cover.image = image;
        }];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.contentView.bounds.size.height;
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat s = MIN(46, h - 12);
    _cover.frame = CGRectMake(14, (h - s) / 2, s, s);
    CGFloat x = CGRectGetMaxX(_cover.frame) + 12;
    _titleLabel.frame = CGRectMake(x, (h - 34) / 2, w - x - 16, 18);
    _subLabel.frame = CGRectMake(x, CGRectGetMaxY(_titleLabel.frame) + 1, w - x - 16, 15);
}

@end

@interface NEMainPanel () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, NEProfilePageDelegate, NEDiscoverPageDelegate, NESidebarDelegate, NELoginViewDelegate, NESettingsPageDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, assign) NEPanelTab tab;
@property (nonatomic, strong) UIView *headerBar;
@property (nonatomic, strong) NESidebar *sidebar;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UISearchBar *topSearch;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIView *playerBar;
@property (nonatomic, strong) UILabel *nowTitle;
@property (nonatomic, strong) UILabel *nowSub;
@property (nonatomic, strong) UIImageView *barCover;
@property (nonatomic, copy) NSString *barCoverURL;
@property (nonatomic, strong) UIButton *playBtn;
@property (nonatomic, strong) UISlider *progress;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) NEPlayerPage *playerPage;
@property (nonatomic, strong) NEProfilePage *profilePage;
@property (nonatomic, strong) NEDiscoverPage *discoverPage;
@property (nonatomic, strong) NEFeedPage *podcastPage;
@property (nonatomic, strong) NEFeedPage *notesPage;
@property (nonatomic, strong) UIButton *loginButton;
/// 当前正在浏览的歌单（用于返回时显示标题）
@property (nonatomic, copy) NSString *currentPlaylistTitle;

@property (nonatomic, strong) NSArray<NESong *> *songs;
/// 发现页（排行榜）
@property (nonatomic, strong) NSArray<NERecommendItem *> *toplists;
/// 漫游页（随机推荐）
@property (nonatomic, strong) NSArray<NESong *> *roamSongs;
/// 列表模式：搜索结果 / 歌单曲目用 table 展示；否则「推荐」页展示推荐内容
@property (nonatomic, assign) BOOL browsingList;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, copy) NSString *hint;
@property (nonatomic, strong, nullable) NELoginView *loginView;
@property (nonatomic, strong) NESettingsPage *settingsPage;
/// 从哪个 tab 进入播放页（收起时返回）
@property (nonatomic, assign) NSInteger previousTab;

@end

@implementation NEMainPanel

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = NE_BG;
        self.tab = NEPanelTabRecommend;
        [self buildHeader];
        [self buildTable];
        [self buildPlayerPage];
        [self buildPlayerBar];
        [self observePlayer];
        [self observeTheme];
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

    // 按网易云版式：推荐 → 发现 → 漫游 → 播放 → 我的（我的放最后）
    NESidebarItem *i0 = [NESidebarItem new];
    i0.title = @"推荐"; i0.iconName = @"sparkles"; i0.iconNameSelected = @"sparkles"; i0.tag = 0;
    NESidebarItem *i1 = [NESidebarItem new];
    i1.title = @"发现"; i1.iconName = @"safari"; i1.iconNameSelected = @"safari.fill"; i1.tag = 1;
    NESidebarItem *i2 = [NESidebarItem new];
    i2.title = @"漫游"; i2.iconName = @"infinity"; i2.iconNameSelected = @"infinity"; i2.tag = 2;
    NESidebarItem *i3 = [NESidebarItem new];
    i3.title = @"播客"; i3.iconName = @"mic"; i3.iconNameSelected = @"mic.fill"; i3.tag = 3;
    NESidebarItem *i4 = [NESidebarItem new];
    i4.title = @"笔记"; i4.iconName = @"note.text"; i4.iconNameSelected = @"note.text"; i4.tag = 4;
    NESidebarItem *i5 = [NESidebarItem new];
    i5.title = @"我的"; i5.iconName = @"person"; i5.iconNameSelected = @"person.fill"; i5.tag = 5;
    _sidebar.items = @[i0, i1, i2, i3, i4, i5];
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
    [self hideSettingsImmediately];      // 切 tab 时关掉设置页
    if (self.tab == NEPanelTabPlayer) [self setNeedsLayout];
    self.tab = (NEPanelTab)index;
    if (self.tab == NEPanelTabRecommend) self.browsingList = NO;
    if (self.tab == NEPanelTabDiscover) [self loadToplistsIfNeeded];
    if (self.tab == NEPanelTabRoam) [self loadRoamIfNeeded];
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

    // 播放页沉浸：隐藏侧边栏与顶栏，内容铺满
    BOOL immersive = (self.tab == NEPanelTabPlayer);
    self.sidebar.hidden = immersive;
    self.topBar.hidden = immersive;

    CGFloat contentX = immersive ? 0 : sideW;
    CGFloat contentW = immersive ? W : W - sideW;

    // 顶栏
    self.topBar.frame = CGRectMake(contentX, 8, contentW, 44);
    CGFloat loginW = 62, gap = 10;
    self.loginButton.frame = CGRectMake(contentW - loginW - 12, 8, loginW, 30);
    self.topSearch.frame = CGRectMake(8, 2, contentW - loginW - gap - 16, 40);

    CGFloat top = immersive ? 0 : 58;
    CGFloat playerH = 64;
    CGRect content = CGRectMake(contentX, top, contentW, MAX(0, H - top - playerH));

    self.table.frame = content;
    self.playerPage.frame = content;
    self.profilePage.frame = content;
    self.discoverPage.frame = content;
    self.podcastPage.frame = content;
    self.notesPage.frame = content;

    self.playerBar.frame = CGRectMake(0, H - playerH, W, playerH);
    self.settingsPage.frame = self.bounds;      // 设置页覆盖整个面板
    [self layoutPlayerBar];
}

- (void)reload {
    BOOL isRecommend = (self.tab == NEPanelTabRecommend);
    BOOL isDiscover  = (self.tab == NEPanelTabDiscover);
    BOOL isRoam      = (self.tab == NEPanelTabRoam);
    BOOL isPodcast   = (self.tab == NEPanelTabPodcast);
    BOOL isNotes     = (self.tab == NEPanelTabNotes);
    BOOL isPlayer    = (self.tab == NEPanelTabPlayer);
    BOOL isProfile   = (self.tab == NEPanelTabProfile);

    // 发现/漫游固定用列表；推荐页只在搜索/歌单详情时切列表
    BOOL showTable = isDiscover || isRoam || (isRecommend && self.browsingList);

    self.playerPage.hidden   = !isPlayer;
    self.profilePage.hidden  = !isProfile;
    self.discoverPage.hidden = !(isRecommend && !showTable);
    self.podcastPage.hidden  = !isPodcast;
    self.notesPage.hidden    = !isNotes;
    self.table.hidden        = !showTable;

    if (isPodcast) { [self.podcastPage reload]; return; }
    if (isNotes) { [self.notesPage reload]; return; }

    if (isRecommend && !showTable) {
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
    [self.table reloadData];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (self.tab == NEPanelTabDiscover) return self.toplists.count;
    if (self.tab == NEPanelTabRoam) return self.roamSongs.count;
    if (self.loading) return 1;
    if (!self.songs.count) return 1;
    return self.songs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"content";
    NEContentCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[NEContentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
    }

    if (self.tab == NEPanelTabDiscover) {
        if (ip.row >= (NSInteger)self.toplists.count) return cell;
        NERecommendItem *item = self.toplists[ip.row];
        [cell configureTitle:item.title sub:item.subtitle cover:item.coverURL];
        return cell;
    }
    if (self.tab == NEPanelTabRoam) {
        if (ip.row >= (NSInteger)self.roamSongs.count) return cell;
        NESong *s = self.roamSongs[ip.row];
        [cell configureTitle:s.name sub:s.artist cover:s.coverURL];
        return cell;
    }
    if (self.loading) {
        [cell configureTitle:@"加载中…" sub:@"" cover:nil];
        return cell;
    }
    if (!self.songs.count) {
        [cell configureTitle:@"暂无内容" sub:self.hint ?: @"" cover:nil];
        return cell;
    }
    NESong *s = self.songs[ip.row];
    NSString *sub = s.artist;
    if (s.vipOnly) sub = [sub stringByAppendingString:@"  VIP"];
    [cell configureTitle:s.name sub:sub cover:s.coverURL];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];

    if (self.tab == NEPanelTabDiscover) {
        if (ip.row >= (NSInteger)self.toplists.count) return;
        NERecommendItem *item = self.toplists[ip.row];
        [self openPlaylistID:item.itemID title:item.title];
        return;
    }
    if (self.tab == NEPanelTabRoam) {
        if (ip.row >= (NSInteger)self.roamSongs.count) return;
        [[NEPlayer shared] playQueue:self.roamSongs atIndex:ip.row];
        [self openPlayerPage];
        return;
    }
    if (self.loading || ip.row >= (NSInteger)self.songs.count) return;
    [[NEPlayer shared] playQueue:self.songs atIndex:ip.row];
    [self openPlayerPage];
}

#pragma mark - NEDiscoverPageDelegate

- (void)discoverPage:(id)page didOpenPlaylistID:(NSString *)playlistID title:(NSString *)title {
    [self openPlaylistID:playlistID title:title];
}

- (void)discoverPage:(id)page didPlaySong:(NESong *)song {
    if (!song) return;
    [[NEPlayer shared] playQueue:@[song] atIndex:0];
    [self openPlayerPage];
}

- (void)discoverPage:(id)page didLoadSongs:(NSArray<NESong *> *)songs title:(NSString *)title {
    if (!songs.count) return;
    self.currentPlaylistTitle = title;
    self.songs = songs;
    self.browsingList = YES;
    self.loading = NO;
    self.hint = [NSString stringWithFormat:@"%@ · %lu 首", title ?: @"", (unsigned long)songs.count];
    self.tab = NEPanelTabRecommend;
    [self highlightTab];
    [self reload];
}

#pragma mark - 发现/漫游/心动

- (void)loadToplistsIfNeeded {
    if (self.toplists.count) return;
    __weak typeof(self) weakSelf = self;
    [[NEApi shared] fetchToplists:^(NSArray<NERecommendItem *> *items, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.toplists = items ?: @[];
        [self reload];
    }];
}

- (void)loadRoamIfNeeded {
    if (self.roamSongs.count) return;
    __weak typeof(self) weakSelf = self;
    [[NEApi shared] fetchRecommendNewSongs:30 complete:^(NSArray<NERecommendItem *> *items, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSMutableArray<NESong *> *songs = [NSMutableArray array];
        for (NERecommendItem *item in items) {
            NESong *song = [NESong new];
            song.songID = item.itemID;
            song.name = item.title;
            song.artist = item.subtitle;
            song.coverURL = item.coverURL;
            if (song.songID.length) [songs addObject:song];
        }
        self.roamSongs = songs;
        [self reload];
    }];
}

- (void)openPlaylistID:(NSString *)playlistID title:(NSString *)title {
    if (!playlistID.length) return;
    self.currentPlaylistTitle = title;
    self.tab = NEPanelTabRecommend;
    self.browsingList = YES;
    self.loading = YES;
    [self highlightTab];
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

- (void)alertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    UIViewController *host = [self topMostViewController];
    if (host) [host presentViewController:alert animated:YES completion:nil];
}

- (void)discoverPageDidRequestRoam:(id)page {
    self.tab = NEPanelTabRoam;
    [self highlightTab];
    [self loadRoamIfNeeded];
    [self reload];
}

- (void)discoverPageDidRequestToplist:(id)page {
    self.tab = NEPanelTabDiscover;
    [self highlightTab];
    [self loadToplistsIfNeeded];
    [self reload];
}

- (void)discoverPageDidRequestHeartMode:(id)page {
    [self runHeartMode];
}

- (void)profilePageDidRequestHeartMode:(id)page {
    [self runHeartMode];
}

- (void)runHeartMode {
    NSString *seed = [NEPlayer shared].currentSong.songID;
    if (!seed.length) seed = self.songs.firstObject.songID;
    if (!seed.length) seed = @"347230";

    __weak typeof(self) weakSelf = self;
    [[NEApi shared] fetchHeartModeSongsWithSeed:seed limit:30 complete:^(NSArray<NESong *> *songs, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (error || !songs.count) {
            [self alertWithTitle:@"心动模式不可用"
                         message:error.localizedDescription ?: @"服务端没有返回歌曲"];
            return;
        }
        self.songs = songs;
        self.browsingList = YES;
        self.loading = NO;
        self.hint = [NSString stringWithFormat:@"心动模式 · %lu 首", (unsigned long)songs.count];
        self.tab = NEPanelTabRecommend;
        [self highlightTab];
        [self reload];
    }];
}

#pragma mark - NEProfilePageDelegate

- (void)profilePage:(id)page didSelectPlaylist:(NEPlaylist *)playlist {
    [self openPlaylistID:playlist.playlistID title:playlist.name];
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
        self.tab = NEPanelTabRecommend;
        self.browsingList = NO;
        [self highlightTab];
        [self reload];
        return;
    }

    // search merged into the top search bar
    self.tab = NEPanelTabRecommend;
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

    __weak typeof(self) weakSelf = self;
    _playerPage.onCollapse = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf closePlayerPage];
    };

    _profilePage = [[NEProfilePage alloc] initWithFrame:CGRectZero];
    _profilePage.hidden = YES;
    _profilePage.delegate = self;
    [self addSubview:_profilePage];

    _discoverPage = [[NEDiscoverPage alloc] initWithFrame:CGRectZero];
    _discoverPage.hidden = YES;
    _discoverPage.delegate = self;
    [self addSubview:_discoverPage];

    // 播客 / 笔记：用 9.6.13 二进制里挖到的接口（参数还在补）
    _podcastPage = [[NEFeedPage alloc] initWithTitle:@"播客"
        loader:^(void (^done)(NSArray *items, NSError *error)) {
            [[NEApi shared] fetchPodcastHomeWithPageCode:@"PODCAST_HOMEPAGE_PODCAST_TAB"
                                                complete:^(NSArray<NERecommendItem *> *items, NSError *err) {
                NSMutableArray *rows = [NSMutableArray array];
                for (NERecommendItem *it in items) {
                    if (![it isKindOfClass:[NERecommendItem class]]) continue;
                    [rows addObject:@{@"title": it.title ?: @"",
                                      @"subTitle": it.subtitle ?: @"",
                                      @"coverUrl": it.coverURL ?: @""}];
                }
                done(rows, err);
            }];
        }];
    _podcastPage.hidden = YES;
    [self addSubview:_podcastPage];

    _notesPage = [[NEFeedPage alloc] initWithTitle:@"笔记"
                                              path:@"/api/mlog/feed/bff/app/v1"
                                            params:@{@"size": @10, @"offset": @0}
                                         arrayKeys:@[@"data", @"data.list", @"list"]];
    _notesPage.hidden = YES;
    [self addSubview:_notesPage];
}

#pragma mark - 设置页

- (void)buildSettingsPage {
    _settingsPage = [[NESettingsPage alloc] initWithFrame:CGRectZero];
    _settingsPage.hidden = YES;
    _settingsPage.delegate = self;
    [self addSubview:_settingsPage];
}

- (void)profilePageDidTapSettings:(id)page {
    [self presentSettings];
}

- (void)presentSettings {
    self.settingsPage.hidden = NO;
    [self.settingsPage reloadData];
    self.settingsPage.alpha = 0;
    self.settingsPage.transform = CGAffineTransformMakeTranslation(0, 32);
    [UIView animateWithDuration:0.26 delay:0
                         options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.settingsPage.alpha = 1;
        self.settingsPage.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)hideSettingsImmediately {
    self.settingsPage.hidden = YES;
    self.settingsPage.alpha = 1;
    self.settingsPage.transform = CGAffineTransformIdentity;
}

- (void)dismissSettingsWithCompletion:(void (^ _Nullable)(void))completion {
    [UIView animateWithDuration:0.2 delay:0
                         options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self.settingsPage.alpha = 0;
        self.settingsPage.transform = CGAffineTransformMakeTranslation(0, 26);
    } completion:^(BOOL finished) {
        self.settingsPage.hidden = YES;
        self.settingsPage.alpha = 1;
        self.settingsPage.transform = CGAffineTransformIdentity;
        if (completion) completion();
    }];
}

- (void)settingsPageDidClose:(id)page {
    [self dismissSettingsWithCompletion:nil];
}

- (void)settingsPageDidLogout:(id)page {
    __weak typeof(self) weakSelf = self;
    [self dismissSettingsWithCompletion:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [[NEApi shared] logout];
        [self loadAccountThenDiscover];
        [self.profilePage reloadData];
    }];
}

- (void)settingsPageDidRequestSwitchAccount:(id)page {
    __weak typeof(self) weakSelf = self;
    [self dismissSettingsWithCompletion:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [[NEApi shared] logout];
        [self loadAccountThenDiscover];
        [self.profilePage reloadData];
        // 登出后直接弹登录（扫码 / 其他登录方式）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self showLogin];
        });
    }];
}

#pragma mark - 播放条

- (void)buildPlayerBar {
    _playerBar = [[UIView alloc] initWithFrame:CGRectZero];
    _playerBar.backgroundColor = NE_PANEL;
    _playerBar.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    _playerBar.layer.borderColor = NE_STROKE.CGColor;
    [self addSubview:_playerBar];

    _barCover = [[UIImageView alloc] initWithFrame:CGRectZero];
    _barCover.backgroundColor = NE_CARD;
    _barCover.layer.cornerRadius = 6;
    _barCover.layer.cornerCurve = kCACornerCurveContinuous;
    _barCover.clipsToBounds = YES;
    _barCover.contentMode = UIViewContentModeScaleAspectFill;
    _barCover.userInteractionEnabled = NO;
    [_playerBar addSubview:_barCover];

    // 点播放条打开播放页（和网易云一致）
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
                                   initWithTarget:self action:@selector(openPlayerPage)];
    tap.delegate = self;      // 点在按钮/滑杆上时不触发
    [_playerBar addGestureRecognizer:tap];

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
    _barCover.frame = CGRectMake(10, 10, 44, 44);
    _nowTitle.frame = CGRectMake(64, 10, w - 140, 18);
    _nowSub.frame = CGRectMake(64, 30, w - 140, 14);
    _playBtn.frame = CGRectMake(w - 56, 12, 44, 44);
    // 细进度条贴在播放条顶部
    _progress.frame = CGRectMake(0, 0, w, 2);
}

- (void)toggle { [[NEPlayer shared] togglePlayPause]; }

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
       shouldReceiveTouch:(UITouch *)touch {
    return ![touch.view isKindOfClass:[UIControl class]];
}

- (void)openPlayerPage {
    if (self.tab == NEPanelTabPlayer) return;
    self.previousTab = (NSInteger)self.tab;
    [self hideSettingsImmediately];
    self.tab = NEPanelTabPlayer;
    [self highlightTab];
    [self setNeedsLayout];
    [self reload];
    [self animatePlayerIn];
}

- (void)animatePlayerIn {
    self.playerPage.alpha = 0;
    self.playerPage.transform = CGAffineTransformMakeTranslation(0, 28);
    [UIView animateWithDuration:0.26 delay:0
                         options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.playerPage.alpha = 1;
        self.playerPage.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)closePlayerPage {
    __weak typeof(self) weakSelf = self;
    [UIView animateWithDuration:0.2 delay:0
                         options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self.playerPage.alpha = 0;
        self.playerPage.transform = CGAffineTransformMakeTranslation(0, 24);
    } completion:^(BOOL finished) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.playerPage.alpha = 1;
        self.playerPage.transform = CGAffineTransformIdentity;
        NEPanelTab back = (NEPanelTab)self.previousTab;
        if (back == NEPanelTabPlayer || back < 0) back = NEPanelTabRecommend;
        self.tab = back;
        [self highlightTab];
        [self setNeedsLayout];
        [self reload];
    }];
}

- (void)seekEnd {
    [[NEPlayer shared] seekTo:self.progress.value];
}

- (void)observeTheme {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeChanged)
                                                 name:NEThemeChangedNotification
                                               object:nil];
}

- (void)themeChanged {
    self.backgroundColor = NE_BG;
    NEApplyThemeToView(self);
    [self setNeedsLayout];
    [self layoutIfNeeded];
    [self reload];
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
    if (s.coverURL.length && ![s.coverURL isEqualToString:self.barCoverURL]) {
        self.barCoverURL = s.coverURL;
        self.barCover.image = nil;
        __weak typeof(self) weakSelf = self;
        [[NEImageCache shared] loadImageWithURL:s.coverURL completion:^(UIImage *image) {
            __strong typeof(weakSelf) self = weakSelf;
            if (image) self.barCover.image = image;
        }];
    } else if (!s.coverURL.length) {
        self.barCoverURL = nil;
        self.barCover.image = nil;
    }
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
