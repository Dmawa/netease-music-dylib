#import "NEPlayerPage.h"
#import "NEUITheme.h"
#import "NEPlayer.h"
#import "NEApi.h"
#import "NELyricView.h"
#import "NEImageCache.h"
#import "NEPlaylistSheet.h"

@interface NEPlayerPage () <NELyricViewDelegate>
@property (nonatomic, strong) UIImageView *coverBackdrop;
@property (nonatomic, strong) UIVisualEffectView *coverBlur;
@property (nonatomic, strong) CAGradientLayer *shade;

@property (nonatomic, strong) UIView *vinylBox;
@property (nonatomic, strong) UIView *discBase;
@property (nonatomic, strong) UIView *discRing;
@property (nonatomic, strong) UIImageView *discCover;
@property (nonatomic, strong) UIView *centerDot;
@property (nonatomic, strong) UIView *armBox;
@property (nonatomic, strong) UIView *tonearm;
@property (nonatomic, strong) UIView *tonearmHead;

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;
@property (nonatomic, strong) UIButton *followBtn;
@property (nonatomic, strong) UILabel *vipBadge;
@property (nonatomic, strong) UIButton *likeBtn;
@property (nonatomic, strong) UILabel *likeCountLabel;
@property (nonatomic, strong) UIButton *commentBtn;
@property (nonatomic, strong) UILabel *commentCountLabel;

@property (nonatomic, strong) UISlider *progress;
@property (nonatomic, strong) UILabel *timeNow;
@property (nonatomic, strong) UILabel *timeTotal;
@property (nonatomic, strong) UILabel *qualityLabel;

@property (nonatomic, strong) UIButton *prevBtn;
@property (nonatomic, strong) UIButton *playBtn;
@property (nonatomic, strong) UIButton *nextBtn;
@property (nonatomic, strong) UIButton *loopBtn;
@property (nonatomic, strong) UIButton *listBtn;

@property (nonatomic, strong) UIButton *deviceBtn;
@property (nonatomic, strong) UIButton *lightBtn;
@property (nonatomic, strong) UIButton *infoBtn;
@property (nonatomic, strong) UIButton *downloadBtn;
@property (nonatomic, strong) UIButton *moreBtn;
@property (nonatomic, strong) UIButton *translateBtn;

@property (nonatomic, strong) UIButton *collapseBtn;
@property (nonatomic, strong) NELyricView *lyricView;
@property (nonatomic, strong) NELyric *lyric;

@property (nonatomic, assign) BOOL showsTranslation;
@property (nonatomic, assign) BOOL userSeeking;
@property (nonatomic, assign) BOOL spinning;
@property (nonatomic, assign) CGFloat lastScale;
@property (nonatomic, copy) NSString *loadedSongID;
@property (nonatomic, copy) NSString *coverURLString;
@property (nonatomic, copy) NSString *likedSongID;
@property (nonatomic, assign) NSInteger commentTotal;
@property (nonatomic, assign) NSInteger likeCount;
@property (nonatomic, strong, nullable) UIViewController *commentsVC;
@end

@implementation NEPlayerPage

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        _showsTranslation = YES;
        [self build];
        [self observe];
    }
    return self;
}

#pragma mark - 构建

