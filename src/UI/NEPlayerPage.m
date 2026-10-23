#import "NEPlayerPage.h"
#import "NEUITheme.h"
#import "NEPlayer.h"
#import "NEApi.h"
#import "NELyricView.h"
#import "NEImageCache.h"
#import "NEPlaylistSheet.h"

@interface NEPlayerPage () <NELyricViewDelegate>
@property (nonatomic, strong) UIImageView *coverBlurBackdrop;
@property (nonatomic, strong) UIVisualEffectView *coverBlur;

@property (nonatomic, strong) UIView *vinylBox;
@property (nonatomic, strong) UIView *discBase;
@property (nonatomic, strong) UIImageView *discCover;
@property (nonatomic, strong) UIView *centerDot;
@property (nonatomic, strong) UIView *tonearm;

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;
@property (nonatomic, strong) UILabel *vipBadge;
@property (nonatomic, strong) UIButton *likeBtn;
@property (nonatomic, strong) UIButton *commentBtn;

@property (nonatomic, strong) UISlider *progress;
@property (nonatomic, strong) UILabel *timeNow;
@property (nonatomic, strong) UILabel *timeTotal;
@property (nonatomic, strong) UILabel *qualityLabel;

@property (nonatomic, strong) UIButton *prevBtn;
@property (nonatomic, strong) UIButton *playBtn;
@property (nonatomic, strong) UIButton *nextBtn;
@property (nonatomic, strong) UIButton *loopBtn;
@property (nonatomic, strong) UIButton *listBtn;

@property (nonatomic, strong) UIButton *fxBtn;
@property (nonatomic, strong) UIButton *downloadBtn;
@property (nonatomic, strong) UIButton *moreBtn;
@property (nonatomic, strong) UIButton *translateBtn;

@property (nonatomic, strong) NELyricView *lyricView;
@property (nonatomic, strong) NELyric *lyric;

