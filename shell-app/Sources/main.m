//  NEMusicShell — 空壳宿主 App
//  唯一用途：给 Player.dylib 提供进程与窗口，验证插件在真实设备上是否正常。
//  故意不做任何业务逻辑，也不 hook 任何东西。
#import <UIKit/UIKit.h>

@interface ShellViewController : UIViewController
@end

@implementation ShellViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.07 alpha:1];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(24, 120, 320, 40)];
    title.text = @"NEMusic 空壳宿主";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold];
    title.textAlignment = NSTextAlignmentCenter;
    title.center = CGPointMake(self.view.bounds.size.width / 2, 140);
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:title];

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(24, 180, 320, 90)];
    hint.text = @"若插件已注入，右上角应出现红色悬浮球。\n点击悬浮球展开播放器面板。";
    hint.numberOfLines = 0;
    hint.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    hint.font = [UIFont systemFontOfSize:14];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.center = CGPointMake(self.view.bounds.size.width / 2, 210);
    hint.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:hint];
}
@end

@interface ShellAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation ShellAppDelegate
- (BOOL)application:(UIApplication *)app
didFinishLaunchingWithOptions:(NSDictionary *)opts {
    // 窗口交给 scene delegate 创建：真实宿主（网易云）就是 scene 架构，
    // 空壳也必须一样，否则测不出「window 没挂 scene 就不显示」这类问题。
    return YES;
}
@end

#pragma mark - 场景代理

@interface ShellSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation ShellSceneDelegate

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
    options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    window.rootViewController = [ShellViewController new];
    self.window = window;
    [window makeKeyAndVisible];
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([ShellAppDelegate class]));
    }
}