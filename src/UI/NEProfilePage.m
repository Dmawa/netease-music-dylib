#import "NEProfilePage.h"
#import "NEUITheme.h"
#import "NEImageCache.h"

/// 歌单卡片：左侧方块封面 + 右侧标题/曲目数
@interface NEPlaylistCell : UITableViewCell
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UILabel *title;
@property (nonatomic, strong) UILabel *subtitle;
@property (nonatomic, strong) UIImageView *badge;
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
    }
    return self;
}

- (void)configureWithPlaylist:(NEPlaylist *)p liked:(BOOL)liked {
    _title.text = liked ? @"我喜欢的音乐" : p.name;
    _subtitle.text = [NSString stringWithFormat:@"%ld 首", (long)p.trackCount];

    if (liked) {
        // 「我喜欢的音乐」用品牌红方块 + 心形，和普通歌单区分开
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
    _title.frame = CGRectMake(CGRectGetMaxX(_cover.frame) + 12, 12, w - sz - 50, 18);
    _subtitle.frame = CGRectMake(_title.frame.origin.x, CGRectGetMaxY(_title.frame) + 2,
                                 w - sz - 50, 14);
    if (!_badge.hidden) {
        _badge.frame = CGRectMake(CGRectGetMidX(_cover.bounds) - 12,
                                  CGRectGetMidY(_cover.bounds) - 12, 24, 24);
        [_cover addSubview:_badge];
    }
}

@end

#pragma mark - 我的页

@interface NEProfilePage () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIView *accountHeader;
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *vipLabel;
@property (nonatomic, strong) UIButton *gearBtn;

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
    // 顶部账号信息：头像 + 昵称 + VIP，右上角齿轮进设置
    _accountHeader = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.bounds.size.width, 84)];

    _avatar = [[UIImageView alloc] initWithFrame:CGRectMake(14, 20, 44, 44)];
    _avatar.backgroundColor = NE_CARD;
    _avatar.layer.cornerRadius = 22;
    _avatar.layer.cornerCurve = kCACornerCurveContinuous;
    _avatar.clipsToBounds = YES;
    _avatar.contentMode = UIViewContentModeScaleAspectFill;
    [_accountHeader addSubview:_avatar];

    _nameLabel = [UILabel new];
    _nameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _nameLabel.textColor = NE_TEXT;
    [_accountHeader addSubview:_nameLabel];

    _vipLabel = [UILabel new];
    _vipLabel.font = [UIFont systemFontOfSize:11];
    _vipLabel.textColor = NE_TEXT_DIM;
    [_accountHeader addSubview:_vipLabel];

    _gearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [_gearBtn setImage:[UIImage systemImageNamed:@"gearshape"] forState:UIControlStateNormal];
    _gearBtn.tintColor = NE_TEXT_DIM;
    [_gearBtn addTarget:self action:@selector(gearTapped) forControlEvents:UIControlEventTouchUpInside];
    [_accountHeader addSubview:_gearBtn];

    [self addSubview:_accountHeader];

    _table = [[UITableView alloc] initWithFrame:self.bounds style:UITableViewStyleGrouped];
    _table.backgroundColor = UIColor.clearColor;
    _table.separatorColor = NE_STROKE;
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = 68;
    _table.sectionHeaderHeight = 34;
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
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

#pragma mark - 账号头部

- (void)reloadAccountHeader {
    if (![[NEApi shared] isLoggedIn]) {
        _nameLabel.text = @"未登录";
        _vipLabel.text = @"登录后可同步歌单";
        _avatar.image = nil;
        return;
    }

    __weak typeof(self) weakSelf = self;
    [[NEApi shared] fetchProfile:^(NSDictionary *profile, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![profile isKindOfClass:[NSDictionary class]]) return;

        self.nameLabel.text = profile[@"nickname"] ?: @"已登录";
        NSInteger vipType = [profile[@"vipType"] integerValue];
        if (vipType == 11) {
            self.vipLabel.text = @"黑胶 VIP";
        } else if (vipType == 1) {
            self.vipLabel.text = @"音乐包";
        } else {
            self.vipLabel.text = @"普通用户";
        }

        NSString *avatarURL = profile[@"avatarUrl"];
        if (avatarURL.length) {
            [[NEImageCache shared] loadImageWithURL:avatarURL completion:^(UIImage *image) {
                __strong typeof(weakSelf) self = weakSelf;
                if (image) self.avatar.image = image;
            }];
        }
    }];
}

- (void)gearTapped {
    if ([self.delegate respondsToSelector:@selector(profilePageDidTapSettings:)]) {
        [self.delegate profilePageDidTapSettings:self];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width;
    CGFloat H = self.bounds.size.height;

    _accountHeader.frame = CGRectMake(0, 0, W, 84);
    _nameLabel.frame = CGRectMake(70, 22, W - 124, 20);
    _vipLabel.frame = CGRectMake(70, 44, W - 124, 16);
    _gearBtn.frame = CGRectMake(W - 52, 26, 40, 36);
    _table.frame = CGRectMake(0, 84, W, MAX(0, H - 84));
}

#pragma mark - 表

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return self.likedPlaylist ? 1 : (self.loading ? 0 : 0);
    return self.collected.count;
}

- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)section {
    UILabel *l = [UILabel new];
    l.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    l.textColor = NE_TEXT;
    if (section == 0) {
        l.text = @"  我喜欢的音乐";
    } else {
        l.text = self.collected.count ? [NSString stringWithFormat:@"  我的歌单 (%lu)", (unsigned long)self.collected.count]
                                      : @"  我的歌单";
    }
    return l;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"pl";
    NEPlaylistCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) cell = [[NEPlaylistCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];

    if (ip.section == 0) {
        [cell configureWithPlaylist:self.likedPlaylist liked:YES];
    } else {
        [cell configureWithPlaylist:self.collected[ip.row] liked:NO];
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NEPlaylist *p = (ip.section == 0) ? self.likedPlaylist : self.collected[ip.row];
    if (!p) return;
    if ([self.delegate respondsToSelector:@selector(profilePage:didSelectPlaylist:)]) {
        [self.delegate profilePage:self didSelectPlaylist:p];
    }
}

@end