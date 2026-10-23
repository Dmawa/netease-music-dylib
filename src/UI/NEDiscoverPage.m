#import "NEDiscoverPage.h"
#import "NEUITheme.h"
#import "NEImageCache.h"
#import "NEPlayer.h"

/// 快捷入口卡片（每日推荐 / 私人漫游 ...）
@interface NEShortcutCard : UIControl
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *title;
@property (nonatomic, strong) UILabel *subtitle;
- (void)configureTitle:(NSString *)t sub:(NSString *)s icon:(NSString *)iconName;
@end

@implementation NEShortcutCard
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 10;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;
        self.backgroundColor = NE_CARD;

        _icon = [[UIImageView alloc] initWithFrame:CGRectZero];
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        _icon.tintColor = UIColor.whiteColor;
        [self addSubview:_icon];

        _title = [UILabel new];
        _title.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _title.textColor = NE_TEXT;
        _title.numberOfLines = 2;
        [self addSubview:_title];

        _subtitle = [UILabel new];
        _subtitle.font = [UIFont systemFontOfSize:10];
        _subtitle.textColor = NE_TEXT_DIM;
        _subtitle.numberOfLines = 2;
        [self addSubview:_subtitle];
    }
    return self;
}
- (void)configureTitle:(NSString *)t sub:(NSString *)s icon:(NSString *)iconName {
    _title.text = t;
    _subtitle.text = s ?: @"";
    _icon.image = [UIImage systemImageNamed:iconName ?: @"music.note"];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    _icon.frame = CGRectMake(10, 10, 26, 26);
    _title.frame = CGRectMake(10, h - 46, w - 20, 20);
    _subtitle.frame = CGRectMake(10, h - 26, w - 20, 18);
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.7 : 1.0;
}
@end

/// 歌单卡片（封面 + 两行标题）
@interface NEPlaylistCard : UIControl
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UILabel *title;
@property (nonatomic, strong) UILabel *subtitle;
@end

@implementation NEPlaylistCard
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _cover = [[UIImageView alloc] initWithFrame:CGRectZero];
        _cover.contentMode = UIViewContentModeScaleAspectFill;
        _cover.clipsToBounds = YES;
        _cover.layer.cornerRadius = 8;
        _cover.layer.cornerCurve = kCACornerCurveContinuous;
        _cover.backgroundColor = NE_CARD;
        [self addSubview:_cover];

        _title = [UILabel new];
        _title.font = [UIFont systemFontOfSize:12];
        _title.textColor = NE_TEXT;
        _title.numberOfLines = 2;
        [self addSubview:_title];

        _subtitle = [UILabel new];
        _subtitle.font = [UIFont systemFontOfSize:10];
        _subtitle.textColor = NE_TEXT_DIM;
        [self addSubview:_subtitle];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    _cover.frame = CGRectMake(0, 0, w, w);
    _title.frame = CGRectMake(0, w + 6, w, 30);
    _subtitle.frame = CGRectMake(0, w + 36, w, 14);
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.75 : 1.0;
}
@end

/// 新歌行
@interface NESongRow : UIControl
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UILabel *title;
@property (nonatomic, strong) UILabel *subtitle;
@property (nonatomic, strong) UILabel *indexLabel;
@end

@implementation NESongRow
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _indexLabel = [UILabel new];
        _indexLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
        _indexLabel.textColor = NE_TEXT_DIM;
        _indexLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_indexLabel];

        _cover = [[UIImageView alloc] initWithFrame:CGRectZero];
        _cover.contentMode = UIViewContentModeScaleAspectFill;
        _cover.clipsToBounds = YES;
        _cover.layer.cornerRadius = 6;
        _cover.layer.cornerCurve = kCACornerCurveContinuous;
        _cover.backgroundColor = NE_CARD;
        [self addSubview:_cover];

        _title = [UILabel new];
        _title.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _title.textColor = NE_TEXT;
        [self addSubview:_title];

        _subtitle = [UILabel new];
        _subtitle.font = [UIFont systemFontOfSize:11];
        _subtitle.textColor = NE_TEXT_DIM;
        [self addSubview:_subtitle];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    _indexLabel.frame = CGRectMake(4, (h - 16) / 2, 22, 16);
    CGFloat s = h - 12;
    _cover.frame = CGRectMake(30, 6, s, s);
    _title.frame = CGRectMake(CGRectGetMaxX(_cover.frame) + 10, (h - 34) / 2, w - s - 60, 18);
    _subtitle.frame = CGRectMake(_title.frame.origin.x, CGRectGetMaxY(_title.frame), w - s - 60, 14);
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.75 : 1.0;
}
@end

