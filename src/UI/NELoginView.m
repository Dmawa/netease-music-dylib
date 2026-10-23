#import "NELoginView.h"
#import "NEUITheme.h"
#import "NEApi.h"
#import "NEQRCode.h"

typedef NS_ENUM(NSInteger, NELoginState) {
    NELoginStateLoading,     // 正在取二维码
    NELoginStateWaiting,     // 等待扫码
    NELoginStateScanned,     // 已扫码，待确认
    NELoginStateSuccess,
    NELoginStateExpired,     // 二维码过期，可点击刷新
    NELoginStateFailed,
};

@interface NELoginView ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIImageView *qrView;
@property (nonatomic, strong) UIView *qrMask;
@property (nonatomic, strong) UILabel *maskLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *refreshBtn;
@property (nonatomic, strong) UIButton *cancelBtn;

@property (nonatomic, copy, nullable) NSString *unikey;
@property (nonatomic, assign) NELoginState state;
@property (nonatomic, assign) BOOL polling;      // 是否有轮询在飞
@property (nonatomic, assign) BOOL stopped;
@property (nonatomic, assign) NSInteger credRetry;
@end

@implementation NELoginView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = NE_PANEL;
        self.layer.cornerRadius = 16;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        [self build];
    }
    return self;
}

- (void)build {
    _titleLabel = [UILabel new];
    _titleLabel.text = @"网易云音乐扫码登录";
    _titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _titleLabel.textColor = NE_TEXT;
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_titleLabel];

    _subtitleLabel = [UILabel new];
    _subtitleLabel.text = @"用网易云音乐 App 扫描二维码";
    _subtitleLabel.font = [UIFont systemFontOfSize:12];
    _subtitleLabel.textColor = NE_TEXT_DIM;
    _subtitleLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_subtitleLabel];

    _qrView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _qrView.backgroundColor = UIColor.whiteColor;
    _qrView.contentMode = UIViewContentModeScaleAspectFit;
    _qrView.layer.cornerRadius = 8;
    _qrView.layer.cornerCurve = kCACornerCurveContinuous;
    _qrView.clipsToBounds = YES;
    _qrView.userInteractionEnabled = YES;
    [_qrView addGestureRecognizer:[[UITapGestureRecognizer alloc]
                                   initWithTarget:self action:@selector(refreshTapped)]];
    [self addSubview:_qrView];

    // 过期/失败时盖在二维码上的遮罩
    _qrMask = [UIView new];
    _qrMask.backgroundColor = [UIColor colorWithWhite:0 alpha:0.72];
    _qrMask.layer.cornerRadius = 8;
    _qrMask.layer.cornerCurve = kCACornerCurveContinuous;
    _qrMask.hidden = YES;
    _qrMask.userInteractionEnabled = YES;
    [_qrMask addGestureRecognizer:[[UITapGestureRecognizer alloc]
                                   initWithTarget:self action:@selector(refreshTapped)]];
    [self addSubview:_qrMask];

    _maskLabel = [UILabel new];
    _maskLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _maskLabel.textColor = UIColor.whiteColor;
    _maskLabel.textAlignment = NSTextAlignmentCenter;
    _maskLabel.numberOfLines = 2;
    [_qrMask addSubview:_maskLabel];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.color = NE_TEXT_DIM;
    _spinner.hidesWhenStopped = YES;
    [self addSubview:_spinner];

    _statusLabel = [UILabel new];
    _statusLabel.font = [UIFont systemFontOfSize:12];
    _statusLabel.textColor = NE_TEXT_DIM;
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.numberOfLines = 2;
    [self addSubview:_statusLabel];

    _refreshBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [_refreshBtn setTitle:@"刷新二维码" forState:UIControlStateNormal];
    _refreshBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [_refreshBtn setTitleColor:NE_BRAND forState:UIControlStateNormal];
    [_refreshBtn addTarget:self action:@selector(refreshTapped) forControlEvents:UIControlEventTouchUpInside];
    _refreshBtn.hidden = YES;
    [self addSubview:_refreshBtn];

    _cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [_cancelBtn setTitle:@"关闭" forState:UIControlStateNormal];
    _cancelBtn.titleLabel.font = [UIFont systemFontOfSize:14];
    [_cancelBtn setTitleColor:NE_TEXT_DIM forState:UIControlStateNormal];
    [_cancelBtn addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_cancelBtn];
}