- (UIButton *)iconButton:(NSString *)symbol size:(CGFloat)size action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *img = [UIImage systemImageNamed:symbol
                           withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size
                                                                                               weight:UIImageSymbolWeightRegular]];
    [b setImage:img forState:UIControlStateNormal];
    b.tintColor = NE_TEXT;
    b.imageView.contentMode = UIViewContentModeScaleAspectFit;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)build {
    _coverBackdrop = [[UIImageView alloc] initWithFrame:CGRectZero];
    _coverBackdrop.contentMode = UIViewContentModeScaleAspectFill;
    _coverBackdrop.clipsToBounds = YES;
    _coverBackdrop.alpha = 0.55;
    [self addSubview:_coverBackdrop];

    _coverBlur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    _coverBlur.alpha = 0.42;
    _coverBlur.userInteractionEnabled = NO;
    [self addSubview:_coverBlur];

    _shade = [CAGradientLayer layer];
    _shade.colors = @[(id)NEColor(0x000000, 0.12).CGColor,
                      (id)NEColor(0x000000, 0.55).CGColor];
    _shade.locations = @[@0.25, @1.0];
    [self.layer addSublayer:_shade];

    // ---------- 黑胶 ----------
    _vinylBox = [[UIView alloc] initWithFrame:CGRectZero];
    _vinylBox.userInteractionEnabled = NO;
    [self addSubview:_vinylBox];

    _discBase = [[UIView alloc] initWithFrame:CGRectZero];
    _discBase.backgroundColor = NEColor(0x070707, 1.0);
    _discBase.layer.borderWidth = 3;
    _discBase.layer.borderColor = NEColor(0xFFFFFF, 0.16).CGColor;
    _discBase.layer.shadowColor = UIColor.blackColor.CGColor;
    _discBase.layer.shadowOpacity = 0.55;
    _discBase.layer.shadowRadius = 26;
    _discBase.layer.shadowOffset = CGSizeMake(0, 12);
    [_vinylBox addSubview:_discBase];

    _discRing = [[UIView alloc] initWithFrame:CGRectZero];
    _discRing.backgroundColor = UIColor.clearColor;
    _discRing.layer.borderColor = NEColor(0xFFFFFF, 0.05).CGColor;
    _discRing.layer.borderWidth = 1;
    [_vinylBox addSubview:_discRing];

    _discCover = [[UIImageView alloc] initWithFrame:CGRectZero];
    _discCover.backgroundColor = NE_CARD;
    _discCover.clipsToBounds = YES;
    _discCover.contentMode = UIViewContentModeScaleAspectFill;
    [_vinylBox addSubview:_discCover];

    _centerDot = [[UIView alloc] initWithFrame:CGRectZero];
    _centerDot.backgroundColor = NEColor(0xFFFFFF, 0.9);
    [_vinylBox addSubview:_centerDot];

    _armBox = [[UIView alloc] initWithFrame:CGRectZero];
    _armBox.userInteractionEnabled = NO;
    [_vinylBox addSubview:_armBox];

    _tonearm = [[UIView alloc] initWithFrame:CGRectZero];
    _tonearm.backgroundColor = NEColor(0xF2F2F2, 0.92);
    _tonearm.layer.cornerRadius = 1.5;
    [_armBox addSubview:_tonearm];

    _tonearmHead = [[UIView alloc] initWithFrame:CGRectZero];
    _tonearmHead.backgroundColor = NEColor(0xFAFAFA, 0.96);
    _tonearmHead.layer.cornerRadius = 5;
    [_armBox addSubview:_tonearmHead];

    // ---------- 歌曲信息 ----------
    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont systemFontOfSize:26 weight:UIFontWeightSemibold];
    _titleLabel.textColor = NE_TEXT;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:_titleLabel];

    _artistLabel = [UILabel new];
    _artistLabel.font = [UIFont systemFontOfSize:15];
    _artistLabel.textColor = NEColor(0xFFFFFF, 0.62);
    [self addSubview:_artistLabel];

    _followBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [_followBtn setTitle:@"关注" forState:UIControlStateNormal];
    _followBtn.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    [_followBtn setTitleColor:NEColor(0xFFFFFF, 0.75) forState:UIControlStateNormal];
    _followBtn.layer.borderWidth = 1;
    _followBtn.layer.borderColor = NEColor(0xFFFFFF, 0.35).CGColor;
    _followBtn.layer.cornerRadius = 9;
    [_followBtn addTarget:self action:@selector(followArtist) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_followBtn];

    _vipBadge = [UILabel new];
    _vipBadge.text = @"VIP";
    _vipBadge.font = [UIFont systemFontOfSize:8 weight:UIFontWeightBold];
    _vipBadge.textColor = NEColor(0xF6D48A, 1.0);
    _vipBadge.layer.borderWidth = 1;
    _vipBadge.layer.borderColor = NEColor(0xF6D48A, 0.8).CGColor;
    _vipBadge.layer.cornerRadius = 3;
    _vipBadge.textAlignment = NSTextAlignmentCenter;
    _vipBadge.hidden = YES;
    [self addSubview:_vipBadge];

    _likeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [_likeBtn setImage:[UIImage systemImageNamed:@"heart"] forState:UIControlStateNormal];
    _likeBtn.tintColor = NEColor(0xFFFFFF, 0.85);
    [_likeBtn addTarget:self action:@selector(toggleLike) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_likeBtn];

    _likeCountLabel = [UILabel new];
    _likeCountLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _likeCountLabel.textColor = NEColor(0xFFFFFF, 0.7);
    [self addSubview:_likeCountLabel];

    _commentBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [_commentBtn setImage:[UIImage systemImageNamed:@"bubble.left"] forState:UIControlStateNormal];
    _commentBtn.tintColor = NEColor(0xFFFFFF, 0.85);
    [_commentBtn addTarget:self action:@selector(showComments) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_commentBtn];

    _commentCountLabel = [UILabel new];
    _commentCountLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _commentCountLabel.textColor = NEColor(0xFFFFFF, 0.7);
    [self addSubview:_commentCountLabel];

    // ---------- 进度 ----------
    _progress = [[UISlider alloc] initWithFrame:CGRectZero];
    _progress.minimumTrackTintColor = NEColor(0xFFFFFF, 0.92);
    _progress.maximumTrackTintColor = NEColor(0xFFFFFF, 0.22);
    [_progress setThumbImage:[self dotImageWithSize:11 color:UIColor.whiteColor] forState:UIControlStateNormal];
    [_progress addTarget:self action:@selector(sliderTouchDown) forControlEvents:UIControlEventTouchDown];
    [_progress addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
    [_progress addTarget:self action:@selector(sliderTouchUp)
        forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self addSubview:_progress];

    _timeNow = [UILabel new];
    _timeNow.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
    _timeNow.textColor = NEColor(0xFFFFFF, 0.55);
    _timeNow.text = @"00:00";
    [self addSubview:_timeNow];

    _timeTotal = [UILabel new];
    _timeTotal.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
    _timeTotal.textColor = NEColor(0xFFFFFF, 0.55);
    _timeTotal.text = @"00:00";
    _timeTotal.textAlignment = NSTextAlignmentRight;
    [self addSubview:_timeTotal];

    _qualityLabel = [UILabel new];
    _qualityLabel.text = @"极高音质";
    _qualityLabel.font = [UIFont systemFontOfSize:10];
    _qualityLabel.textColor = NEColor(0xFFFFFF, 0.5);
    _qualityLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_qualityLabel];

    // ---------- 控制 ----------
    _loopBtn = [self iconButton:@"repeat" size:15 action:@selector(cycleLoop)];
    _prevBtn = [self iconButton:@"backward.end.fill" size:20 action:@selector(prev)];
    _playBtn = [self iconButton:@"pause.fill" size:30 action:@selector(toggle)];
    _nextBtn = [self iconButton:@"forward.end.fill" size:20 action:@selector(next)];
    _listBtn = [self iconButton:@"list.bullet" size:15 action:@selector(openPlaylist)];
    for (UIButton *b in @[_loopBtn, _prevBtn, _playBtn, _nextBtn, _listBtn]) [self addSubview:b];

    // ---------- 底部工具 ----------
    _deviceBtn   = [self iconButton:@"iphone" size:15 action:@selector(notReady:)];
    _lightBtn    = [self iconButton:@"lightbulb" size:15 action:@selector(notReady:)];
    _infoBtn     = [self iconButton:@"info.circle" size:15 action:@selector(notReady:)];
    _downloadBtn = [self iconButton:@"arrow.down.circle" size:15 action:@selector(notReady:)];
    _moreBtn     = [self iconButton:@"ellipsis" size:15 action:@selector(showMore)];
    _translateBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [_translateBtn setTitle:@"译" forState:UIControlStateNormal];
    _translateBtn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    [_translateBtn setTitleColor:NEColor(0xFFFFFF, 0.8) forState:UIControlStateNormal];
    _translateBtn.layer.borderWidth = 1;
    _translateBtn.layer.borderColor = NEColor(0xFFFFFF, 0.35).CGColor;
    _translateBtn.layer.cornerRadius = 9;
    [_translateBtn addTarget:self action:@selector(toggleTranslation) forControlEvents:UIControlEventTouchUpInside];
    for (UIButton *b in @[_deviceBtn, _lightBtn, _infoBtn, _downloadBtn, _moreBtn, _translateBtn]) [self addSubview:b];

    // ---------- 收起按钮 ----------
    _collapseBtn = [self iconButton:@"chevron.down" size:20 action:@selector(collapseTapped)];
    _collapseBtn.tintColor = NEColor(0xFFFFFF, 0.85);
    [self addSubview:_collapseBtn];

    // ---------- 歌词 ----------
    _lyricView = [[NELyricView alloc] initWithFrame:CGRectZero];
    _lyricView.delegate = self;
    _lyricView.showsTranslation = YES;
    [self addSubview:_lyricView];
}