#pragma mark - 发现页

@interface NEDiscoverPage ()
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIView *content;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;

@property (nonatomic, strong) NSArray<NERecommendItem *> *playlists;
@property (nonatomic, strong) NSArray<NERecommendItem *> *recentSongs;
@property (nonatomic, strong) NSArray<NERecommendItem *> *toplists;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL layoutDone;
@property (nonatomic, assign) CGFloat lastW;
@end

@implementation NEDiscoverPage

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;

        _scroll = [[UIScrollView alloc] initWithFrame:self.bounds];
        _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _scroll.showsVerticalScrollIndicator = NO;
        _scroll.alwaysBounceVertical = YES;
        [self addSubview:_scroll];

        _content = [[UIView alloc] initWithFrame:CGRectZero];
        [_scroll addSubview:_content];

        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        _spinner.color = NE_TEXT_DIM;
        _spinner.hidesWhenStopped = YES;
        [self addSubview:_spinner];
    }
    return self;
}

- (void)reloadData {
    if (self.loading) return;
    self.loading = YES;
    [self.spinner startAnimating];

    __weak typeof(self) weakSelf = self;
    dispatch_group_t g = dispatch_group_create();

    dispatch_group_enter(g);
    [[NEApi shared] fetchRecommendPlaylists:8 complete:^(NSArray<NERecommendItem *> *items, NSError *e) {
        __strong typeof(weakSelf) s = weakSelf;
        if (s) s.playlists = items ?: @[];
        dispatch_group_leave(g);
    }];

    dispatch_group_enter(g);
    [[NEApi shared] fetchRecommendNewSongs:8 complete:^(NSArray<NERecommendItem *> *items, NSError *e) {
        __strong typeof(weakSelf) s = weakSelf;
        if (s) s.recentSongs = items ?: @[];
        dispatch_group_leave(g);
    }];

    dispatch_group_enter(g);
    [[NEApi shared] fetchToplists:^(NSArray<NERecommendItem *> *items, NSError *e) {
        __strong typeof(weakSelf) s = weakSelf;
        if (s) s.toplists = items ?: @[];
        dispatch_group_leave(g);
    }];

    dispatch_group_notify(g, dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) s = weakSelf;
        if (!s) return;
        s.loading = NO;
        [s.spinner stopAnimating];
        s.layoutDone = NO;
        [s setNeedsLayout];
        [s layoutIfNeeded];
    });
}

#pragma mark - 布局

