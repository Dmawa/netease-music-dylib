#import "NEProfilePage.h"
#import "NEUITheme.h"
#import "NEImageCache.h"

/// 歌单卡片：封面 + 标题 + 明细（歌单 · N 首 · 作者 / 播放次数），喜欢列表带「心动模式」
@interface NEPlaylistCell : UITableViewCell
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UILabel *title;
@property (nonatomic, strong) UILabel *subtitle;
@property (nonatomic, strong) UIImageView *badge;
@property (nonatomic, strong) UIButton *heartBtn;
@property (nonatomic, copy, nullable) void (^onHeart)(void);
- (void)configureWithPlaylist:(NEPlaylist *)p liked:(BOOL)liked;
@end

@implementation NEPlaylistCell

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
        _cover.layer.cornerRadius = 8;
        _cover.layer.cornerCurve = kCACornerCurveContinuous;
        _cover.backgroundColor = NE_CARD;
        [self.contentView addSubview:_cover];

        _title = [UILabel new];
        _title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        _title.textColor = NE_TEXT;
        [self.contentView addSubview:_title];

        _subtitle = [UILabel new];
        _subtitle.font = [UIFont systemFontOfSize:11];
        _subtitle.textColor = NE_TEXT_DIM;
        [self.contentView addSubview:_subtitle];

        _badge = [[UIImageView alloc] initWithFrame:CGRectZero];
        _badge.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:_badge];

        _heartBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        [_heartBtn setTitle:@"♡ 心动模式" forState:UIControlStateNormal];
        _heartBtn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        [_heartBtn setTitleColor:NE_TEXT forState:UIControlStateNormal];
        _heartBtn.layer.borderWidth = 1;
        _heartBtn.layer.borderColor = NEColor(0xFFFFFF, 0.22).CGColor;
        _heartBtn.layer.cornerRadius = 13;
        _heartBtn.hidden = YES;
        [_heartBtn addTarget:self action:@selector(heartTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_heartBtn];
    }
    return self;
}

- (void)heartTapped {
    if (self.onHeart) self.onHeart();
}

- (void)configureWithPlaylist:(NEPlaylist *)p liked:(BOOL)liked {
    _heartBtn.hidden = !liked;
    _title.text = liked ? @"我喜欢的音乐" : (p.name ?: @"");
    if (liked) {
        _subtitle.text = [NSString stringWithFormat:@"%ld 首 · %ld 次播放",
                          (long)p.trackCount, (long)p.playCount];
    } else {
        NSString *creator = p.creatorName.length ? p.creatorName : @"歌单";
        _subtitle.text = [NSString stringWithFormat:@"歌单 · %ld 首 · %@",
                          (long)p.trackCount, creator];
    }

    if (liked) {
        _cover.backgroundColor = NE_BRAND;
        _cover.image = nil;
        _badge.image = [UIImage systemImageNamed:@"heart.fill"];
        _badge.tintColor = UIColor.whiteColor;
        _badge.hidden = NO;
    } else {
        _badge.hidden = YES;
        if (p.coverURL.length) {
            __weak typeof(self) weakSelf = self;
            [[NEImageCache shared] loadImageWithURL:p.coverURL completion:^(UIImage *img) {
                if (img) weakSelf.cover.image = img;
            }];
        }
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.contentView.bounds.size.height;
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat sz = h - 16;
    _cover.frame = CGRectMake(14, 8, sz, sz);
    CGFloat right = _heartBtn.hidden ? 14 : 108;
    _title.frame = CGRectMake(CGRectGetMaxX(_cover.frame) + 12, 14, w - sz - 40 - right, 18);
    _subtitle.frame = CGRectMake(_title.frame.origin.x, CGRectGetMaxY(_title.frame) + 3,
                                 w - sz - 40 - right, 14);
    _heartBtn.frame = CGRectMake(w - 96, (h - 26) / 2, 86, 26);
    if (!_badge.hidden) {
        _badge.frame = CGRectMake(CGRectGetMidX(_cover.bounds) - 12,
                                  CGRectGetMidY(_cover.bounds) - 12, 24, 24);
        [_cover addSubview:_badge];
    }
}

@end

#pragma mark - 我的页

@interface NEProfilePage () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UIView *accountHeader;
@property (nonatomic, strong) UIImageView *banner;
@property (nonatomic, strong) UIView *bannerMask;
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *vipLabel;
@property (nonatomic, strong) UILabel *statsLabel;
@property (nonatomic, strong) UIButton *gearBtn;
@property (nonatomic, strong) UITableView *table;

@property (nonatomic, strong) NEPlaylist *likedPlaylist;
@property (nonatomic, strong) NSArray<NEPlaylist *> *collected;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, copy) NSString *hint;
@end

