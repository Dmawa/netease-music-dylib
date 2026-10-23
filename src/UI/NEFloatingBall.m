#import "NEFloatingBall.h"
#import "NEUITheme.h"

@interface NEFloatingBall () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIButton *ball;
@property (nonatomic, strong) UIView *panelContainer;
@property (nonatomic, strong) UIView *dragHandle;     // 面板顶部拖动条
@property (nonatomic, strong, nullable) UIView *panelView;
@property (nonatomic, assign) BOOL expanded;
@property (nonatomic, assign) BOOL hasPositioned;
@property (nonatomic, assign) CGSize preferredPanelSize;
@end

@implementation NEFloatingBall

+ (instancetype)shared {
    static NEFloatingBall *s; static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[NEFloatingBall alloc] initWithFrame:[UIScreen mainScreen].bounds];
    });
    return s;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.windowLevel = UIWindowLevelAlert + 100;
        self.backgroundColor = UIColor.clearColor;
        self.rootViewController = [UIViewController new];
        self.rootViewController.view.backgroundColor = UIColor.clearColor;
        self.hidden = NO;

        [self buildBall];
        [self buildPanelContainer];
        [self observeNotifications];
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
    _ball.layer.shadowRadius = 12;
    _ball.layer.shadowOffset = CGSizeMake(0, 4);
    [_ball setTitle:@"♪" forState:UIControlStateNormal];
    _ball.titleLabel.font = [UIFont systemFontOfSize:26 weight:UIFontWeightSemibold];
    [_ball setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [_ball addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
                                   initWithTarget:self action:@selector(handleBallPan:)];
    [_ball addGestureRecognizer:pan];
    [self.rootViewController.view addSubview:_ball];
}

- (void)handleBallPan:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self];
    CGPoint c = CGPointMake(self.ball.center.x + t.x, self.ball.center.y + t.y);
    [pan setTranslation:CGPointZero inView:self];

    CGFloat half = NE_BALL_SIZE / 2;
    c.x = MAX(half + 6, MIN(c.x, self.bounds.size.width - half - 6));
    c.y = MAX(half + 30, MIN(c.y, self.bounds.size.height - half - 30));
    self.ball.center = c;

    if (pan.state == UIGestureRecognizerStateEnded) {
        // 吸附到最近的左右边缘
        CGFloat targetX = (c.x < self.bounds.size.width / 2)
            ? half + 8 : self.bounds.size.width - half - 8;
        [UIView animateWithDuration:0.28 delay:0
             usingSpringWithDamping:0.8 initialSpringVelocity:0.5
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            self.ball.center = CGPointMake(targetX, c.y);
        } completion:nil];
    }
}

#pragma mark - 面板

- (void)buildPanelContainer {
    _panelContainer = [[UIView alloc] initWithFrame:CGRectZero];
    _panelContainer.backgroundColor = NE_PANEL;
    _panelContainer.layer.cornerRadius = NE_CORNER;
    _panelContainer.layer.cornerCurve = kCACornerCurveContinuous;
    _panelContainer.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    _panelContainer.layer.borderColor = NE_STROKE.CGColor;
    _panelContainer.layer.shadowColor = UIColor.blackColor.CGColor;
    _panelContainer.layer.shadowOpacity = 0.4;
    _panelContainer.layer.shadowRadius = 24;
    _panelContainer.layer.shadowOffset = CGSizeMake(0, 8);
    _panelContainer.clipsToBounds = YES;
    _panelContainer.hidden = YES;
    [self.rootViewController.view addSubview:_panelContainer];

    // 顶部拖动条：整块面板可自由拖动
    _dragHandle = [[UIView alloc] initWithFrame:CGRectZero];
    _dragHandle.backgroundColor = UIColor.clearColor;
    [_panelContainer addSubview:_dragHandle];

    UIView *grip = [[UIView alloc] initWithFrame:CGRectZero];
    grip.backgroundColor = NEColor(0xFFFFFF, 0.22);
    grip.layer.cornerRadius = 2;
    grip.tag = 9001;
    grip.userInteractionEnabled = NO;
    [_dragHandle addSubview:grip];

    // 拖动面板（不与内部滚动视图冲突：只在拖动条上响应）
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
                                   initWithTarget:self action:@selector(handlePanelPan:)];
    [_dragHandle addGestureRecognizer:pan];

    // iPad：允许从右下角调整大小
    UIPanGestureRecognizer *resize = [[UIPanGestureRecognizer alloc]
                                      initWithTarget:self action:@selector(handleResize:)];
    UIView *corner = [[UIView alloc] initWithFrame:CGRectZero];
    corner.tag = 9002;
    corner.backgroundColor = UIColor.clearColor;
    [corner addGestureRecognizer:resize];
    [_panelContainer addSubview:corner];
}