@property (nonatomic, assign) BOOL showsTranslation;
@property (nonatomic, assign) BOOL userSeeking;
@property (nonatomic, assign) BOOL spinning;
@property (nonatomic, copy) NSString *loadedSongID;
@property (nonatomic, copy) NSString *coverURLString;
@property (nonatomic, copy) NSString *likedSongID;
@property (nonatomic, assign) NSInteger commentTotal;
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
    [b setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    b.tintColor = NE_TEXT;
    b.imageView.contentMode = UIViewContentModeScaleAspectFit;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)build {
    _coverBlurBackdrop = [[UIImageView alloc] initWithFrame:CGRectZero];
    _coverBlurBackdrop.contentMode = UIViewContentModeScaleAspectFill;
    _coverBlurBackdrop.clipsToBounds = YES;
    _coverBlurBackdrop.alpha = 0.30;
    [self addSubview:_coverBlurBackdrop];

    _coverBlur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    _coverBlur.alpha = 0.75;
    _coverBlur.userInteractionEnabled = NO;
    [self addSubview:_coverBlur];

    // 黑胶唱片
    _vinylBox = [[UIView alloc] initWithFrame:CGRectZero];
    [_vinylBox setUserInteractionEnabled:NO];
    [self addSubview:_vinylBox];

    _discBase = [[UIView alloc] initWithFrame:CGRectZero];
    _discBase.backgroundColor = NEColor(0x0B0B0B, 1.0);
    _discBase.layer.borderWidth = 1;
    _discBase.layer.borderColor = NEColor(0xFFFFFF, 0.08).CGColor;
    [_vinylBox addSubview:_discBase];

    _discCover = [[UIImageView alloc] initWithFrame:CGRectZero];
    _discCover.backgroundColor = NE_CARD;
    _discCover.clipsToBounds = YES;
    _discCover.contentMode = UIViewContentModeScaleAspectFill;
    [_vinylBox addSubview:_discCover];

    _centerDot = [[UIView alloc] initWithFrame:CGRectZero];
    _centerDot.backgroundColor = NEColor(0xF2F2F2, 0.9);
    _centerDot.layer.cornerRadius = 3;
    [_vinylBox addSubview:_centerDot];

    _tonearm = [[UIView alloc] initWithFrame:CGRectZero];
    _tonearm.backgroundColor = NEColor(0xEDEDED, 0.85);
    _tonearm.layer.cornerRadius = 2;
    [_vinylBox addSubview:_tonearm];

    // 歌曲信息
    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _titleLabel.textColor = NE_TEXT;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:_titleLabel];

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

    _artistLabel = [UILabel new];
    _artistLabel.font = [UIFont systemFontOfSize:12];
    _artistLabel.textColor = NE_TEXT_DIM;
    [self addSubview:_artistLabel];

    _likeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [_likeBtn setTitle:@"♡" forState:UIControlStateNormal];
    [_likeBtn setTitleColor:NE_TEXT forState:UIControlStateNormal];
    _likeBtn.titleLabel.font = [UIFont systemFontOfSize:20];
    [_likeBtn addTarget:self action:@selector(toggleLike) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_likeBtn];

    _commentBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [_commentBtn setTitle:@"💬" forState:UIControlStateNormal];
    _commentBtn.titleLabel.font = [UIFont systemFontOfSize:15];
    [_commentBtn addTarget:self action:@selector(showComments) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_commentBtn];

    // 进度
    _progress = [[UISlider alloc] initWithFrame:CGRectZero];
    _progress.minimumTrackTintColor = NE_BRAND;
    _progress.maximumTrackTintColor = NEColor(0xFFFFFF, 0.18);
    [_progress addTarget:self action:@selector(sliderTouchDown) forControlEvents:UIControlEventTouchDown];
    [_progress addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
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

    _qualityLabel = [UILabel new];
    _qualityLabel.text = @"极高音质";
    _qualityLabel.font = [UIFont systemFontOfSize:9];
    _qualityLabel.textColor = NE_TEXT_DIM;
    _qualityLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_qualityLabel];

    // 控制
    _loopBtn = [self iconButton:@"repeat" size:18 action:@selector(cycleLoop)];
    _prevBtn = [self iconButton:@"backward.end.fill" size:22 action:@selector(prev)];
    _playBtn = [self iconButton:@"play.fill" size:28 action:@selector(toggle)];
    _nextBtn = [self iconButton:@"forward.end.fill" size:22 action:@selector(next)];
    _listBtn = [self iconButton:@"list.bullet" size:20 action:@selector(openPlaylist)];
    for (UIButton *b in @[_loopBtn, _prevBtn, _playBtn, _nextBtn, _listBtn]) [self addSubview:b];

    // 辅助
    _fxBtn = [self iconButton:@"waveform" size:16 action:@selector(notReady:)];
    _downloadBtn = [self iconButton:@"arrow.down.circle" size:16 action:@selector(notReady:)];
    _moreBtn = [self iconButton:@"ellipsis" size:16 action:@selector(showMore)];
    _translateBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [_translateBtn setTitle:@"译" forState:UIControlStateNormal];
    _translateBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [_translateBtn setTitleColor:NE_TEXT forState:UIControlStateNormal];
    _translateBtn.layer.borderWidth = 1;
    _translateBtn.layer.borderColor = NEColor(0xFFFFFF, 0.25).CGColor;
    _translateBtn.layer.cornerRadius = 10;
    [_translateBtn addTarget:self action:@selector(toggleTranslation) forControlEvents:UIControlEventTouchUpInside];
    for (UIButton *b in @[_fxBtn, _downloadBtn, _moreBtn, _translateBtn]) [self addSubview:b];

    // 歌词
    _lyricView = [[NELyricView alloc] initWithFrame:CGRectZero];
    _lyricView.delegate = self;
    _lyricView.showsTranslation = YES;
    [self addSubview:_lyricView];
}

