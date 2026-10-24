//  NEUITheme.h
//  唯一的视觉常量出口：换皮只改这个文件（支持深色 / 浅色运行时切换）
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 主题变化通知（切换黑白模式后发出）
extern NSString *const NEThemeChangedNotification;

/// 当前是否浅色模式
BOOL NELightModeEnabled(void);
/// 切换深浅色（会持久化并发出 NEThemeChangedNotification）
void NESetLightMode(BOOL light);

static inline UIColor *NEColor(NSInteger hex, CGFloat alpha) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0
                           alpha:alpha];
}

UIColor *NEBrandColor(void);
UIColor *NEBGColor(void);
UIColor *NEPanelColor(void);
UIColor *NECardColor(void);
UIColor *NETextColor(void);
UIColor *NETextDimColor(void);
UIColor *NEStrokeColor(void);

/// 递归把已有视图的配色换成当前主题（用于运行时切换）
void NEApplyThemeToView(UIView *view);

#define NE_BRAND        NEBrandColor()
#define NE_BG           NEBGColor()
#define NE_PANEL        NEPanelColor()
#define NE_CARD         NECardColor()
#define NE_TEXT         NETextColor()
#define NE_TEXT_DIM     NETextDimColor()
#define NE_STROKE       NEStrokeColor()

static const CGFloat NE_BALL_SIZE   = 52.0;
static const CGFloat NE_PANEL_WIDTH = 340.0;
static const CGFloat NE_CORNER      = 22.0;

NS_ASSUME_NONNULL_END
