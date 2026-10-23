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
/// 每换一次二维码 +1；旧请求/旧定时器的回调据此整条作废
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, assign) BOOL stopped;

- (void)confirmLoginWithNickname:(nullable NSString *)nickname attempt:(NSInteger)attempt;
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
            break;
        case NELoginStateSuccess:
            _qrMask.hidden = NO;
            _maskLabel.text = @"登录成功";
            _refreshBtn.hidden = YES;
            [_spinner stopAnimating];
            _qrView.alpha = 0.5;
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
            break;
    }

    // 状态文字颜色：失败=红、已扫码/成功=白、其余=灰。
    // （以前这里无条件写回灰色，把上面对白/红的设置全盖掉了。）
    if (state == NELoginStateFailed) {
        _statusLabel.textColor = [UIColor colorWithRed:1 green:0.45 blue:0.45 alpha:1];
    } else if (state == NELoginStateScanned || state == NELoginStateSuccess) {
        _statusLabel.textColor = NE_TEXT;
    } else {
        _statusLabel.textColor = NE_TEXT_DIM;
    }
}

#pragma mark - 流程

- (void)start {
    self.stopped = NO;
    [self requestNewCode];
}

- (void)stop {
    self.stopped = YES;
    self.generation += 1;      // 在飞的请求与定时器全部作废
    self.unikey = nil;
}

- (void)refreshTapped {
    if (self.state == NELoginStateLoading) return;
    [self requestNewCode];
}

- (void)requestNewCode {
    // 刷新/重登：作废旧 generation，旧请求的响应会被丢弃
    self.stopped = NO;
    self.generation += 1;
    const NSUInteger gen = self.generation;

    [self applyState:NELoginStateLoading message:@"正在获取二维码…"];
    self.unikey = nil;

    __weak typeof(self) weakSelf = self;
    [[NEApi shared] requestQRKey:^(NSString *unikey, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.stopped || gen != self.generation) return;

        if (!unikey.length) {
            [self applyState:NELoginStateFailed
                     message:error.localizedDescription ?: @"获取二维码失败"];
            return;
        }
        self.unikey = unikey;

        // 二维码内容必须与官方 web 端完全一致：
        //   http://music.163.com/login?codekey=<unikey>
        // 官方 js 里写的就是 http（不是 https），App 扫码时按这个前缀识别。
        NSString *content = [NSString stringWithFormat:
            @"http://music.163.com/login?codekey=%@", unikey];
        UIImage *img = [NEQRCode imageWithText:content size:260];
        self.qrView.image = img;

        if (!img) {
            [self applyState:NELoginStateFailed message:@"二维码生成失败"];
            return;
        }
        [self applyState:NELoginStateWaiting message:@"请使用网易云 App 扫码"];
        [self pollWithGeneration:gen delay:0];
    }];
}