- (void)layoutSubviews {
    [super layoutSubviews];
    self.scroll.frame = self.bounds;
    self.spinner.center = CGPointMake(self.bounds.size.width / 2, 80);

    CGFloat w = self.bounds.size.width;
    if (w < 1) { self.layoutDone = NO; return; }
    if (self.layoutDone && fabs(w - self.lastW) < 0.5) return;
    self.lastW = w;

    for (UIView *v in self.content.subviews) [v removeFromSuperview];
    self.content.frame = CGRectMake(0, 0, w, 0);

    CGFloat pad = 14;
    CGFloat usable = w - pad * 2;
    CGFloat y = 10;

    // ---------- 快捷入口 ----------
    [self addSectionTitle:@"为你推荐" width:w y:&y];

    NSArray *shortcuts = @[
        @[@"每日推荐", @"按口味推荐", @"calendar"],
        @[@"私人漫游", @"随心听", @"infinity"],
        @[@"心动模式", @"红心与相似", @"heart.text.square"],
        @[@"私人雷达", @"反复聆听", @"dot.radiowaves.left.and.right"],
        @[@"排行榜", @"热门榜单", @"chart.bar"],
    ];
    CGFloat cardW = 112, cardH = 78, gap = 10;
    CGFloat totalW = shortcuts.count * cardW + (shortcuts.count - 1) * gap;
    if (totalW <= usable) {
        // 放得下就平均分布
        cardW = (usable - (shortcuts.count - 1) * gap) / shortcuts.count;
        totalW = usable;
    }
    UIScrollView *hscroll = [[UIScrollView alloc] initWithFrame:CGRectMake(pad, y, usable, cardH)];
    hscroll.showsHorizontalScrollIndicator = NO;
    hscroll.contentSize = CGSizeMake(totalW, cardH);
    CGFloat cx = 0;
    for (NSInteger i = 0; i < (NSInteger)shortcuts.count; i++) {
        NSArray *cfg = shortcuts[i];
        NEShortcutCard *c = [[NEShortcutCard alloc] initWithFrame:CGRectMake(cx, 0, cardW, cardH)];
        [c configureTitle:cfg[0] sub:cfg[1] icon:cfg[2]];
        c.tag = 1000 + i;
        [c addTarget:self action:@selector(shortcutTapped:) forControlEvents:UIControlEventTouchUpInside];
        [hscroll addSubview:c];
        cx += cardW + gap;
    }
    [self.content addSubview:hscroll];
    y += cardH + 22;

    // ---------- 推荐歌单 ----------
    if (self.playlists.count) {
        [self addSectionTitle:@"推荐歌单" width:w y:&y];
        NSInteger cols = (w >= 700) ? 4 : ((w >= 480) ? 3 : 2);
        CGFloat innerGap = 12;
        CGFloat itemW = (usable - (cols - 1) * innerGap) / cols;
        CGFloat rowH = itemW + 56;
        NSInteger rows = (self.playlists.count + cols - 1) / cols;
        for (NSInteger i = 0; i < (NSInteger)self.playlists.count; i++) {
            NSInteger r = i / cols, c = i % cols;
            NERecommendItem *it = self.playlists[i];
            NEPlaylistCard *card = [[NEPlaylistCard alloc] initWithFrame:
                CGRectMake(pad + c * (itemW + innerGap), y + r * rowH, itemW, rowH - 6)];
            card.title.text = it.title;
            card.subtitle.text = it.subtitle;
            card.tag = 2000 + i;
            [card addTarget:self action:@selector(playlistTapped:) forControlEvents:UIControlEventTouchUpInside];
            if (it.coverURL.length) {
                __weak NEPlaylistCard *weakCard = card;
                [[NEImageCache shared] loadImageWithURL:it.coverURL completion:^(UIImage *img) {
                    if (img) weakCard.cover.image = img;
                }];
            }
            [self.content addSubview:card];
        }
        y += rows * rowH + 16;
    }

    // ---------- 最近热门（新歌） ----------
    if (self.recentSongs.count) {
        [self addSectionTitle:@"最近热门" width:w y:&y];
        CGFloat rowH = 56;
        for (NSInteger i = 0; i < (NSInteger)self.recentSongs.count; i++) {
            NERecommendItem *it = self.recentSongs[i];
            NESongRow *row = [[NESongRow alloc] initWithFrame:CGRectMake(pad, y, usable, rowH)];
            row.indexLabel.text = [NSString stringWithFormat:@"%02ld", (long)(i + 1)];
            row.title.text = it.title;
            row.subtitle.text = it.subtitle;
            row.tag = 3000 + i;
            [row addTarget:self action:@selector(songTapped:) forControlEvents:UIControlEventTouchUpInside];
            if (it.coverURL.length) {
                __weak NESongRow *weakRow = row;
                [[NEImageCache shared] loadImageWithURL:it.coverURL completion:^(UIImage *img) {
                    if (img) weakRow.cover.image = img;
                }];
            }
            [self.content addSubview:row];
            y += rowH;
        }
        y += 16;
    }

    self.content.frame = CGRectMake(0, 0, w, y + 20);
    self.scroll.contentSize = self.content.bounds.size;
    self.layoutDone = YES;
}

- (void)addSectionTitle:(NSString *)t width:(CGFloat)w y:(CGFloat *)y {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(14, *y, w - 28, 22)];
    l.text = t;
    l.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    l.textColor = NE_TEXT;
    [self.content addSubview:l];
    *y += 32;
}