#pragma mark - 布局（自适应）

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width;
    CGFloat H = self.bounds.size.height;
    CGFloat pad = 20;

    _titleLabel.frame = CGRectMake(pad, 18, W - pad * 2, 22);
    _subtitleLabel.frame = CGRectMake(pad, CGRectGetMaxY(_titleLabel.frame) + 4, W - pad * 2, 16);

    // 二维码尺寸：受宽高共同约束，最长边留出让状态文字和按钮的空间
    CGFloat availH = H - 62 - 90;                 // 标题区 + 底部区
    CGFloat side = MIN(W - pad * 2, availH);
    side = MIN(side, 260);
    side = MAX(side, 120);
    CGFloat qx = (W - side) / 2;
    CGFloat qy = CGRectGetMaxY(_subtitleLabel.frame) + 14;
    _qrView.frame = CGRectMake(qx, qy, side, side);
    _qrMask.frame = _qrView.frame;
    _maskLabel.frame = CGRectMake(10, 0, side - 20, side);
    _spinner.center = CGPointMake(CGRectGetMidX(_qrView.frame), CGRectGetMidY(_qrView.frame));

    CGFloat statusY = CGRectGetMaxY(_qrView.frame) + 10;
    _statusLabel.frame = CGRectMake(pad, statusY, W - pad * 2, 34);
    _refreshBtn.frame = CGRectMake(pad, CGRectGetMaxY(_statusLabel.frame) + 2, W - pad * 2, 28);
    _cancelBtn.frame = CGRectMake(pad, H - 40, W - pad * 2, 30);
}

#pragma mark - 状态

- (void)applyState:(NELoginState)state message:(NSString *)message {
    self.state = state;
    _statusLabel.text = message ?: @"";

    switch (state) {
        case NELoginStateLoading:
            _qrMask.hidden = YES;
            _refreshBtn.hidden = YES;
            [_spinner startAnimating];
            _qrView.alpha = 0.35;
            break;
        case NELoginStateWaiting:
            _qrMask.hidden = YES;
            _refreshBtn.hidden = YES;
            [_spinner stopAnimating];
            _qrView.alpha = 1;
            break;
        case NELoginStateScanned:
            _qrMask.hidden = NO;
            _maskLabel.text = @"已扫码\n请在手机上确认";
            _refreshBtn.hidden = YES;
            [_spinner stopAnimating];
            _qrView.alpha = 0.5;
            _statusLabel.textColor = NE_TEXT;
            break;
        case NELoginStateSuccess:
            _qrMask.hidden = NO;
            _maskLabel.text = @"登录成功";
            _refreshBtn.hidden = YES;
            [_spinner stopAnimating];
            _qrView.alpha = 0.5;
            _statusLabel.textColor = NE_TEXT;
            break;
        case NELoginStateExpired:
            _qrMask.hidden = NO;
            _maskLabel.text = @"二维码已过期\n点击刷新";
            _refreshBtn.hidden = NO;
            [_spinner stopAnimating];
            break;
        case NELoginStateFailed:
            _qrMask.hidden = NO;
            _maskLabel.text = @"加载失败\n点击重试";
            _refreshBtn.hidden = NO;
            [_spinner stopAnimating];
            _statusLabel.textColor = [UIColor colorWithRed:1 green:0.45 blue:0.45 alpha:1];
            break;
    }
    if (state != NELoginStateFailed) _statusLabel.textColor = NE_TEXT_DIM;
}

#pragma mark - 流程

- (void)start {
    self.stopped = NO;
    [self requestNewCode];
}

- (void)stop {
    self.stopped = YES;
    self.polling = NO;
    self.unikey = nil;
}

- (void)refreshTapped {
    if (self.state == NELoginStateLoading) return;
    [self requestNewCode];
}

