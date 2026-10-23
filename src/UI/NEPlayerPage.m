#import "NEPlayerPage.h"
#import "NEUITheme.h"
#import "NEPlayer.h"
#import "NEApi.h"
#import "NELyricView.h"

@interface NEPlayerPage () <NELyricViewDelegate>
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UIVisualEffectView *coverBlur;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;
@property (nonatomic, strong) NELyricView *lyricView;
@property (nonatomic, strong) UISlider *progress;
@property (nonatomic, strong) UILabel *timeNow;
@property (nonatomic, strong) UILabel *timeTotal;
@property (nonatomic, strong) UIButton *playBtn;
@property (nonatomic, strong) UIButton *prevBtn;
@property (nonatomic, strong) UIButton *nextBtn;
@property (nonatomic, strong) UIButton *modeBtn;

@property (nonatomic, strong) NELyric *lyric;
@property (nonatomic, assign) BOOL showsTranslation;
@property (nonatomic, assign) BOOL userSeeking;
@property (nonatomic, strong) NESong *loadedSong;
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

- (void)build {
    // 背景：封面高斯模糊，营造网易云的沉浸感
    _coverBlur = [[UIVisualEffectView alloc] initWithEffect:
                  [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    _coverBlur.alpha = 0.55;
    _coverBlur.userInteractionEnabled = NO;
    [self addSubview:_coverBlur];

    _cover = [[UIImageView alloc] initWithFrame:CGRectZero];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerRadius = 12;
    _cover.layer.cornerCurve = kCACornerCurveContinuous;
    _cover.backgroundColor = NE_CARD;
    [self addSubview:_cover];

    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    _titleLabel.textColor = NE_TEXT;
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:_titleLabel];

    _artistLabel = [UILabel new];
    _artistLabel.font = [UIFont systemFontOfSize:12];
    _artistLabel.textColor = NE_TEXT_DIM;
    _artistLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_artistLabel];

    _lyricView = [[NELyricView alloc] initWithFrame:CGRectZero];
    _lyricView.delegate = self;
    _lyricView.showsTranslation = YES;
    [self addSubview:_lyricView];

    _progress = [[UISlider alloc] initWithFrame:CGRectZero];
    _progress.minimumTrackTintColor = NE_BRAND;
    _progress.maximumTrackTintColor = NEColor(0xFFFFFF, 0.18);
    [_progress addTarget:self action:@selector(sliderTouchDown)
        forControlEvents:UIControlEventTouchDown];
    [_progress addTarget:self action:@selector(sliderChanged)
        forControlEvents:UIControlEventValueChanged];
    [_progress addTarget:self action:@selector(sliderTouchUp)
        forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self addSubview:_progress];

    _timeNow = [UILabel new];
    _timeNow.font = [UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightRegular];
    _timeNow.textColor = NE_TEXT_DIM;
    _timeNow.text = @"0:00";
    [self addSubview:_timeNow];

    _timeTotal = [UILabel new];
    _timeTotal.font = [UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightRegular];
    _timeTotal.textColor = NE_TEXT_DIM;
    _timeTotal.text = @"0:00";
    _timeTotal.textAlignment = NSTextAlignmentRight;
    [self addSubview:_timeTotal];

    _prevBtn   = [self controlButton:@"⏮" size:22 action:@selector(prev)];
    _playBtn   = [self controlButton:@"▶" size:30 action:@selector(toggle)];
    _nextBtn   = [self controlButton:@"⏭" size:22 action:@selector(next)];
    _modeBtn   = [self controlButton:@"🔁" size:14 action:@selector(toggleTranslation)];
    _modeBtn.titleLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightSemibold];
    [_modeBtn setTitle:@"译" forState:UIControlStateNormal];
    _modeBtn.layer.borderWidth = 1;
    _modeBtn.layer.borderColor = NEColor(0xFFFFFF, 0.22).CGColor;
    _modeBtn.layer.cornerRadius = 12;
    _modeBtn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];

    for (UIButton *b in @[_prevBtn, _playBtn, _nextBtn, _modeBtn]) [self addSubview:b];
}

- (UIButton *)controlButton:(NSString *)title size:(CGFloat)size action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:NE_TEXT forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:size weight:UIFontWeightMedium];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

