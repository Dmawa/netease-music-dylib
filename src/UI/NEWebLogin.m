#import "NEWebLogin.h"
#import "NEUITheme.h"
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
    NSString *v = [self currentMusicU];
    if (!v.length) return;
    if (self.initialMusicU.length && [v isEqualToString:self.initialMusicU]) return;

    [self.timer invalidate];
    self.timer = nil;
    void (^done)(void) = self.onSuccess;
    [self dismissViewControllerAnimated:YES completion:^{
        if (done) done();
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