#pragma mark - 布局

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width;
    CGFloat H = self.bounds.size.height;
    _coverBlurBackdrop.frame = self.bounds;
    _coverBlur.frame = self.bounds;

    BOOL wide = (W >= 560);
    CGFloat bottom = 92;

    if (wide) {
        CGFloat leftW = W * 0.46;
        CGFloat discSize = MIN(leftW - 52, H - bottom - 150);
        discSize = MAX(96, discSize);

        CGFloat vx = 26 + (leftW - 52 - discSize) / 2;
        CGFloat vy = 10;
        _vinylBox.frame = CGRectMake(vx - 10, vy, discSize + 20, discSize + 20);

        _discBase.frame = CGRectMake(10, 10, discSize, discSize);
        _discBase.layer.cornerRadius = discSize / 2;
        _discCover.frame = CGRectMake(10 + discSize * 0.18, 10 + discSize * 0.18,
                                      discSize * 0.64, discSize * 0.64);
        _discCover.layer.cornerRadius = discSize * 0.32;
        _centerDot.frame = CGRectMake(10 + discSize / 2 - 3, 10 + discSize / 2 - 3, 6, 6);
        _tonearm.frame = CGRectMake(10 + discSize * 0.72, 0, 4, discSize * 0.45);
        _tonearm.transform = CGAffineTransformMakeRotation(M_PI / 9);

        CGFloat infoY = CGRectGetMaxY(_vinylBox.frame) + 6;
        _titleLabel.frame = CGRectMake(26, infoY, leftW - 120, 22);
        _artistLabel.frame = CGRectMake(26, infoY + 22, leftW - 120, 16);
        _vipBadge.frame = CGRectMake(CGRectGetMaxX(_titleLabel.frame) + 4, infoY + 5, 26, 13);
        _likeBtn.frame = CGRectMake(leftW - 56, infoY - 2, 28, 28);
        _commentBtn.frame = CGRectMake(leftW - 26, infoY, 26, 26);

        CGFloat barY = infoY + 44;
        _progress.frame = CGRectMake(26, barY, leftW - 52, 18);
        _timeNow.frame = CGRectMake(26, barY + 18, 40, 12);
        _timeTotal.frame = CGRectMake(leftW - 66, barY + 18, 40, 12);
        _qualityLabel.frame = CGRectMake(leftW / 2 - 40, barY - 2, 80, 12);

        CGFloat cy = barY + 50;
        CGFloat cx = 26 + (leftW - 52) / 2;
        _loopBtn.frame = CGRectMake(26, cy - 12, 30, 24);
        _prevBtn.frame = CGRectMake(cx - 70, cy - 15, 34, 30);
        _playBtn.frame = CGRectMake(cx - 17, cy - 20, 34, 40);
        _nextBtn.frame = CGRectMake(cx + 36, cy - 15, 34, 30);
        _listBtn.frame = CGRectMake(leftW - 56, cy - 12, 30, 24);

        _fxBtn.frame = CGRectMake(26, H - 30, 26, 22);
        _downloadBtn.frame = CGRectMake(70, H - 30, 26, 22);
        _moreBtn.frame = CGRectMake(114, H - 30, 26, 22);
        _translateBtn.frame = CGRectMake(W - 52, H - 32, 28, 20);

        CGFloat lyricX = leftW + 14;
        _lyricView.frame = CGRectMake(lyricX, 8, W - lyricX - 16, H - 16);
    } else {
        CGFloat discSize = MIN(W * 0.42, H * 0.30);
        discSize = MAX(72, discSize);
        CGFloat vx = (W - discSize) / 2;
        _vinylBox.frame = CGRectMake(vx - 10, 4, discSize + 20, discSize + 20);

        _discBase.frame = CGRectMake(10, 10, discSize, discSize);
        _discBase.layer.cornerRadius = discSize / 2;
        _discCover.frame = CGRectMake(10 + discSize * 0.18, 10 + discSize * 0.18,
                                      discSize * 0.64, discSize * 0.64);
        _discCover.layer.cornerRadius = discSize * 0.32;
        _centerDot.frame = CGRectMake(10 + discSize / 2 - 3, 10 + discSize / 2 - 3, 6, 6);
        _tonearm.frame = CGRectMake(10 + discSize * 0.72, 0, 3, discSize * 0.42);
        _tonearm.transform = CGAffineTransformMakeRotation(M_PI / 9);

        CGFloat infoY = CGRectGetMaxY(_vinylBox.frame) + 2;
        _titleLabel.textAlignment = NSTextAlignmentLeft;
        _titleLabel.frame = CGRectMake(16, infoY, W - 100, 20);
        _artistLabel.frame = CGRectMake(16, infoY + 20, W - 100, 14);
        _vipBadge.frame = CGRectMake(W - 78, infoY + 4, 26, 13);
        _likeBtn.frame = CGRectMake(W - 50, infoY - 2, 26, 26);
        _commentBtn.frame = CGRectMake(W - 24, infoY + 1, 22, 22);

        CGFloat barY = infoY + 40;
        _progress.frame = CGRectMake(16, barY, W - 32, 16);
        _timeNow.frame = CGRectMake(16, barY + 16, 40, 11);
        _timeTotal.frame = CGRectMake(W - 56, barY + 16, 40, 11);
        _qualityLabel.frame = CGRectMake(W / 2 - 40, barY, 80, 11);

        CGFloat cy = barY + 44;
        CGFloat cx = W / 2;
        _loopBtn.frame = CGRectMake(16, cy - 12, 28, 24);
        _prevBtn.frame = CGRectMake(cx - 70, cy - 14, 32, 28);
        _playBtn.frame = CGRectMake(cx - 16, cy - 19, 32, 38);
        _nextBtn.frame = CGRectMake(cx + 38, cy - 14, 32, 28);
        _listBtn.frame = CGRectMake(W - 44, cy - 12, 28, 24);

        _fxBtn.frame = CGRectMake(16, H - 26, 24, 20);
        _downloadBtn.frame = CGRectMake(54, H - 26, 24, 20);
        _moreBtn.frame = CGRectMake(92, H - 26, 24, 20);
        _translateBtn.frame = CGRectMake(W - 44, H - 28, 26, 19);

        CGFloat lyricTop = cy + 22;
        _lyricView.frame = CGRectMake(0, lyricTop, W, MAX(40, H - lyricTop - 32));
    }
}