- (void)requestNewCode {
    [self applyState:NELoginStateLoading message:@"正在获取二维码…"];
    self.unikey = nil;
    self.credRetry = 0;

    __weak typeof(self) weakSelf = self;
    [[NEApi shared] requestQRKey:^(NSString *unikey, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.stopped) return;

        if (!unikey.length) {
            [self applyState:NELoginStateFailed
                     message:error.localizedDescription ?: @"获取二维码失败"];
            return;
        }
        self.unikey = unikey;

        // 二维码本地生成：网易云没有可直接下载的图片接口
        NSString *content = [NSString stringWithFormat:
            @"https://music.163.com/login?codekey=%@", unikey];
        UIImage *img = [NEQRCode imageWithText:content size:260];
        self.qrView.image = img;

        if (!img) {
            [self applyState:NELoginStateFailed message:@"二维码生成失败"];
            return;
        }
        [self applyState:NELoginStateWaiting message:@"请使用网易云 App 扫码"];
        [self poll];
    }];
}

- (void)poll {
    if (self.stopped || !self.unikey.length) return;
    if (self.polling) return;                  // 防重入
    self.polling = YES;

    NSString *key = self.unikey;
    __weak typeof(self) weakSelf = self;
    [[NEApi shared] pollQRCode:key complete:^(NSInteger code, NSString *nickname, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.stopped) return;
        self.polling = NO;

        // 期间换了 unikey 就丢弃旧结果
        if (![self.unikey isEqualToString:key]) return;

        if (error) {
            // 网络抖动不立刻判死，继续重试几次
            [self applyState:NELoginStateWaiting message:error.localizedDescription];
            [self schedulePoll:2.0];
            return;
        }

        switch (code) {
            case 800:   // 过期
                [self applyState:NELoginStateExpired message:@"二维码已过期，请点击刷新"];
                return;

            case 801:   // 等待扫码
                [self applyState:NELoginStateWaiting message:@"请使用网易云 App 扫码"];
                [self schedulePoll:1.5];
                return;

            case 802:   // 已扫码待确认
                [self applyState:NELoginStateScanned message:@"已扫码，请在手机上确认"];
                [self schedulePoll:1.2];
                return;

            case 803: { // 成功
                [self handleLoginSuccess:nickname];
                return;
            }

            case 8821:
                // 风控提示：同一个二维码被重复轮询会触发。
                // 此时若已拿到凭证，直接按成功处理；否则要求刷新二维码。
                if ([[NEApi shared] isLoggedIn]) {
                    [self handleLoginSuccess:nickname];
                } else {
                    [self applyState:NELoginStateExpired
                             message:@"扫码状态已失效，请点击刷新二维码"];
                }
                return;

            default:
                [self applyState:NELoginStateWaiting
                         message:[NSString stringWithFormat:@"状态 %ld，继续等待…", (long)code]];
                [self schedulePoll:1.5];
                return;
        }
    }];
}

- (void)schedulePoll:(NSTimeInterval)delay {
    if (self.stopped) return;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.stopped) return;
        [self poll];
    });
}

- (void)handleLoginSuccess:(NSString *)nickname {
    // 注意：这里绝对不能再调 poll。
    // 二维码是一次性的，803 之后重复轮询会触发风控（code 8821）。
    // 正确做法是直接查账号信息来确认登录态：
    //  - 成功 -> 服务端返回 profile，同时 MUSIC_U 已在 Set-Cookie 里
    //  - 失败 -> profile 为 null
    if ([[NEApi shared] isLoggedIn]) {
        [self finishLogin:nickname];
        return;
    }

    [self applyState:NELoginStateWaiting message:@"正在确认登录状态…"];
    __weak typeof(self) weakSelf = self;
    [[NEApi shared] fetchAccount:^(NSString *nick, NSString *avatar, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.stopped) return;

        if (nick.length || [[NEApi shared] isLoggedIn]) {
            [self finishLogin:nick.length ? nick : nickname];
            return;
        }
        // 一次都没成功：提示重来，但不再重复轮询
        [self applyState:NELoginStateFailed
                 message:error.localizedDescription ?: @"登录未完成，请刷新二维码重试"];
    }];
}

- (void)finishLogin:(NSString *)nickname {
    [self stop];                    // 立刻停止轮询，避免后续误触发
    [self applyState:NELoginStateSuccess message:@"登录成功"];
    if ([self.delegate respondsToSelector:@selector(loginViewDidLogin:nickname:)]) {
        [self.delegate loginViewDidLogin:self nickname:nickname];
    }
}

- (void)cancelTapped {
    [self stop];
    if ([self.delegate respondsToSelector:@selector(loginViewDidCancel:)]) {
        [self.delegate loginViewDidCancel:self];
    }
}

@end