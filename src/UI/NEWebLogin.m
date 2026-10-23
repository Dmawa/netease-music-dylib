#import "NEWebLogin.h"
#import "NEUITheme.h"
#import "NESession.h"
#import <WebKit/WebKit.h>

/// 桌面 UA：移动端 UA 会进移动版页面，登录入口和网页版不一样
static NSString *const kNEWebLoginUA =
    @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    @"AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";

@interface NEWebLogin () <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
/// 打开网页前已有的 MUSIC_U，用来判断「这次登录成功后新写入的值」
@property (nonatomic, copy, nullable) NSString *initialMusicU;
@property (nonatomic, assign) BOOL finished;
@end

@implementation NEWebLogin

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = NE_BG;

    CGFloat top = 92;
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, top)];
    bar.backgroundColor = NE_PANEL;
    bar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:bar];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"关闭" forState:UIControlStateNormal];
    close.frame = CGRectMake(12, 44, 64, 36);
    [close addTarget:self action:@selector(handleClose) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:close];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(80, 44, self.view.bounds.size.width - 160, 36)];
    title.text = @"网易云网页登录";
    title.textAlignment = NSTextAlignmentCenter;
    title.textColor = NE_TEXT;
    title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [bar addSubview:title];

    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:@"已完成" forState:UIControlStateNormal];
    done.frame = CGRectMake(self.view.bounds.size.width - 76, 44, 64, 36);
    done.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [done addTarget:self action:@selector(manualCheck) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:done];

    _webView = [[WKWebView alloc] initWithFrame:CGRectMake(0, top, self.view.bounds.size.width,
                                                           self.view.bounds.size.height - top)
                                    configuration:[WKWebViewConfiguration new]];
    _webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _webView.navigationDelegate = self;
    _webView.customUserAgent = kNEWebLoginUA;
    [self.view addSubview:_webView];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.center = CGPointMake(self.view.bounds.size.width / 2, top + 40);
    _spinner.hidesWhenStopped = YES;
    [self.view addSubview:_spinner];
    [_spinner startAnimating];

    [_webView loadRequest:[NSURLRequest requestWithURL:
        [NSURL URLWithString:@"https://music.163.com/"]]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.initialMusicU = [self currentMusicU];
    [self.timer invalidate];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self
                                                selector:@selector(checkLogin)
                                                userInfo:nil repeats:YES];
    [self checkLogin];      // 已经有登录态时立刻接管
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.timer invalidate];
    self.timer = nil;
}

- (void)dealloc {
    [_timer invalidate];
}

#pragma mark - Cookie 检测

- (NSString *)currentMusicU {
    // MUSIC_U 一般是 HttpOnly，JS 读不到，但共享 Cookie 存储能读到
    for (NSHTTPCookie *c in [NSHTTPCookieStorage sharedHTTPCookieStorage].cookies) {
        if ([c.name isEqualToString:@"MUSIC_U"] &&
            [c.domain containsString:@"music.163.com"] && c.value.length) {
            return c.value;
        }
    }
    return nil;
}

- (void)checkLogin {
    // 1) 共享存储：有些系统版本会把 WKWebView 的 cookie 同步过来
    NSString *shared = [self currentMusicU];
    if (shared.length && ![shared isEqualToString:self.initialMusicU]) {
        [self finishLoginWithMusicU:shared cookies:nil];
        return;
    }

    // 2) WKWebView 自己的 cookie store：HttpOnly 的 MUSIC_U 只在这里，
    //    NSHTTPCookieStorage 往往看不到（这是「网页登录完没反应」的根因）
    WKHTTPCookieStore *store = self.webView.configuration.websiteDataStore.httpCookieStore;
    if (!store) return;
    __weak typeof(self) weakSelf = self;
    [store getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.finished) return;

        NSString *musicU = nil;
        for (NSHTTPCookie *c in cookies) {
            if ([c.name isEqualToString:@"MUSIC_U"] && c.value.length) musicU = c.value;
        }
        if (!musicU.length) return;
        if (self.initialMusicU.length && [musicU isEqualToString:self.initialMusicU]) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || self.finished) return;
            [self finishLoginWithMusicU:musicU cookies:cookies];
        });
    }];
}

/// 把网页登录拿到的 cookie 同步给共享存储和 NESession，然后回调成功
- (void)finishLoginWithMusicU:(NSString *)musicU cookies:(nullable NSArray<NSHTTPCookie *> *)cookies {
    if (self.finished) return;
    self.finished = YES;

    [self.timer invalidate];
    self.timer = nil;

    // 网页里的 163 cookie 全量同步进 NSHTTPCookieStorage（NSURLSession 就靠它）
    for (NSHTTPCookie *c in cookies) {
        if ([c.domain containsString:@"163.com"]) {
            [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookie:c];
        }
    }

    NSDictionary *props = @{
        NSHTTPCookieName: @"MUSIC_U",
        NSHTTPCookieValue: musicU,
        NSHTTPCookieDomain: @".music.163.com",
        NSHTTPCookiePath: @"/",
        NSHTTPCookieSecure: @"TRUE",
    };
    NSHTTPCookie *musicUCookie = [NSHTTPCookie cookieWithProperties:props];
    if (musicUCookie) [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookie:musicUCookie];

    // 直接写进 NESession 的 jar，避免依赖系统 Cookie 同步时机
    [[NESession shared] setCookieValue:musicU forName:@"MUSIC_U"];
    for (NSHTTPCookie *c in cookies) {
        if ([c.name isEqualToString:@"__csrf"] && c.value.length) {
            [[NESession shared] setCookieValue:c.value forName:@"__csrf"];
        }
    }

    NSLog(@"[NELogin] 网页登录完成，已同步 MUSIC_U（%lu 字节）",
          (unsigned long)musicU.length);

    void (^done)(void) = self.onSuccess;
    [self dismissViewControllerAnimated:YES completion:^{
        if (done) done();
    }];
}

#pragma mark - 手动确认

/// 用户点「已完成」：立刻查一次 WKWebView 的 cookie；没有就明确告诉他
- (void)manualCheck {
    WKHTTPCookieStore *store = self.webView.configuration.websiteDataStore.httpCookieStore;
    __weak typeof(self) weakSelf = self;
    [store getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.finished) return;

        NSString *musicU = nil;
        for (NSHTTPCookie *c in cookies) {
            if ([c.name isEqualToString:@"MUSIC_U"] && c.value.length) musicU = c.value;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || self.finished) return;
            if (musicU.length) {
                [self finishLoginWithMusicU:musicU cookies:cookies];
                return;
            }
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:@"还没检测到登录"
                                 message:@"请确认网页右上角已经显示头像（真正登录成功）。"
                                         @"如果已登录，请再等几秒；仍然不行，把当前页面截图发我。"
                          preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好"
                                                      style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    }];
}

#pragma mark - 交互

- (void)handleClose {
    [self.timer invalidate];
    self.timer = nil;
    void (^done)(void) = self.onCancel;
    [self dismissViewControllerAnimated:YES completion:^{
        if (done) done();
    }];
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self.spinner stopAnimating];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation
      withError:(NSError *)error {
    [self.spinner stopAnimating];
}

@end
