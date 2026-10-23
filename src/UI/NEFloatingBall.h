//  NEFloatingBall.h
//  悬浮球 + 面板容器。唯一职责：把面板挂到窗口上、处理拖动与展开。
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NEFloatingBall : UIWindow

+ (instancetype)shared;

/// 显示悬浮球（幂等）
- (void)presentBall;
/// 面板内容由外部提供，便于整体替换 UI
- (void)installPanelView:(UIView *)panelView;

@end

NS_ASSUME_NONNULL_END