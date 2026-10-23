//  NEUITheme.h
//  唯一的视觉常量出口：换皮只改这个文件
#import <UIKit/UIKit.h>

static inline UIColor *NEColor(NSInteger hex, CGFloat alpha) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0
                           alpha:alpha];
}

#define NE_BRAND        NEColor(0xE60026, 1.0)
#define NE_BG           NEColor(0x121212, 1.0)
#define NE_PANEL        NEColor(0x1E1E1E, 0.96)
#define NE_CARD         NEColor(0x2A2A2A, 1.0)
#define NE_TEXT         NEColor(0xFFFFFF, 1.0)
#define NE_TEXT_DIM     NEColor(0xFFFFFF, 0.55)
#define NE_STROKE       NEColor(0xFFFFFF, 0.10)

static const CGFloat NE_BALL_SIZE   = 52.0;
static const CGFloat NE_PANEL_WIDTH = 340.0;
static const CGFloat NE_CORNER      = 22.0;