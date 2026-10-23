#import "NEPlayerPage.h"
#import "NEUITheme.h"
#import "NEPlayer.h"
#import "NEApi.h"
#import "NELyricView.h"
#import "NEImageCache.h"

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
@property (nonatomic, strong) UIButton *likeBtn;
@property (nonatomic, strong) UIButton *commentBtn;
/// 当前这首歌是否已喜欢（本地点亮用）
@property (nonatomic, copy, nullable) NSString *likedSongID;
@property (nonatomic, strong, nullable) UIViewController *commentsVC;
@property (nonatomic, copy) NSString *coverURLString;
@property (nonatomic, strong) UIImageView *coverBlurBackdrop;
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
    // 模糊封面铺满整个播放页，营造网易云的沉浸感
    _coverBlurBackdrop = [[UIImageView alloc] initWithFrame:CGRectZero];
    _coverBlurBackdrop.contentMode = UIViewContentModeScaleAspectFill;
    _coverBlurBackdrop.clipsToBounds = YES;
    _coverBlurBackdrop.alpha = 0.35;
    [self addSubview:_coverBlurBackdrop];

    _coverBlur = [[UIVisualEffectView alloc] initWithEffect:
                  [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    _coverBlur.alpha = 0.72;
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

    _likeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [_likeBtn setImage:[UIImage systemImageNamed:@"heart"] forState:UIControlStateNormal];
    _likeBtn.tintColor = NE_TEXT_DIM;
    [_likeBtn addTarget:self action:@selector(toggleLike) forControlEvents:UIControlEventTouchUpInside];

    _commentBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [_commentBtn setImage:[UIImage systemImageNamed:@"text.bubble"] forState:UIControlStateNormal];
    _commentBtn.tintColor = NE_TEXT_DIM;
    [_commentBtn addTarget:self action:@selector(showComments) forControlEvents:UIControlEventTouchUpInside];

    for (UIButton *b in @[_prevBtn, _playBtn, _nextBtn, _modeBtn, _likeBtn, _commentBtn]) [self addSubview:b];
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
    _coverBlurBackdrop.frame = self.bounds;
    _coverBlur.frame = self.bounds;

    // iPad / 宽屏：左封面 + 右歌词；窄屏：上图下词
    BOOL wide = (W >= 560);
    CGFloat bottom = 92;          // 进度 + 控制区高度
    CGFloat topPad = 10;

    if (wide) {
        CGFloat infoH = 46;       // 标题 + 艺术家
        CGFloat coverSize = MIN(W * 0.38, H - bottom - infoH - 28);
        coverSize = MAX(120, coverSize);

        _cover.frame = CGRectMake(24, topPad + infoH, coverSize, coverSize);

        _titleLabel.textAlignment = NSTextAlignmentLeft;
        _artistLabel.textAlignment = NSTextAlignmentLeft;
        _titleLabel.frame = CGRectMake(24, topPad, coverSize, 22);
        _artistLabel.frame = CGRectMake(24, topPad + 22, coverSize, 16);

        CGFloat lyricX = CGRectGetMaxX(_cover.frame) + 24;
        CGFloat lyricW = W - lyricX - 20;
        CGFloat lyricY = topPad;
        CGFloat lyricH = H - bottom - topPad - 8;
        _lyricView.frame = CGRectMake(lyricX, lyricY, lyricW, MAX(80, lyricH));
    } else {
        CGFloat coverSize = MIN(W - 110, 128);
        _cover.frame = CGRectMake((W - coverSize) / 2, topPad, coverSize, coverSize);

        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _artistLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.frame = CGRectMake(20, CGRectGetMaxY(_cover.frame) + 6, W - 40, 20);
        _artistLabel.frame = CGRectMake(20, CGRectGetMaxY(_titleLabel.frame) + 1, W - 40, 16);

        CGFloat lyricTop = CGRectGetMaxY(_artistLabel.frame) + 6;
        _lyricView.frame = CGRectMake(0, lyricTop, W, MAX(50, H - bottom - lyricTop));
    }

    // 进度条 + 时间
    CGFloat barY = H - bottom + 2;
    _progress.frame = CGRectMake(20, barY, W - 40, 20);
    _timeNow.frame = CGRectMake(20, barY + 18, 46, 12);
    _timeTotal.frame = CGRectMake(W - 66, barY + 18, 46, 12);

    // 控制按钮
    CGFloat cy = barY + 52;
    CGFloat cx = W / 2;
    _prevBtn.frame = CGRectMake(cx - 92, cy - 16, 44, 32);
    _playBtn.frame = CGRectMake(cx - 24, cy - 24, 48, 48);
    _nextBtn.frame = CGRectMake(cx + 48, cy - 16, 44, 32);
    _modeBtn.frame = CGRectMake(W - 44, cy - 12, 24, 24);
    // 喜欢 / 评论：放在进度条右上方
    _likeBtn.frame = CGRectMake(W - 76, barY - 32, 28, 28);
    _commentBtn.frame = CGRectMake(W - 42, barY - 32, 28, 28);
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
    // 进度单独通知（约 20Hz），只推进歌词，不做全量 UI 刷新
    [nc addObserver:self selector:@selector(onProgress) name:NEPlayerProgressNotification object:nil];
}

- (void)onState {
    [self refresh];
}

- (void)onProgress {
    NEPlayer *p = [NEPlayer shared];
    // 让歌词视图按 60fps 插值推进
    self.lyricView.playing = p.isPlaying;
    self.lyricView.currentTime = p.currentTime;
    // 进度条与时间文本跟着走（不重建视图）
    if (!self.userSeeking) {
        _progress.value = p.currentTime;
        _timeNow.text = [self formatTime:p.currentTime];
        if (p.duration > 0) {
            _progress.maximumValue = MAX(1.0, p.duration);
            _timeTotal.text = [self formatTime:p.duration];
        }
    }
}

- (void)onTrack {
    self.likedSongID = nil;          // 换歌后喜欢状态未知，先熄灭
    [self updateLikeButton];
    [self loadLyricForCurrentSong];
    [self refresh];
}

- (void)updateLikeButton {
    BOOL liked = self.likedSongID.length &&
        [self.likedSongID isEqualToString:[NEPlayer shared].currentSong.songID];
    [_likeBtn setImage:[UIImage systemImageNamed:(liked ? @"heart.fill" : @"heart")]
              forState:UIControlStateNormal];
    _likeBtn.tintColor = liked ? NE_BRAND : NE_TEXT_DIM;
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
        [self updateLikeButton];
    }];
}

