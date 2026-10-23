//  NEEntry.m
//  dylib 入口。
//
//  设计要点（与"hook 宿主"严格区分）：
//    · 不使用 MobileSubstrate / fishhook / method swizzling
//    · 不改宿主任何类、方法或 UI
//    · 只在自己的 UIWindow 上装界面，靠 dylib 构造器自动启动
//  因此它只是一个"寄生在宿主进程里的独立浮层程序"，卸载 dylib 即完全消失。
#import <UIKit/UIKit.h>
#import "NEFloatingBall.h"
#import "NEMainPanel.h"

__attribute__((constructor))
static void NEMusicBootstrap(void) {
    // 构造器可能在非主线程/极早期执行，统一挪到主队列且等 App 起来
    dispatch_async(dispatch_get_main_queue(), ^{
        [NEEntry launch];
    });
}

@interface NEEntry : NSObject
+ (void)launch;
@end

@implementation NEEntry

+ (void)launch {
    // 宿主 App 尚未完成启动时，延迟重试，最多约 10 秒
    static NSInteger attempts = 0;
    UIApplication *app = [UIApplication sharedApplication];
    BOOL ready = (app != nil);
    if (@available(iOS 13.0, *)) {
        // 有活跃 scene 才算真正起来了，否则 UIWindow 挂不上去
        BOOL hasScene = NO;
        for (UIScene *s in app.connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]] &&
                s.activationState != UISceneActivationStateUnattached) { hasScene = YES; break; }
        }
        ready = ready && hasScene;
    }
    if (!ready) {
        attempts++;
        if (attempts > 40) {
            NSLog(@"[NEMusic] 宿主长时间未就绪，放弃注入");
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [NEEntry launch]; });
        return;
    }

    static BOOL installed = NO;
    if (installed) return;
    installed = YES;

    NEFloatingBall *ball = [NEFloatingBall shared];
    NEMainPanel *panel = [[NEMainPanel alloc] initWithFrame:CGRectMake(0, 0, 320, 460)];
    [ball installPanelView:panel];
    [ball presentBall];
    [panel start];

    NSLog(@"[NEMusic] 已注入，悬浮球就绪");
}

@end