#pragma mark - 通知

- (void)observe {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(onState) name:NEPlayerStateChangedNotification object:nil];
    [nc addObserver:self selector:@selector(onTrack) name:NEPlayerTrackChangedNotification object:nil];
    [nc addObserver:self selector:@selector(onProgress) name:NEPlayerProgressNotification object:nil];
}

- (void)onState {
    [self refresh];
}

- (void)onTrack {
    self.likedSongID = nil;
    self.commentTotal = 0;
    [self loadLyricForCurrentSong];
    [self loadCommentCount];
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
    [_playBtn setImage:[UIImage systemImageNamed:(playing ? @"pause.fill" : @"play.fill")]
              forState:UIControlStateNormal];

    [self updateLoopIcon];
    [self updateLikeButton];

    if (self.commentTotal > 0) {
        [_commentBtn setTitle:[NSString stringWithFormat:@"💬 %ld", (long)self.commentTotal]
                     forState:UIControlStateNormal];
    } else {
        [_commentBtn setTitle:@"💬" forState:UIControlStateNormal];
    }

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

- (void)updateLikeButton {
    BOOL liked = self.likedSongID.length &&
        [self.likedSongID isEqualToString:[NEPlayer shared].currentSong.songID];
    [_likeBtn setTitle:(liked ? @"♥" : @"♡") forState:UIControlStateNormal];
    [_likeBtn setTitleColor:(liked ? NE_BRAND : NE_TEXT) forState:UIControlStateNormal];
}

#pragma mark - 黑胶旋转

- (void)startVinyl {
    if (self.spinning) return;
    self.spinning = YES;
    CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    spin.fromValue = @(0);
    spin.toValue = @(M_PI * 2);
    spin.duration = 24;
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
        _coverBlurBackdrop.image = nil;
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
    _coverBlurBackdrop.image = img;
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

- (void)toggleTranslation {
    self.showsTranslation = !self.showsTranslation;
    self.lyricView.showsTranslation = self.showsTranslation;
    [_translateBtn setTitleColor:(self.showsTranslation ? NE_TEXT : NE_TEXT_DIM)
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

- (void)loadCommentCount {
    NESong *song = [NEPlayer shared].currentSong;
    if (!song.songID.length) return;
    __weak typeof(self) weakSelf = self;
    [[NEApi shared] fetchCommentsForSongID:song.songID limit:1
                                complete:^(NSArray<NSDictionary *> *comments, NSInteger total, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.commentTotal = total;
        [self refresh];
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
    return [NSString stringWithFormat:@"%d:%02d", total / 60, total % 60];
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
