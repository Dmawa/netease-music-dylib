#import "NEUITheme.h"

NSString *const NEThemeChangedNotification = @"NEThemeChangedNotification";

static NSString *const kNELightModeKey = @"NELightMode";
static BOOL gNELightMode = NO;
static BOOL gNELightModeLoaded = NO;

BOOL NELightModeEnabled(void) {
    if (!gNELightModeLoaded) {
        gNELightModeLoaded = YES;
        gNELightMode = [[NSUserDefaults standardUserDefaults] boolForKey:kNELightModeKey];
    }
    return gNELightMode;
}

void NESetLightMode(BOOL light) {
    gNELightModeLoaded = YES;
    if (gNELightMode == light) return;
    gNELightMode = light;
    [[NSUserDefaults standardUserDefaults] setBool:light forKey:kNELightModeKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:NEThemeChangedNotification object:nil];
}

UIColor *NEBrandColor(void) {
    return NEColor(0xE60026, 1.0);
}

UIColor *NEBGColor(void) {
    return NELightModeEnabled() ? NEColor(0xF6F6F6, 1.0) : NEColor(0x121212, 1.0);
}

UIColor *NEPanelColor(void) {
    return NELightModeEnabled() ? NEColor(0xFFFFFF, 0.97) : NEColor(0x1E1E1E, 0.96);
}

UIColor *NECardColor(void) {
    return NELightModeEnabled() ? NEColor(0xECECEC, 1.0) : NEColor(0x2A2A2A, 1.0);
}

UIColor *NETextColor(void) {
    return NELightModeEnabled() ? NEColor(0x1A1A1A, 1.0) : NEColor(0xFFFFFF, 1.0);
}

UIColor *NETextDimColor(void) {
    return NELightModeEnabled() ? NEColor(0x000000, 0.55) : NEColor(0xFFFFFF, 0.55);
}

UIColor *NEStrokeColor(void) {
    return NELightModeEnabled() ? NEColor(0x000000, 0.10) : NEColor(0xFFFFFF, 0.10);
}

#pragma mark - 运行时换肤

static BOOL NEColorEqual(UIColor *a, UIColor *b) {
    if (!a || !b) return NO;
    CGFloat r1 = 0, g1 = 0, b1 = 0, a1 = 0, r2 = 0, g2 = 0, b2 = 0, a2 = 0;
    if (![a getRed:&r1 green:&g1 blue:&b1 alpha:&a1]) return NO;
    if (![b getRed:&r2 green:&g2 blue:&b2 alpha:&a2]) return NO;
    return fabs(r1 - r2) < 0.01 && fabs(g1 - g2) < 0.01 &&
           fabs(b1 - b2) < 0.01 && fabs(a1 - a2) < 0.01;
}

/// 深色 -> 浅色 的已知配色映射
static UIColor *NEMapColor(UIColor *c, BOOL toLight) {
    if (!c) return c;
    // 背景
    if (NEColorEqual(c, NEColor(0x121212, 1.0))) return toLight ? NEColor(0xF6F6F6, 1.0) : c;
    if (NEColorEqual(c, NEColor(0xF6F6F6, 1.0))) return toLight ? c : NEColor(0x121212, 1.0);
    // 面板
    if (NEColorEqual(c, NEColor(0x1E1E1E, 0.96))) return toLight ? NEColor(0xFFFFFF, 0.97) : c;
    if (NEColorEqual(c, NEColor(0xFFFFFF, 0.97))) return toLight ? c : NEColor(0x1E1E1E, 0.96);
    // 卡片
    if (NEColorEqual(c, NEColor(0x2A2A2A, 1.0))) return toLight ? NEColor(0xECECEC, 1.0) : c;
    if (NEColorEqual(c, NEColor(0xECECEC, 1.0))) return toLight ? c : NEColor(0x2A2A2A, 1.0);
    // 正文
    if (NEColorEqual(c, NEColor(0xFFFFFF, 1.0))) return toLight ? NEColor(0x1A1A1A, 1.0) : c;
    if (NEColorEqual(c, NEColor(0x1A1A1A, 1.0))) return toLight ? c : NEColor(0xFFFFFF, 1.0);
    // 次要文字
    if (NEColorEqual(c, NEColor(0xFFFFFF, 0.55))) return toLight ? NEColor(0x000000, 0.55) : c;
    if (NEColorEqual(c, NEColor(0x000000, 0.55))) return toLight ? c : NEColor(0xFFFFFF, 0.55);
    // 描边
    if (NEColorEqual(c, NEColor(0xFFFFFF, 0.10))) return toLight ? NEColor(0x000000, 0.10) : c;
    if (NEColorEqual(c, NEColor(0x000000, 0.10))) return toLight ? c : NEColor(0xFFFFFF, 0.10);
    return c;
}

void NEApplyThemeToView(UIView *view) {
    if (!view) return;
    BOOL light = NELightModeEnabled();

    if (view.backgroundColor) {
        UIColor *mapped = NEMapColor(view.backgroundColor, light);
        if (mapped != view.backgroundColor) view.backgroundColor = mapped;
    }
    if (view.tintColor) {
        UIColor *mapped = NEMapColor(view.tintColor, light);
        if (mapped != view.tintColor) view.tintColor = mapped;
    }
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        if (label.textColor) {
            UIColor *mapped = NEMapColor(label.textColor, light);
            if (mapped != label.textColor) label.textColor = mapped;
        }
    } else if ([view isKindOfClass:[UIButton class]]) {
        UIButton *button = (UIButton *)view;
        UIColor *title = [button titleColorForState:UIControlStateNormal];
        if (title) {
            UIColor *mapped = NEMapColor(title, light);
            if (mapped != title) [button setTitleColor:mapped forState:UIControlStateNormal];
        }
    } else if ([view isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)view;
        if (tf.textColor) {
            UIColor *mapped = NEMapColor(tf.textColor, light);
            if (mapped != tf.textColor) tf.textColor = mapped;
        }
    } else if ([view isKindOfClass:[UITextView class]]) {
        UITextView *tv = (UITextView *)view;
        if (tv.textColor) {
            UIColor *mapped = NEMapColor(tv.textColor, light);
            if (mapped != tv.textColor) tv.textColor = mapped;
        }
    } else if ([view isKindOfClass:[UITableView class]]) {
        UITableView *tv = (UITableView *)view;
        if (tv.separatorColor) {
            UIColor *mapped = NEMapColor(tv.separatorColor, light);
            if (mapped != tv.separatorColor) tv.separatorColor = mapped;
        }
    } else if ([view isKindOfClass:[UISlider class]]) {
        UISlider *slider = (UISlider *)view;
        if (slider.maximumTrackTintColor) {
            UIColor *mapped = NEMapColor(slider.maximumTrackTintColor, light);
            if (mapped != slider.maximumTrackTintColor) slider.maximumTrackTintColor = mapped;
        }
    }

    for (UIView *sub in view.subviews) NEApplyThemeToView(sub);
}