/// 单个轮询；每次响应结束后自己排队下一次。gen 变化（换码/关闭）即整条链作废
- (void)pollWithGeneration:(NSUInteger)gen delay:(NSTimeInterval)delay {
    if (self.stopped || gen != self.generation || !self.unikey.length) return;

    NSString *key = self.unikey;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.stopped || gen != self.generation) return;
        if (![self.unikey isEqualToString:key]) return;   // 期间换了码

        [[NEApi shared] pollQRCodeDetail:key complete:^(NSInteger code, NSString *nickname,
                                                        NSArray<NSString *> *setCookieLines,
                                                        NSString *message,
                                                        NSError *error) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || self.stopped || gen != self.generation) return;

            if (error) {
                // 网络抖动不判死，继续重试
                [self applyState:NELoginStateWaiting message:error.localizedDescription];
                [self pollWithGeneration:gen delay:2.0];
                return;
            }

            NSLog(@"[NELogin] poll code=%ld message=%@ loggedIn=%d cookies=%@",
                  (long)code, message, [[NEApi shared] isLoggedIn],
                  [[NESession shared] cookieHeader]);

            if (code == 803) {
                NSLog(@"[NELogin] 803 Set-Cookie lines = %@", setCookieLines);
                [self handleLoginSuccess:nickname];
                return;
            }
            if (code == 800) {
                [self applyState:NELoginStateExpired message:@"二维码已过期，请点击刷新"];
                return;
            }
            if (code == 802) {
                [self applyState:NELoginStateScanned message:@"已扫码，请在手机上确认"];
                [self pollWithGeneration:gen delay:1.0];
                return;
            }
            if (code == 801) {
                [self applyState:NELoginStateWaiting message:@"请使用网易云 App 扫码"];
                [self pollWithGeneration:gen delay:1.0];
                return;
            }

            /*
             *  其他状态码（典型是 8821）：
             *  官方 web 的 switch 只处理 800/801/802/803，default 直接忽略并继续轮询。
             *  8821 多是扫码确认瞬间的临时状态，继续轮询通常能等到 803；
             *  之前把它当终止状态，用户就直接卡在「登录状态异常」了。
             */
            NSLog(@"[NELogin] 未知状态码 %ld message=%@（官方前端同样继续轮询）",
                  (long)code, message);
            if ([[NEApi shared] isLoggedIn]) {          // 凭证其实已经下发
                [self handleLoginSuccess:nickname];
                return;
            }
            // 把服务端原话显示出来，方便定位（拿不到就说「等待手机确认」）
            NSString *hint = message.length ? message : @"等待手机确认…";
            [self applyState:NELoginStateWaiting
                     message:[NSString stringWithFormat:@"%@（%ld）", hint, (long)code]];
            [self pollWithGeneration:gen delay:2.0];
        }];
    });
}

- (void)handleLoginSuccess:(NSString *)nickname {
    /*
     *  判定登录成功不能只看 MUSIC_U 是否在本地 jar 里：
     *  NSURLSession 可能把 Set-Cookie 直接吸收进 HTTPCookieStorage，
     *  我们的 allHeaderFields 解析拿不到，但会话其实已经生效了。
     *
     *  所以这里直接问服务端「我现在是谁」：
     *    - 返回 profile  -> 登录成功（Cookie 已经生效）
     *    - profile 为 null -> 没登录成功
     *
     *  另外：绝不再去 poll 二维码，那是已经用掉的一次性凭证。
     */
    [self applyState:NELoginStateWaiting message:@"正在确认登录状态…"];
    [self confirmLoginWithNickname:nickname attempt:1];
}

- (void)confirmLoginWithNickname:(NSString *)nickname attempt:(NSInteger)attempt {
    __weak typeof(self) weakSelf = self;
    [[NEApi shared] fetchAccount:^(NSString *nick, NSString *avatar, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.stopped) return;

        BOOL ok = (nick.length > 0) || [[NEApi shared] isLoggedIn];
        if (ok) {
            NSLog(@"[NELogin] 登录成功 nickname=%@ loggedIn=%d cookies=%@",
                  nick, [[NEApi shared] isLoggedIn], [[NESession shared] cookieHeader]);
            [self finishLogin:nick.length ? nick : nickname];
            return;
        }

        // 803 之后 Cookie 可能晚一拍才生效，重试几次再判失败
        if (attempt < 3) {
            NSLog(@"[NELogin] 第 %ld 次确认未拿到 profile，稍后重试", (long)attempt);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self || self.stopped) return;
                [self confirmLoginWithNickname:nickname attempt:attempt + 1];
            });
            return;
        }

        // 把诊断信息显示在界面上，方便定位（不需要连电脑看日志）
        NSString *ck = [[NESession shared] cookieHeader];
        NSLog(@"[NELogin] 803 后仍未登录 error=%@ cookies=%@",
              error.localizedDescription, ck);

        NSString *hint;
        if (!ck.length) {
            hint = @"扫码已确认，但未收到任何 Cookie（服务端未下发凭证）";
        } else if (![[NESession shared] valueForCookie:@"MUSIC_U"].length) {
            hint = @"收到 Cookie 但缺少 MUSIC_U，请点击刷新重试";
        } else {
            hint = @"已收到 MUSIC_U，但服务端不认，请点击刷新重试";
        }
        [self applyState:NELoginStateFailed message:hint];
    }];
}

- (void)finishLogin:(NSString *)nickname {
    [self stop];                    // 停止轮询，避免后续误触发风控
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