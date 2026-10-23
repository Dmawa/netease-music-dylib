//  NEFloatingBall.h
//  悬浮窗容器：悬浮球 + 可自由拖动的面板
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NEFloatingBall : UIWindow

+ (instancetype)shared;

/// iOS 13+ 必须把窗口挂到活跃的 UIWindowScene，否则浮层不会显示
- (void)attachToScene:(UIWindowScene *)scene;

- (void)presentBall;
/// 面板内容由外部提供，便于整体替换 UI
- (void)installPanelView:(UIView *)panelView;

@end

NS_ASSUME_NONNULL_END