#pragma mark - 交互

- (void)shortcutTapped:(NEShortcutCard *)c {
    NSInteger idx = c.tag - 1000;

    if (idx == 4) {             // 排行榜 → 发现页
        if ([self.delegate respondsToSelector:@selector(discoverPageDidRequestToplist:)]) {
            [self.delegate discoverPageDidRequestToplist:self];
        }
        return;
    }
    if (idx == 1) {             // 私人漫游 → 漫游 tab
        if ([self.delegate respondsToSelector:@selector(discoverPageDidRequestRoam:)]) {
            [self.delegate discoverPageDidRequestRoam:self];
        }
        return;
    }
    if (idx == 2) {             // 心动模式
        if ([self.delegate respondsToSelector:@selector(discoverPageDidRequestHeartMode:)]) {
            [self.delegate discoverPageDidRequestHeartMode:self];
        }
        return;
    }
    if (idx == 3) {             // 私人雷达
        [self toast:@"私人雷达接口未开放，先用「心动模式」"];
        return;
    }
    if (idx == 0) {
        // 每日推荐：v3 接口，登录后按口味，未登录给一份通用推荐
        [self toast:@"正在拉取每日推荐…"];
        __weak typeof(self) weakSelf = self;
        [[NEApi shared] fetchDailyRecommendSongs:^(NSArray<NESong *> *songs, NSError *error) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            if (error || !songs.count) {
                [self toast:error.localizedDescription ?: @"每日推荐暂时没有内容"];
                return;
            }
            if ([self.delegate respondsToSelector:@selector(discoverPage:didLoadSongs:title:)]) {
                [self.delegate discoverPage:self didLoadSongs:songs title:@"每日推荐"];
            }
        }];
        return;
    }
    [self toast:@"该入口暂未接入"];
}

- (void)playlistTapped:(NEPlaylistCard *)card {
    NSInteger i = card.tag - 2000;
    if (i < 0 || i >= (NSInteger)self.playlists.count) return;
    NERecommendItem *it = self.playlists[i];
    if ([self.delegate respondsToSelector:@selector(discoverPage:didOpenPlaylistID:title:)])
        [self.delegate discoverPage:self didOpenPlaylistID:it.itemID title:it.title];
}

- (void)songTapped:(NESongRow *)row {
    NSInteger i = row.tag - 3000;
    if (i < 0 || i >= (NSInteger)self.recentSongs.count) return;
    NERecommendItem *it = self.recentSongs[i];
    // 新歌只有 id，构造一个最简 NESong 交给播放器
    NESong *s = [NESong new];
    s.songID = it.itemID;
    s.name = it.title;
    s.artist = it.subtitle;
    s.coverURL = it.coverURL;
    if ([self.delegate respondsToSelector:@selector(discoverPage:didPlaySong:)])
        [self.delegate discoverPage:self didPlaySong:s];
}

- (void)toast:(NSString *)msg {
    UIWindow *win = self.window;
    if (!win) return;
    UILabel *l = [UILabel new];
    l.text = msg;
    l.font = [UIFont systemFontOfSize:12];
    l.textColor = UIColor.whiteColor;
    l.backgroundColor = [UIColor colorWithWhite:0 alpha:0.82];
    l.textAlignment = NSTextAlignmentCenter;
    l.layer.cornerRadius = 14;
    l.layer.cornerCurve = kCACornerCurveContinuous;
    l.clipsToBounds = YES;
    CGSize sz = [l sizeThatFits:CGSizeMake(260, 40)];
    l.frame = CGRectMake((win.bounds.size.width - sz.width - 32) / 2,
                         win.bounds.size.height - 120, sz.width + 32, 32);
    [win addSubview:l];
    l.alpha = 0;
    [UIView animateWithDuration:0.18 animations:^{ l.alpha = 1; } completion:^(BOOL f) {
        [UIView animateWithDuration:0.25 delay:1.6 options:0 animations:^{ l.alpha = 0; }
                         completion:^(BOOL f2) { [l removeFromSuperview]; }];
    }];
}

@end