@implementation NEProfilePage

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        [self build];
    }
    return self;
}

- (void)build {
    _accountHeader = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.bounds.size.width, 132)];
    _accountHeader.clipsToBounds = YES;

    _banner = [[UIImageView alloc] initWithFrame:_accountHeader.bounds];
    _banner.contentMode = UIViewContentModeScaleAspectFill;
    _banner.clipsToBounds = YES;
    _banner.alpha = 0.35;
    [_accountHeader addSubview:_banner];

    _bannerMask = [[UIView alloc] initWithFrame:_accountHeader.bounds];
    _bannerMask.backgroundColor = NEColor(0x000000, 0.25);
    [_accountHeader addSubview:_bannerMask];

    _avatar = [[UIImageView alloc] initWithFrame:CGRectMake(14, 18, 64, 64)];
    _avatar.backgroundColor = NE_CARD;
    _avatar.layer.cornerRadius = 32;
    _avatar.layer.cornerCurve = kCACornerCurveContinuous;
    _avatar.layer.borderWidth = 2;
    _avatar.layer.borderColor = NEColor(0xFFFFFF, 0.85).CGColor;
    _avatar.clipsToBounds = YES;
    _avatar.contentMode = UIViewContentModeScaleAspectFill;
    [_accountHeader addSubview:_avatar];

    _nameLabel = [UILabel new];
    _nameLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _nameLabel.textColor = NE_TEXT;
    [_accountHeader addSubview:_nameLabel];

    _vipLabel = [UILabel new];
    _vipLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    _vipLabel.textColor = NEColor(0xF6D48A, 1.0);
    [_accountHeader addSubview:_vipLabel];

    _statsLabel = [UILabel new];
    _statsLabel.font = [UIFont systemFontOfSize:11];
    _statsLabel.textColor = NE_TEXT_DIM;
    _statsLabel.text = @"关注 — · 粉丝 — · 等级 — · 听歌 —";
    [_accountHeader addSubview:_statsLabel];

    _gearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    // 三条杠（☰）：网易云里就是它打开「我的」设置抽屉
    [_gearBtn setImage:[UIImage systemImageNamed:@"line.horizontal.3"] forState:UIControlStateNormal];
    _gearBtn.tintColor = NE_TEXT;
    [_gearBtn addTarget:self action:@selector(gearTapped) forControlEvents:UIControlEventTouchUpInside];
    [_accountHeader addSubview:_gearBtn];

    [self addSubview:_accountHeader];

    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    _table.backgroundColor = UIColor.clearColor;
    _table.separatorColor = NE_STROKE;
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = 68;
    _table.sectionHeaderHeight = 30;
    _table.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [self addSubview:_table];
}

- (void)reloadData {
    [self reloadAccountHeader];
    if (![[NEApi shared] isLoggedIn]) {
        self.hint = @"登录后可查看收藏";
        self.likedPlaylist = nil;
        self.collected = @[];
        [self.table reloadData];
        return;
    }
    self.loading = YES;
    [self.table reloadData];

    __weak typeof(self) weakSelf = self;
    [[NEApi shared] fetchLikedPlaylist:^(NEPlaylist *playlist, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.likedPlaylist = playlist;
        [[NEApi shared] fetchMyCollectedPlaylists:^(NSArray<NEPlaylist *> *list, NSError *err) {
            __strong typeof(weakSelf) self2 = weakSelf;
            if (!self2) return;
            self2.loading = NO;
            self2.collected = list ?: @[];
            [self2.table reloadData];
        }];
    }];
}

#pragma mark - 账号横幅