- (void)setIcon:(NSString *)symbol for:(UIButton *)button size:(CGFloat)size {
    UIImage *img = [UIImage systemImageNamed:symbol
                           withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size
                                                                                               weight:UIImageSymbolWeightRegular]];
    [button setImage:img forState:UIControlStateNormal];
}

- (CGFloat)uiScale {
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat s;
    if (w >= 620) {
        s = MIN(w / 1000.0, h / 760.0);
    } else {
        // 竖屏按宽度放大，元素才能撑满
        s = w / 480.0;
    }
    return MIN(MAX(s, 0.85), 1.45);
}

- (void)applyUIScale:(CGFloat)s {
    _titleLabel.font = [UIFont systemFontOfSize:26 * s weight:UIFontWeightSemibold];
    _artistLabel.font = [UIFont systemFontOfSize:15 * s];
    _followBtn.titleLabel.font = [UIFont systemFontOfSize:10 * s weight:UIFontWeightMedium];
    _likeCountLabel.font = [UIFont systemFontOfSize:12 * s weight:UIFontWeightMedium];
    _commentCountLabel.font = _likeCountLabel.font;
    _timeNow.font = [UIFont monospacedDigitSystemFontOfSize:11 * s weight:UIFontWeightRegular];
    _timeTotal.font = _timeNow.font;
    _qualityLabel.font = [UIFont systemFontOfSize:10 * s];
    _translateBtn.titleLabel.font = [UIFont systemFontOfSize:11 * s weight:UIFontWeightSemibold];

    if (fabs(s - self.lastScale) < 0.02) return;
    self.lastScale = s;
    [self setIcon:@"repeat" for:_loopBtn size:15 * s];
    [self setIcon:@"backward.end.fill" for:_prevBtn size:20 * s];
    [self setIcon:@"pause.fill" for:_playBtn size:30 * s];
    [self setIcon:@"forward.end.fill" for:_nextBtn size:20 * s];
    [self setIcon:@"list.bullet" for:_listBtn size:15 * s];
    [self setIcon:@"iphone" for:_deviceBtn size:15 * s];
    [self setIcon:@"lightbulb" for:_lightBtn size:15 * s];
    [self setIcon:@"info.circle" for:_infoBtn size:15 * s];
    [self setIcon:@"arrow.down.circle" for:_downloadBtn size:15 * s];
    [self setIcon:@"ellipsis" for:_moreBtn size:15 * s];
    [self setIcon:@"chevron.down" for:_collapseBtn size:20 * s];
    [_progress setThumbImage:[self dotImageWithSize:11 * s color:UIColor.whiteColor]
                    forState:UIControlStateNormal];
    _lyricView.fontScale = s;
}