- (void)showComments {
    NESong *song = [NEPlayer shared].currentSong;
    if (!song.songID.length) return;
    __weak typeof(self) weakSelf = self;
    [[NEApi shared] fetchCommentsForSongID:song.songID limit:30
                                complete:^(NSArray<NSDictionary *> *comments, NSError *error) {
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

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 52, vc.view.bounds.size.width, 22)];
    title.text = @"评论";
    title.textColor = NE_TEXT;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [vc.view addSubview:title];

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
        self.lyricView.playing = [NEPlayer shared].isPlaying;
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
    self.lyricView.playing = playing;

    _progress.maximumValue = MAX(1.0, p.duration);
    if (!self.userSeeking) {
        _progress.value = p.currentTime;
        _timeNow.text = [self formatTime:p.currentTime];
    }
    _timeTotal.text = [self formatTime:p.duration];

    [self loadCoverIfNeeded:s];
}

- (void)loadCoverIfNeeded:(NESong *)song {
    NSString *url = song.coverURL;
    if (!url.length) {
        _cover.image = nil;
        return;
    }
    // 同一首歌不重复加载；比原来的 static 全局变量更安全（支持多实例/切歌）
    if ([self.coverURLString isEqualToString:url] && _cover.image) return;
    self.coverURLString = url;

    // 命中内存缓存直接上
    UIImage *cached = [[NEImageCache shared] imageForKey:url];
    if (cached) { [self applyCover:cached]; return; }

    __weak typeof(self) weakSelf = self;
    [[NEImageCache shared] loadImageWithURL:url completion:^(UIImage *img) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        // 回调回来时可能已经切歌了
        if (![self.coverURLString isEqualToString:url]) return;
        if (img) [self applyCover:img];
    }];
}

- (void)applyCover:(UIImage *)img {
    [UIView transitionWithView:self.cover duration:0.22
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
        self.cover.image = img;
    } completion:nil];
    // 背景也铺一层模糊封面，接近网易云的沉浸效果
    if (self.coverBlurBackdrop) {
        self.coverBlurBackdrop.image = img;
    }
}

#pragma mark - NELyricViewDelegate

- (void)lyricView:(id)view didSeekToTime:(double)time {
    [[NEPlayer shared] seekTo:time];
    [self refresh];
}

@end