- (void)reloadAccountHeader {
    if (![[NEApi shared] isLoggedIn]) {
        _nameLabel.text = @"未登录";
        _vipLabel.text = @"登录后可同步歌单";
        _statsLabel.text = @"关注 — · 粉丝 — · 等级 — · 听歌 —";
        _avatar.image = nil;
        _banner.image = nil;
        return;
    }

    __weak typeof(self) weakSelf = self;
    [[NEApi shared] fetchProfile:^(NSDictionary *profile, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![profile isKindOfClass:[NSDictionary class]]) return;

        self.nameLabel.text = profile[@"nickname"] ?: @"已登录";
        NSInteger vipType = [profile[@"vipType"] integerValue];
        self.vipLabel.text = (vipType == 11) ? @"SVIP · 黑胶会员" : (vipType == 1 ? @"音乐包" : @"普通用户");

        NSNumber *follows = profile[@"follows"];
        NSNumber *followeds = profile[@"followeds"];
        NSNumber *level = profile[@"level"];

        NSString *avatarURL = profile[@"avatarUrl"];
        if (avatarURL.length) {
            [[NEImageCache shared] loadImageWithURL:avatarURL completion:^(UIImage *image) {
                __strong typeof(weakSelf) self = weakSelf;
                if (!image) return;
                self.avatar.image = image;
                self.banner.image = image;
            }];
        }

        self.statsLabel.text = [NSString stringWithFormat:@"关注 %@ · 粉丝 %@ · Lv.%@ · 听歌 —",
                                follows ?: @"—", followeds ?: @"—", level ?: @"—"];

        // 9.6.13 的「我的」头部接口：关注/粉丝/等级/听歌量一次给全
        NSNumber *uid = profile[@"userId"];
        if (uid) {
            NSString *uidText = [uid description];
            [[NEApi shared] fetchMineHeaderWithUserID:uidText
                                            complete:^(NSDictionary *header, NSError *err) {
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) return;
                if (![header isKindOfClass:[NSDictionary class]]) {
                    // 兜底：老接口
                    [[NEApi shared] fetchUserDetailWithUID:uidText
                                                 complete:^(NSInteger level, NSInteger listenSongs, NSError *e2) {
                        __strong typeof(weakSelf) self2 = weakSelf;
                        if (!self2) return;
                        self2.statsLabel.text = [NSString stringWithFormat:
                            @"关注 %@ · 粉丝 %@ · Lv.%ld · 听歌 %ld 首",
                            follows ?: @"—", followeds ?: @"—", (long)level, (long)listenSongs];
                    }];
                    return;
                }
                NSString *follow = header[@"followText"] ?: (follows ? [follows description] : @"—");
                NSString *fans = header[@"followedText"] ?: (followeds ? [followeds description] : @"—");
                NSString *lv = header[@"levelText"] ?: (level ? [NSString stringWithFormat:@"Lv.%@", level] : @"—");
                NSNumber *listen = header[@"listenSongs"];
                self.statsLabel.text = [NSString stringWithFormat:
                    @"关注 %@ · 粉丝 %@ · %@ · 听歌 %@ 首",
                    follow, fans, lv, listen ?: @"—"];
            }];
        }
    }];
}

- (void)gearTapped {
    if ([self.delegate respondsToSelector:@selector(profilePageDidTapSettings:)]) {
        [self.delegate profilePageDidTapSettings:self];
    }
}

- (void)heartModeTapped {
    if ([self.delegate respondsToSelector:@selector(profilePageDidRequestHeartMode:)]) {
        [self.delegate profilePageDidRequestHeartMode:self];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width;
    CGFloat H = self.bounds.size.height;

    _accountHeader.frame = CGRectMake(0, 0, W, 132);
    _banner.frame = _accountHeader.bounds;
    _bannerMask.frame = _accountHeader.bounds;
    _nameLabel.frame = CGRectMake(90, 24, W - 150, 22);
    _vipLabel.frame = CGRectMake(90, 47, W - 150, 16);
    _statsLabel.frame = CGRectMake(90, 68, W - 110, 16);
    _gearBtn.frame = CGRectMake(W - 52, 22, 40, 36);
    _table.frame = CGRectMake(0, 132, W, MAX(0, H - 132));
}

#pragma mark - 表

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return self.likedPlaylist ? 1 : 0;
    return self.collected.count;
}

- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)section {
    UILabel *label = [UILabel new];
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    label.textColor = NE_TEXT;
    if (section == 0) {
        label.text = @"  我喜欢的音乐";
    } else {
        label.text = self.collected.count
            ? [NSString stringWithFormat:@"  我的歌单 (%lu)", (unsigned long)self.collected.count]
            : @"  我的歌单";
    }
    return label;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"pl";
    NEPlaylistCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) cell = [[NEPlaylistCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];

    __weak typeof(self) weakSelf = self;
    cell.onHeart = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self) [self heartModeTapped];
    };

    if (ip.section == 0) {
        [cell configureWithPlaylist:self.likedPlaylist liked:YES];
    } else {
        [cell configureWithPlaylist:self.collected[(NSUInteger)ip.row] liked:NO];
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NEPlaylist *p = (ip.section == 0) ? self.likedPlaylist : self.collected[(NSUInteger)ip.row];
    if (!p) return;
    if ([self.delegate respondsToSelector:@selector(profilePage:didSelectPlaylist:)]) {
        [self.delegate profilePage:self didSelectPlaylist:p];
    }
}

@end