- (void)installPanelView:(UIView *)panelView {
    [self.panelView removeFromSuperview];
    self.panelView = panelView;
    panelView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.panelContainer insertSubview:panelView atIndex:0];
    panelView.frame = self.panelContainer.bounds;
    [self layoutPanelContent];
}

- (void)handlePanelPan:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self];
    [pan setTranslation:CGPointZero inView:self];
    CGPoint c = CGPointMake(self.panelContainer.center.x + t.x,
                            self.panelContainer.center.y + t.y);
    [self clampPanelCenter:&c];
    self.panelContainer.center = c;
}

- (void)handleResize:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self];
    [pan setTranslation:CGPointZero inView:self];
    CGSize s = CGSizeMake(self.panelContainer.bounds.size.width + t.x,
                          self.panelContainer.bounds.size.height + t.y);
    CGFloat minW = 280, minH = 320;
    CGFloat maxW = self.bounds.size.width - 24;
    CGFloat maxH = self.bounds.size.height - 80;
    s.width  = MAX(minW, MIN(s.width, maxW));
    s.height = MAX(minH, MIN(s.height, maxH));

    CGRect f = self.panelContainer.frame;
    f.size = s;
    // 保持左上角不动，避免拖动时跳动
    self.panelContainer.frame = f;
    [self layoutPanelContent];
}

- (void)layoutPanelContent {
    CGRect b = self.panelContainer.bounds;
    CGFloat handleH = 26;
    // 拖动条占据顶部，内容区避开它
    self.dragHandle.frame = CGRectMake(0, 0, b.size.width, handleH);
    UIView *grip = [self.dragHandle viewWithTag:9001];
    grip.frame = CGRectMake((b.size.width - 36) / 2, (handleH - 4) / 2, 36, 4);

    if (self.panelView) {
        self.panelView.frame = CGRectMake(0, handleH, b.size.width, b.size.height - handleH);
    }
    UIView *corner = [self.panelContainer viewWithTag:9002];
    corner.frame = CGRectMake(b.size.width - 26, b.size.height - 26, 26, 26);
}

#pragma mark - 默认尺寸（iPad / iPhone）

- (CGSize)defaultPanelSize {
    CGSize screen = self.bounds.size;
    BOOL pad = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) || screen.width >= 700;
    if (pad) {
        // iPad：更宽更长，接近网易云的横屏播放页比例
        CGFloat w = MIN(720, screen.width - 80);
        CGFloat h = MIN(560, screen.height - 120);
        return CGSizeMake(MAX(460, w), MAX(420, h));
    }
    // iPhone 横屏时也要收缩
    CGFloat w = MIN(NE_PANEL_WIDTH, screen.width - 24);
    CGFloat h = MIN(460, screen.height - 80);
    return CGSizeMake(w, MAX(300, h));
}