- (UIImage *)dotImageWithSize:(CGFloat)size color:(UIColor *)color {
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [color setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, size, size)] fill];
    }];
}

#pragma mark - 布局

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width;
    CGFloat H = self.bounds.size.height;
    CGFloat s = [self uiScale];
    [self applyUIScale:s];

    _coverBackdrop.frame = self.bounds;
    _coverBlur.frame = self.bounds;
    _shade.frame = self.bounds;

    BOOL wide = (W >= 620 && H >= 470);
    CGFloat margin = (wide ? 30.0 : 20.0);
    CGFloat bottomBarH = 36.0 * s;

    // 底部工具（随字号缩放）
    CGFloat by = H - bottomBarH;
    CGFloat bx = margin;
    CGFloat bottomGap = (wide ? 44.0 : 36.0) * s;
    CGFloat iconBox = 24.0 * s;
    for (UIButton *b in @[_deviceBtn, _lightBtn, _infoBtn, _downloadBtn, _moreBtn]) {
        b.frame = CGRectMake(bx, by + (bottomBarH - iconBox) / 2, iconBox, iconBox);
        bx += bottomGap;
    }
    CGFloat tw = 26.0 * s, th = 20.0 * s;
    _translateBtn.frame = CGRectMake(W - margin - tw, by + (bottomBarH - th) / 2, tw, th);
    _translateBtn.layer.cornerRadius = th / 2;

    CGFloat chevronS = 30 * s;
    _collapseBtn.frame = CGRectMake(wide ? margin - 4 : 8, wide ? margin - 6 : 8, chevronS, chevronS);

    if (wide) {
        CGFloat leftW = MIN(MAX(W * 0.52, 360), 680);
        CGFloat availH = H - margin * 2 - bottomBarH;
        CGFloat disc = MIN(leftW * 0.60, availH * 0.52);
        disc = MIN(MAX(disc, 140), 480);

        CGFloat infoW = leftW * 0.80;
        CGFloat titleH = 30 * s, gap1 = 6 * s, artistH = 18 * s, gap2 = 14 * s;
        CGFloat barH = 20 * s, gap3 = 22 * s, timeH = 14 * s, gap4 = 30 * s, ctrlH = 48 * s;
        CGFloat infoH = titleH + gap1 + artistH + gap2 + barH + gap3 + timeH + gap4 + ctrlH;
        CGFloat groupH = disc + 30 * s + infoH;
        CGFloat topY = MAX(margin, (H - bottomBarH - groupH) / 2);

        CGFloat discX = margin + (leftW - disc) / 2 - leftW * 0.05;
        [self placeVinylAt:CGPointMake(discX, topY) size:disc];

        CGFloat infoY = topY + disc + 30 * s;
        _titleLabel.textAlignment = NSTextAlignmentLeft;
        _titleLabel.frame = CGRectMake(margin, infoY, infoW - 10, titleH);
        _artistLabel.textAlignment = NSTextAlignmentLeft;
        _artistLabel.frame = CGRectMake(margin, infoY + titleH + gap1, infoW - 160 * s, artistH);
        _vipBadge.frame = CGRectMake(0, 0, 0, 0);
        _followBtn.frame = CGRectMake(MIN(CGRectGetMaxX(_artistLabel.frame) + 26 * s, margin + infoW - 170 * s),
                                      infoY + titleH + gap1 + (artistH - 20 * s) / 2, 48 * s, 20 * s);
        _followBtn.layer.cornerRadius = 10 * s;

        CGFloat likeS = 24 * s;
        CGFloat likeX = margin + infoW - 160 * s;
        _likeBtn.frame = CGRectMake(likeX, infoY + 8 * s, likeS, likeS);
        _likeCountLabel.frame = CGRectMake(likeX + 27 * s, infoY + 10 * s, 64 * s, 20 * s);
        CGFloat cmtX = margin + infoW - 44 * s;
        _commentBtn.frame = CGRectMake(cmtX, infoY + 8 * s, likeS, likeS);
        _commentCountLabel.hidden = NO;
        _commentCountLabel.frame = CGRectMake(cmtX + 27 * s, infoY + 10 * s, 52 * s, 20 * s);

        CGFloat barY = infoY + titleH + gap1 + artistH + gap2;
        _progress.frame = CGRectMake(margin, barY, infoW - 10, barH);
        _timeNow.frame = CGRectMake(margin, barY + barH + gap3, 52 * s, timeH);
        _timeTotal.frame = CGRectMake(margin + infoW - 10 - 52 * s, barY + barH + gap3, 52 * s, timeH);
        _qualityLabel.frame = CGRectMake(margin + (infoW - 10) / 2 - 44 * s, barY + (barH - 13 * s) / 2, 88 * s, 13 * s);

        CGFloat cy = barY + barH + gap3 + timeH + gap4;
        CGFloat cx = margin + (infoW - 10) / 2;
        CGFloat gap = 40 * s;
        CGFloat loopS = 30 * s, navS = 32 * s, playS = 48 * s, listS = 30 * s;
        CGFloat clusterW = loopS + navS + playS + navS + listS + gap * 4;
        CGFloat sx = cx - clusterW / 2;
        _loopBtn.frame = CGRectMake(sx, cy - loopS / 2, loopS, loopS);
        _prevBtn.frame = CGRectMake(sx + loopS + gap, cy - navS / 2, navS, navS);
        _playBtn.frame = CGRectMake(sx + loopS + gap + navS + gap, cy - playS / 2, playS, playS);
        _nextBtn.frame = CGRectMake(sx + loopS + gap + navS + gap + playS + gap, cy - navS / 2, navS, navS);
        _listBtn.frame = CGRectMake(sx + clusterW - listS, cy - listS / 2, listS, listS);

        CGFloat lyricX = margin + leftW + 10;
        CGFloat lyricW = W - lyricX - margin;
        _lyricView.hidden = NO;
        _lyricView.frame = CGRectMake(lyricX, margin, MAX(160, lyricW), H - margin * 2 - bottomBarH);
    } else {
        CGFloat titleH = 30 * s, gap1 = 4 * s, artistH = 18 * s, gap2 = 14 * s;
        CGFloat barH = 18 * s, gap3 = 20 * s, timeH = 13 * s, gap4 = 28 * s, ctrlH = 48 * s;
        CGFloat infoH = titleH + gap1 + artistH + gap2 + barH + gap3 + timeH + gap4 + ctrlH;

        CGFloat topY = margin + 6 * s;
        CGFloat availH = H - bottomBarH - topY - 10 * s;
        CGFloat maxDisc = availH - infoH - 56 * s;
        CGFloat disc = MIN(W * 0.72, maxDisc);
        disc = MIN(MAX(disc, 110), 420);
        CGFloat discX = (W - disc) / 2;
        [self placeVinylAt:CGPointMake(discX, topY) size:disc];

        CGFloat infoY = topY + disc + 22 * s;
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.frame = CGRectMake(margin, infoY, W - margin * 2 - 124 * s, titleH);
        _artistLabel.textAlignment = NSTextAlignmentCenter;
        _artistLabel.frame = CGRectMake(margin, infoY + titleH + gap1, W - margin * 2 - 124 * s, artistH);
        _vipBadge.frame = CGRectMake(W - margin - 30 * s, infoY + titleH + gap1, 26 * s, 13 * s);
        _followBtn.frame = CGRectMake(W / 2 + 34 * s, infoY + titleH + gap1 + (artistH - 20 * s) / 2, 48 * s, 20 * s);
        _followBtn.layer.cornerRadius = 10 * s;

        CGFloat likeS = 24 * s;
        _likeBtn.frame = CGRectMake(W - margin - 104 * s, infoY + 3 * s, likeS, likeS);
        _likeCountLabel.frame = CGRectMake(W - margin - 78 * s, infoY + 4 * s, 64 * s, 20 * s);
        _commentBtn.frame = CGRectMake(W - margin - 26 * s, infoY + 3 * s, likeS, likeS);
        _commentCountLabel.hidden = YES;

        CGFloat barY = infoY + titleH + gap1 + artistH + gap2;
        _progress.frame = CGRectMake(margin, barY, W - margin * 2, barH);
        _timeNow.frame = CGRectMake(margin, barY + barH + gap3, 52 * s, timeH);
        _timeTotal.frame = CGRectMake(W - margin - 52 * s, barY + barH + gap3, 52 * s, timeH);
        _qualityLabel.frame = CGRectMake(W / 2 - 44 * s, barY + (barH - 13 * s) / 2, 88 * s, 13 * s);

        CGFloat cy = barY + barH + gap3 + timeH + gap4;
        CGFloat cx = W / 2;
        CGFloat gap = 30 * s;
        CGFloat loopS = 30 * s, navS = 30 * s, playS = 46 * s, listS = 30 * s;
        CGFloat clusterW = loopS + navS + playS + navS + listS + gap * 4;
        CGFloat sx = cx - clusterW / 2;
        _loopBtn.frame = CGRectMake(sx, cy - loopS / 2, loopS, loopS);
        _prevBtn.frame = CGRectMake(sx + loopS + gap, cy - navS / 2, navS, navS);
        _playBtn.frame = CGRectMake(sx + loopS + gap + navS + gap, cy - playS / 2, playS, playS);
        _nextBtn.frame = CGRectMake(sx + loopS + gap + navS + gap + playS + gap, cy - navS / 2, navS, navS);
        _listBtn.frame = CGRectMake(sx + clusterW - listS, cy - listS / 2, listS, listS);

        CGFloat lyricTop = cy + 24 * s;
        CGFloat lyricH = H - lyricTop - bottomBarH - 8;
        _lyricView.hidden = (lyricH < 44);
        _lyricView.frame = CGRectMake(0, lyricTop, W, MAX(0, lyricH));
    }
}