#pragma mark - 布局（iPad 关键）

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width;
    CGFloat H = self.bounds.size.height;
    _coverBlur.frame = self.bounds;

    // iPad / 宽屏：封面在左，歌词在右
    BOOL wide = (W >= 560);

    CGFloat top = 8;
    CGFloat textBlock = 44;
    CGFloat bottom = 96;

    if (wide) {
        CGFloat coverSize = MIN(W * 0.42, H - textBlock - bottom - 24);
        coverSize = MAX(140, coverSize);
        _cover.frame = CGRectMake(24, (H - coverSize) / 2 - 10, coverSize, coverSize);
        CGFloat lyricX = CGRectGetMaxX(_cover.frame) + 20;
        CGFloat lyricW = W - lyricX - 24;
        _lyricView.frame = CGRectMake(lyricX, top + 8, lyricW, H - bottom - top - 16);
        _titleLabel.frame = CGRectMake(24, _lyricView.frame.origin.y + _lyricView.bounds.size.height - 40, W - 48, 20);
        _artistLabel.frame = CGRectMake(24, _titleLabel.frame.origin.y + 20, W - 48, 16);
        // 标题覆盖在歌词下方可能冲突，宽屏时把歌曲信息挪到封面上方
        _titleLabel.frame = CGRectMake(24, CGRectGetMinY(_cover.frame) - 48, W - 48, 20);
        _artistLabel.frame = CGRectMake(24, CGRectGetMinY(_cover.frame) - 26, W - 48, 16);
    } else {
        CGFloat coverSize = MIN(W - 100, 132);
        _cover.frame = CGRectMake((W - coverSize) / 2, top + 6, coverSize, coverSize);
        _titleLabel.frame = CGRectMake(20, CGRectGetMaxY(_cover.frame) + 8, W - 40, 20);
        _artistLabel.frame = CGRectMake(20, CGRectGetMaxY(_titleLabel.frame) + 1, W - 40, 16);
        CGFloat lyricTop = CGRectGetMaxY(_artistLabel.frame) + 6;
        _lyricView.frame = CGRectMake(0, lyricTop, W, MAX(40, H - bottom - lyricTop));
    }

    CGFloat barY = H - bottom + 6;
    _progress.frame = CGRectMake(20, barY, W - 40, 20);
    _timeNow.frame = CGRectMake(20, barY + 18, 46, 12);
    _timeTotal.frame = CGRectMake(W - 66, barY + 18, 46, 12);

    CGFloat cy = barY + 52;
    CGFloat cx = W / 2;
    _prevBtn.frame = CGRectMake(cx - 88, cy - 16, 44, 32);
    _playBtn.frame = CGRectMake(cx - 22, cy - 22, 44, 44);
    _nextBtn.frame = CGRectMake(cx + 44, cy - 16, 44, 32);
    _modeBtn.frame = CGRectMake(W - 46, cy - 14, 24, 24);
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

- (void)toggleTranslation {
    self.showsTranslation = !self.showsTranslation;
    self.lyricView.showsTranslation = self.showsTranslation;
    [_modeBtn setTitleColor:(self.showsTranslation ? NE_TEXT : NE_TEXT_DIM) forState:UIControlStateNormal];
    [_modeBtn setTitle:(self.showsTranslation ? @"译" : @"原") forState:UIControlStateNormal];
}

- (void)sliderTouchDown { self.userSeeking = YES; }
- (void)sliderChanged {
    _timeNow.text = [self formatTime:self.progress.value];
}
- (void)sliderTouchUp {
    self.userSeeking = NO;
    [[NEPlayer shared] seekTo:self.progress.value];
}

- (NSString *)formatTime:(double)s {
    if (!isfinite(s) || s < 0) s = 0;
    int total = (int)lround(s);
    return [NSString stringWithFormat:@"%d:%02d", total / 60, total % 60];
}

#pragma mark - 数据

- (void)observe {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(onState) name:NEPlayerStateChangedNotification object:nil];
    [nc addObserver:self selector:@selector(onTrack) name:NEPlayerTrackChangedNotification object:nil];
}

- (void)onState {
    [self refresh];
    // 歌词随时间滚动
    NEPlayer *p = [NEPlayer shared];
    if (self.lyric) {
        self.lyricView.currentTime = p.currentTime;
    }
}

- (void)onTrack {
    [self loadLyricForCurrentSong];
    [self refresh];
}

- (void)loadLyricForCurrentSong {
    NESong *song = [NEPlayer shared].currentSong;
    self.loadedSong = song;
    self.lyric = nil;
    self.lyricView.lyric = nil;

    if (!song) return;
    __weak typeof(self) weakSelf = self;
    [[NEApi shared] fetchLyricForSong:song complete:^(NELyric *lyric, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        // 切歌过快时丢弃过期回调
        if (![self.loadedSong.songID isEqualToString:song.songID]) return;
        self.lyric = lyric;
        self.lyricView.lyric = lyric;
        self.lyricView.currentTime = [NEPlayer shared].currentTime;
    }];
}

- (void)refresh {
    NEPlayer *p = [NEPlayer shared];
    NESong *s = p.currentSong;
    _titleLabel.text = s.name.length ? s.name : @"未在播放";
    _artistLabel.text = s.artist ?: @"";

    BOOL playing = p.isPlaying;
    [_playBtn setTitle:(playing ? @"❚❚" : @"▶") forState:UIControlStateNormal];

    _progress.maximumValue = MAX(1.0, p.duration);
    if (!self.userSeeking) {
        _progress.value = p.currentTime;
        _timeNow.text = [self formatTime:p.currentTime];
    }
    _timeTotal.text = [self formatTime:p.duration];

    [self loadCoverIfNeeded:s];
}

- (void)loadCoverIfNeeded:(NESong *)song {
    if (!song.coverURL.length) { _cover.image = nil; return; }
    static NSString *lastURL = nil;
    if ([lastURL isEqualToString:song.coverURL]) return;
    lastURL = song.coverURL;

    __weak typeof(self) weakSelf = self;
    NSURL *u = [NSURL URLWithString:song.coverURL];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSData *d = [NSData dataWithContentsOfURL:u];
        UIImage *img = d ? [UIImage imageWithData:d] : nil;
        if (!img) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [UIView transitionWithView:self.cover duration:0.25
                               options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:^{ self.cover.image = img; } completion:nil];
        });
    });
}

#pragma mark - NELyricViewDelegate

- (void)lyricView:(id)view didSeekToTime:(double)time {
    [[NEPlayer shared] seekTo:time];
    [self refresh];
}

@end