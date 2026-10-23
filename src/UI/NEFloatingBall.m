#import "NEFloatingBall.h"
#import "NEUITheme.h"

@interface NEFloatingBall ()
@property (nonatomic, strong) UIButton *ball;
@property (nonatomic, strong) UIView *panelContainer;
@property (nonatomic, strong, nullable) UIView *panelView;
@property (nonatomic, assign) BOOL expanded;
@property (nonatomic, assign) CGPoint lastCenter;
@property (nonatomic, assign) BOOL hasPositioned;
@end

@implementation NEFloatingBall

+ (instancetype)shared {
    static NEFloatingBall *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[NEFloatingBall alloc] initWithFrame:[UIScreen mainScreen].bounds]; });
    return s;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        // 关键：独立窗口层级，浮在所有 App 内容之上
        self.windowLevel = UIWindowLevelAlert + 100;
        self.backgroundColor = [UIColor clearColor];
        self.rootViewController = [UIViewController new];
        self.rootViewController.view.backgroundColor = [UIColor clearColor];
        self.hidden = NO;

        [self buildBall];
        [self buildPanelContainer];
        [self addGestures];
        [self observeOrientation];
    }
    return self;
}

#pragma mark - 悬浮球

- (void)buildBall {
    CGFloat size = NE_BALL_SIZE;
    _ball = [UIButton buttonWithType:UIButtonTypeCustom];
    _ball.frame = CGRectMake(0, 0, size, size);
    _ball.layer.cornerRadius = size / 2;
    _ball.layer.cornerCurve = kCACornerCurveContinuous;
    _ball.backgroundColor = NE_BRAND;
    _ball.layer.shadowColor = UIColor.blackColor.CGColor;
    _ball.layer.shadowOpacity = 0.35;
    _ball.layer.shadowRadius = 10;
    _ball.layer.shadowOffset = CGSizeMake(0, 4);
    [_ball setTitle:@"♪" forState:UIControlStateNormal];
    _ball.titleLabel.font = [UIFont systemFontOfSize:26 weight:UIFontWeightSemibold];
    [_ball setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [_ball addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.rootViewController.view addSubview:_ball];
}

- (void)buildPanelContainer {
    CGFloat w = MIN(NE_PANEL_WIDTH, [UIScreen mainScreen].bounds.size.width - 32);
    _panelContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 460)];
    _panelContainer.backgroundColor = NE_PANEL;
    _panelContainer.layer.cornerRadius = NE_CORNER;
    _panelContainer.layer.cornerCurve = kCACornerCurveContinuous;
    _panelContainer.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    _panelContainer.layer.borderColor = NE_STROKE.CGColor;
    _panelContainer.clipsToBounds = YES;
    _panelContainer.hidden = YES;
    [self.rootViewController.view addSubview:_panelContainer];
}

- (void)installPanelView:(UIView *)panelView {
    [self.panelView removeFromSuperview];
    self.panelView = panelView;
    panelView.frame = self.panelContainer.bounds;
    panelView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.panelContainer addSubview:panelView];
}

#pragma mark - 手势

- (void)addGestures {
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [_ball addGestureRecognizer:pan];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self];
    CGPoint center = CGPointMake(self.ball.center.x + translation.x,
                                 self.ball.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:self];

    // 吸附到屏幕内
    CGFloat half = NE_BALL_SIZE / 2;
    CGRect bounds = self.bounds;
    center.x = MAX(half + 8, MIN(center.x, bounds.size.width - half - 8));
    center.y = MAX(half + 30, MIN(center.y, bounds.size.height - half - 30));
    self.ball.center = center;
    self.lastCenter = center;

    if (pan.state == UIGestureRecognizerStateEnded) {
        // 松手吸附到最近的左右边缘
        CGFloat targetX = center.x < bounds.size.width / 2 ? half + 10 : bounds.size.width - half - 10;
        [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0.6
                            options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.ball.center = CGPointMake(targetX, center.y);
        } completion:nil];
        if (self.expanded) [self layoutPanel];
    }
}

#pragma mark - 展开 / 收起

- (void)togglePanel {
    self.expanded = !self.expanded;
    if (self.expanded) {
        self.panelContainer.hidden = NO;
        [self layoutPanel];
        self.panelContainer.alpha = 0;
        self.panelContainer.transform = CGAffineTransformMakeScale(0.92, 0.92);
        [UIView animateWithDuration:0.26 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.4
                            options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.panelContainer.alpha = 1;
            self.panelContainer.transform = CGAffineTransformIdentity;
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.18 animations:^{
            self.panelContainer.alpha = 0;
            self.panelContainer.transform = CGAffineTransformMakeScale(0.94, 0.94);
        } completion:^(BOOL finished) {
            self.panelContainer.hidden = YES;
            self.panelContainer.alpha = 1;
            self.panelContainer.transform = CGAffineTransformIdentity;
            // 收起时释放键盘
            [self endEditing:YES];
        }];
    }
}

- (void)layoutPanel {
    CGRect screen = self.bounds;
    CGSize size = self.panelContainer.bounds.size;
    CGFloat margin = 12;

    CGFloat x;
    if (self.ball.center.x < screen.size.width / 2) {
        x = CGRectGetMaxX(self.ball.frame) + margin;
    } else {
        x = CGRectGetMinX(self.ball.frame) - size.width - margin;
    }
    // 贴着球放不下时回退到居中
    if (x < margin || x + size.width > screen.size.width - margin) {
        x = (screen.size.width - size.width) / 2;
    }
    CGFloat y = self.ball.center.y - size.height / 2;
    y = MAX(60, MIN(y, screen.size.height - size.height - 40));

    self.panelContainer.frame = CGRectMake(x, y, size.width, size.height);
}

#pragma mark - 屏幕适配

- (void)observeOrientation {
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(handleOrientationChange:)
        name:UIDeviceOrientationDidChangeNotification object:nil];
}

- (void)handleOrientationChange:(NSNotification *)note {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.frame = [UIScreen mainScreen].bounds;
        CGFloat w = MIN(NE_PANEL_WIDTH, self.bounds.size.width - 32);
        CGRect f = self.panelContainer.frame;
        self.panelContainer.frame = CGRectMake(f.origin.x, f.origin.y, w, f.size.height);
        if (self.expanded) [self layoutPanel];
    });
}

- (void)presentBall {
    self.hidden = NO;
    if (self.hasPositioned) return;
    self.hasPositioned = YES;

    // 默认停在右侧偏上：避开状态栏，也避开右下角的返回手势区
    CGRect screen = self.bounds;
    CGFloat w = screen.size.width;
    CGFloat topSafe = 60.0;
    if (@available(iOS 11.0, *)) {
        UIWindow *win = self;
        topSafe = win.safeAreaInsets.top + 44.0;
    }
    self.ball.center = CGPointMake(w - NE_BALL_SIZE / 2 - 10, topSafe + NE_BALL_SIZE / 2);
}

@end