- (void)placeVinylAt:(CGPoint)origin size:(CGFloat)size {
    _vinylBox.frame = CGRectMake(origin.x, origin.y, size, size);
    _discBase.frame = CGRectMake(0, 0, size, size);
    _discBase.layer.cornerRadius = size / 2;

    CGFloat ring = size * 0.86;
    _discRing.frame = CGRectMake((size - ring) / 2, (size - ring) / 2, ring, ring);
    _discRing.layer.cornerRadius = ring / 2;

    CGFloat cover = size * 0.62;
    _discCover.frame = CGRectMake((size - cover) / 2, (size - cover) / 2, cover, cover);
    _discCover.layer.cornerRadius = cover / 2;

    _centerDot.frame = CGRectMake(size / 2 - 2.5, size / 2 - 2.5, 5, 5);
    _centerDot.layer.cornerRadius = 2.5;

    CGFloat armW = size * 0.58;
    _armBox.frame = CGRectMake(size * 0.30, -size * 0.06, armW, 20);
    _armBox.transform = CGAffineTransformMakeRotation(M_PI / 10);
    _tonearm.frame = CGRectMake(0, 8, armW, 3);
    _tonearmHead.frame = CGRectMake(armW - 8, 2, 12, 12);
    _tonearmHead.layer.cornerRadius = 6;
}