- (void)togglePanel {
    self.expanded = !self.expanded;
    if (self.expanded) {
        CGSize size = [self defaultPanelSize];
        if (self.panelContainer.bounds.size.width < 1) {
            self.panelContainer.bounds = CGRectMake(0, 0, size.width, size.height);
        }
        [self layoutPanelContent];
        [self centerPanelNearBall];

        self.panelContainer.hidden = NO;
        self.panelContainer.alpha = 0;
        self.panelContainer.transform = CGAffineTransformMakeScale(0.94, 0.94);
        [UIView animateWithDuration:0.26 delay:0
             usingSpringWithDamping:0.85 initialSpringVelocity:0.4
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            self.panelContainer.alpha = 1;
            self.panelContainer.transform = CGAffineTransformIdentity;
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.16 animations:^{
            self.panelContainer.alpha = 0;
            self.panelContainer.transform = CGAffineTransformMakeScale(0.96, 0.96);
        } completion:^(BOOL finished) {
            self.panelContainer.hidden = YES;
            self.panelContainer.alpha = 1;
            self.panelContainer.transform = CGAffineTransformIdentity;
            [self endEditing:YES];
        }];
    }
}

- (void)centerPanelNearBall {
    CGSize size = self.panelContainer.bounds.size;
    CGRect screen = self.bounds;
    CGPoint ballC = self.ball.center;

    CGFloat x = (ballC.x < screen.size.width / 2)
        ? ballC.x + NE_BALL_SIZE / 2 + 10
        : ballC.x - NE_BALL_SIZE / 2 - 10 - size.width;
    CGFloat y = ballC.y - size.height / 2;

    CGPoint c = CGPointMake(x + size.width / 2, y + size.height / 2);
    [self clampPanelCenter:&c];
    self.panelContainer.center = c;
}

- (void)clampPanelCenter:(CGPoint *)c {
    CGSize size = self.panelContainer.bounds.size;
    CGRect b = self.bounds;
    CGFloat margin = 8;
    CGFloat halfW = size.width / 2, halfH = size.height / 2;

    CGFloat minX = margin + halfW;
    CGFloat maxX = b.size.width - margin - halfW;
    CGFloat minY = 40 + halfH;
    CGFloat maxY = b.size.height - margin - halfH;

    if (minX > maxX) minX = maxX = b.size.width / 2;
    if (minY > maxY) minY = maxY = b.size.height / 2;

    c->x = MAX(minX, MIN(c->x, maxX));
    c->y = MAX(minY, MIN(c->y, maxY));
}

#pragma mark - 屏幕 / 旋转

- (void)observeNotifications {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(onOrientationChanged)
               name:UIDeviceOrientationDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(onOrientationChanged)
               name:UIWindowDidBecomeKeyNotification object:nil];
}

- (void)onOrientationChanged {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        // window 尺寸跟随屏幕
        CGRect screen = [UIScreen mainScreen].bounds;
        if (!CGSizeEqualToSize(self.bounds.size, screen.size)) {
            self.frame = screen;
        }
        if (self.hasPositioned) {
            CGPoint c = self.ball.center;
            CGFloat half = NE_BALL_SIZE / 2;
            c.x = MAX(half + 6, MIN(c.x, self.bounds.size.width - half - 6));
            c.y = MAX(half + 30, MIN(c.y, self.bounds.size.height - half - 30));
            self.ball.center = c;
        }
        if (self.expanded) {
            // 面板可能超出新屏幕，重新夹取并重排
            CGPoint c = self.panelContainer.center;
            [self clampPanelCenter:&c];
            self.panelContainer.center = c;
            [self layoutPanelContent];
        }
    });
}

- (void)presentBall {
    self.hidden = NO;
    if (self.hasPositioned) return;
    self.hasPositioned = YES;

    CGFloat top = 60;
    if (@available(iOS 11.0, *)) {
        top = self.safeAreaInsets.top + 44;
    }
    self.ball.center = CGPointMake(self.bounds.size.width - NE_BALL_SIZE / 2 - 10,
                                   top + NE_BALL_SIZE / 2);
}

@end