#pragma mark - 通知

- (void)observe {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(onState) name:NEPlayerStateChangedNotification object:nil];
    [nc addObserver:self selector:@selector(onTrack) name:NEPlayerTrackChangedNotification object:nil];
    [nc addObserver:self selector:@selector(onProgress) name:NEPlayerProgressNotification object:nil];
}

- (void)onState { [self refresh]; }

- (void)onTrack {
    self.likedSongID = nil;
    self.commentTotal = 0;
    self.likeCount = 0;
    [self loadLyricForCurrentSong];
    [self loadCommentCount];
    [self loadLikeState];
    [self refresh];
}

- (void)onProgress {
    NEPlayer *p = [NEPlayer shared];
    self.lyricView.playing = p.isPlaying;
    self.lyricView.currentTime = p.currentTime;
    if (!self.userSeeking) {
        _progress.value = p.currentTime;
        _timeNow.text = [self formatTime:p.currentTime];
        if (p.duration > 0) {
            _progress.maximumValue = MAX(1.0, p.duration);
            _timeTotal.text = [self formatTime:p.duration];
        }
    }
    if (p.isPlaying && !self.spinning) [self startVinyl];
    if (!p.isPlaying && self.spinning) [self stopVinyl];
}

- (void)refresh {
    NEPlayer *p = [NEPlayer shared];
    NESong *song = p.currentSong;

    _titleLabel.text = song.name.length ? song.name : @"未在播放";
    _artistLabel.text = song.artist ?: @"";
    _vipBadge.hidden = !song.vipOnly;

    BOOL playing = p.isPlaying;
    [_playBtn setImage:[UIImage systemImageNamed:(playing ? @"pause.fill" : @"play.fill")] forState:UIControlStateNormal];
    [self updateLoopIcon];
    [self updateLikeButton];
    [self updateCommentCount];

    _progress.maximumValue = MAX(1.0, p.duration);
    if (!self.userSeeking) {
        _progress.value = p.currentTime;
        _timeNow.text = [self formatTime:p.currentTime];
    }
    _timeTotal.text = [self formatTime:p.duration];

    [self loadCoverIfNeeded:song];

    self.lyricView.playing = playing;
    if (playing && !self.spinning) [self startVinyl];
    if (!playing && self.spinning) [self stopVinyl];
}

- (void)updateLoopIcon {
    NSInteger mode = [NEPlayer shared].playMode;
    NSString *symbol = @"repeat";
    if (mode == NEPlayModeSingleLoop) symbol = @"repeat.1";
    else if (mode == NEPlayModeShuffle) symbol = @"shuffle";
    else if (mode == NEPlayModeSequential) symbol = @"arrow.right";
    [_loopBtn setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
}

- (NSString *)formatCount:(NSInteger)n {
    if (n <= 0) return @"";
    if (n >= 1000000) return [NSString stringWithFormat:@"%ldw+", (long)(n / 10000)];
    if (n >= 10000) return [NSString stringWithFormat:@"%.1fw", n / 10000.0];
    return [NSString stringWithFormat:@"%ld", (long)n];
}

- (void)updateLikeButton {
    BOOL liked = self.likedSongID.length &&
        [self.likedSongID isEqualToString:[NEPlayer shared].currentSong.songID];
    [_likeBtn setImage:[UIImage systemImageNamed:(liked ? @"heart.fill" : @"heart")]
              forState:UIControlStateNormal];
    _likeBtn.tintColor = liked ? NEColor(0xFA3B3B, 1.0) : NEColor(0xFFFFFF, 0.85);
    _likeCountLabel.text = [self formatCount:self.likeCount];
}

- (void)updateCommentCount {
    _commentCountLabel.text = [self formatCount:self.commentTotal];
}

#pragma mark - 黑胶旋转

- (void)startVinyl {
    if (self.spinning) return;
    self.spinning = YES;
    CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    spin.fromValue = @(0);
    spin.toValue = @(M_PI * 2);
    spin.duration = 26;
    spin.repeatCount = HUGE_VALF;
    spin.removedOnCompletion = NO;
    [_discCover.layer addAnimation:spin forKey:@"spin"];
}

- (void)stopVinyl {
    if (!self.spinning) return;
    self.spinning = NO;
    [_discCover.layer removeAnimationForKey:@"spin"];
}

#pragma mark - 歌词 / 封面

- (void)loadLyricForCurrentSong {
    NESong *song = [NEPlayer shared].currentSong;
    self.loadedSongID = song.songID;
    self.lyric = nil;
    self.lyricView.lyric = nil;
    if (!song) return;

    __weak typeof(self) weakSelf = self;
    [[NEApi shared] fetchLyricForSong:song complete:^(NELyric *lyric, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (![self.loadedSongID isEqualToString:song.songID]) return;
        self.lyric = lyric;
        self.lyricView.lyric = lyric;
        self.lyricView.playing = [NEPlayer shared].isPlaying;
        self.lyricView.currentTime = [NEPlayer shared].currentTime;
    }];
}

- (void)loadCoverIfNeeded:(NESong *)song {
    NSString *url = song.coverURL;
    if (!url.length) {
        _discCover.image = nil;
        _coverBackdrop.image = nil;
        return;
    }
    if ([self.coverURLString isEqualToString:url] && _discCover.image) return;
    self.coverURLString = url;

    UIImage *cached = [[NEImageCache shared] imageForKey:url];
    if (cached) { [self applyCover:cached]; return; }

    __weak typeof(self) weakSelf = self;
    [[NEImageCache shared] loadImageWithURL:url completion:^(UIImage *img) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (![self.coverURLString isEqualToString:url]) return;
        if (img) [self applyCover:img];
    }];
}

- (void)applyCover:(UIImage *)img {
    _discCover.image = img;
    _coverBackdrop.image = img;
}

#pragma mark - 操作

- (void)toggle {
    NEPlayer *p = [NEPlayer shared];
    if (!p.currentSong) return;
    [p togglePlayPause];
    [self refresh];
}

- (void)prev { [[NEPlayer shared] previous]; }
- (void)next { [[NEPlayer shared] next]; }

- (void)cycleLoop {
    NEPlayer *p = [NEPlayer shared];
    [p cyclePlayMode];
    [self updateLoopIcon];
    NSString *name = @"列表循环";
    switch (p.playMode) {
        case NEPlayModeSingleLoop: name = @"单曲循环"; break;
        case NEPlayModeShuffle: name = @"随机播放"; break;
        case NEPlayModeSequential: name = @"顺序播放"; break;
        default: name = @"列表循环"; break;
    }
    [self presentAlert:@"播放模式" message:name];
}

- (void)openPlaylist {
    NEPlaylistSheet *sheet = [NEPlaylistSheet new];
    sheet.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        sheet.sheetPresentationController.detents = @[
            [UISheetPresentationControllerDetent mediumDetent],
            [UISheetPresentationControllerDetent largeDetent],
        ];
    }
    UIViewController *host = [self topMostVC];
    if (host) [host presentViewController:sheet animated:YES completion:nil];
}

- (void)collapseTapped {
    if (self.onCollapse) self.onCollapse();
}

- (void)followArtist {
    [self presentAlert:@"关注歌手" message:@"歌手页还没接，先用搜索找 TA 的歌"];
}

- (void)toggleTranslation {
    self.showsTranslation = !self.showsTranslation;
    self.lyricView.showsTranslation = self.showsTranslation;
    [_translateBtn setTitleColor:(self.showsTranslation ? NEColor(0xFFFFFF, 0.85) : NEColor(0xFFFFFF, 0.35))
                        forState:UIControlStateNormal];
}

- (void)notReady:(UIButton *)sender {
    [self presentAlert:@"暂未接入" message:@"这个入口还没接"];
}

- (void)showMore {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"更多"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"分享" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        NESong *song = [NEPlayer shared].currentSong;
        NSString *text = [NSString stringWithFormat:@"%@ - %@", song.name ?: @"", song.artist ?: @""];
        UIActivityViewController *vc = [[UIActivityViewController alloc]
            initWithActivityItems:@[text] applicationActivities:nil];
        vc.popoverPresentationController.sourceView = self;
        vc.popoverPresentationController.sourceRect = self.bounds;
        UIViewController *host = [self topMostVC];
        if (host) [host presentViewController:vc animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"清空播放列表" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *a) {
        [[NEPlayer shared] clearQueue];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self;
    sheet.popoverPresentationController.sourceRect = self.bounds;
    UIViewController *host = [self topMostVC];
    if (host) [host presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - 喜欢 / 评论

- (void)loadLikeState {
    NESong *song = [NEPlayer shared].currentSong;
    if (!song.songID.length || ![[NEApi shared] isLoggedIn]) return;
    __weak typeof(self) weakSelf = self;
    [[NEApi shared] fetchSongLikeState:song.songID complete:^(NSInteger count, BOOL liked, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || error) return;
        self.likeCount = count;
        if (liked) self.likedSongID = song.songID;
        [self updateLikeButton];
    }];
}

- (void)toggleLike {
    NESong *song = [NEPlayer shared].currentSong;
    if (!song.songID.length) return;
    if (![[NEApi shared] isLoggedIn]) {
        [self presentAlert:@"请先登录" message:@"喜欢歌曲需要登录"];
        return;
    }
    BOOL willLike = ![self.likedSongID isEqualToString:song.songID];
    __weak typeof(self) weakSelf = self;
    [[NEApi shared] likeSongID:song.songID liked:willLike complete:^(BOOL ok, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (!ok) {
            [self presentAlert:@"操作失败" message:error.localizedDescription];
            return;
        }
        self.likedSongID = willLike ? song.songID : nil;
        self.likeCount = MAX(0, self.likeCount + (willLike ? 1 : -1));
        [self updateLikeButton];
    }];
}

- (void)loadCommentCount {
    NESong *song = [NEPlayer shared].currentSong;
    if (!song.songID.length) return;
    __weak typeof(self) weakSelf = self;
    [[NEApi shared] fetchCommentsForSongID:song.songID limit:1
                                complete:^(NSArray<NSDictionary *> *comments, NSInteger total, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.commentTotal = total;
        [self updateCommentCount];
    }];
}

- (void)showComments {
    NESong *song = [NEPlayer shared].currentSong;
    if (!song.songID.length) return;
    __weak typeof(self) weakSelf = self;
    [[NEApi shared] fetchCommentsForSongID:song.songID limit:30
                                complete:^(NSArray<NSDictionary *> *comments, NSInteger total, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self presentComments:comments error:error];
    }];
}

- (void)presentComments:(NSArray<NSDictionary *> *)comments error:(NSError *)error {
    NSMutableString *text = [NSMutableString string];
    for (NSDictionary *c in comments) {
        if (![c isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *user = [c[@"user"] isKindOfClass:[NSDictionary class]] ? c[@"user"] : nil;
        NSString *name = [user[@"nickname"] isKindOfClass:[NSString class]] ? user[@"nickname"] : @"匿名用户";
        NSString *content = [c[@"content"] isKindOfClass:[NSString class]] ? c[@"content"] : @"";
        NSNumber *liked = [c[@"likedCount"] isKindOfClass:[NSNumber class]] ? c[@"likedCount"] : @0;
        [text appendFormat:@"%@  ♡%ld\n%@\n\n", name, (long)[liked integerValue], content];
    }
    if (!text.length) [text appendString:(error.localizedDescription ?: @"暂无评论")];

    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = NE_BG;
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;

    UITextView *tv = [[UITextView alloc] initWithFrame:vc.view.bounds];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.editable = NO;
    tv.backgroundColor = UIColor.clearColor;
    tv.textColor = NE_TEXT;
    tv.font = [UIFont systemFontOfSize:13];
    tv.text = text;
    tv.contentInset = UIEdgeInsetsMake(60, 16, 24, 16);
    [vc.view addSubview:tv];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"关闭" forState:UIControlStateNormal];
    close.frame = CGRectMake(vc.view.bounds.size.width - 76, 46, 64, 34);
    close.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [close addTarget:self action:@selector(dismissComments) forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:close];

    self.commentsVC = vc;
    UIViewController *host = [self topMostVC];
    if (host) [host presentViewController:vc animated:YES completion:nil];
}

- (void)dismissComments {
    [self.commentsVC dismissViewControllerAnimated:YES completion:nil];
    self.commentsVC = nil;
}

#pragma mark - 工具

- (void)sliderTouchDown { self.userSeeking = YES; }
- (void)sliderChanged { _timeNow.text = [self formatTime:self.progress.value]; }
- (void)sliderTouchUp {
    self.userSeeking = NO;
    [[NEPlayer shared] seekTo:self.progress.value];
}

- (NSString *)formatTime:(double)s {
    if (!isfinite(s) || s < 0) s = 0;
    int total = (int)lround(s);
    return [NSString stringWithFormat:@"%02d:%02d", total / 60, total % 60];
}

- (UIViewController *)topMostVC {
    UIWindow *window = self.window;
    if (!window) return nil;
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

- (void)presentAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    UIViewController *host = [self topMostVC];
    if (host) [host presentViewController:alert animated:YES completion:nil];
}

#pragma mark - NELyricViewDelegate

- (void)lyricView:(id)view didSeekToTime:(double)time {
    [[NEPlayer shared] seekTo:time];
    [self refresh];
}

@end
