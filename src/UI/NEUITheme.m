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

/// 深色 -> 浅色 的配色映射：先按已知色对，再对灰阶做通用反相
static UIColor *NEMapColor(UIColor *c, BOOL toLight) {
    if (!c) return c;

    // 品牌红不动
    if (NEColorEqual(c, NEColor(0xE60026, 1.0))) return c;

    // 通用灰阶反相：近白 -> 近黑，近黑 -> 近白（保留 alpha）
    CGFloat r0 = 0, g0 = 0, b0 = 0, a0 = 0;
    if ([c getRed:&r0 green:&g0 blue:&b0 alpha:&a0]) {
        BOOL grayish = fabs(r0 - g0) < 0.06 && fabs(g0 - b0) < 0.06;
        if (grayish) {
            CGFloat lum = 0.299 * r0 + 0.587 * g0 + 0.114 * b0;
            if (toLight) {
                if (lum > 0.72) {
                    CGFloat target = MAX(0.06, 0.16 - (lum - 0.72) * 0.3);
                    return [UIColor colorWithRed:target green:target blue:target alpha:a0];
                }
                if (lum < 0.28 && a0 > 0.5) {
                    CGFloat target = MIN(0.98, 1.0 - lum * 0.35);
                    return [UIColor colorWithRed:target green:target blue:target alpha:a0];
                }
            } else {
                if (lum < 0.30 && a0 > 0.5) {
                    CGFloat target = MIN(1.0, 1.0 - lum * 0.5);
                    return [UIColor colorWithRed:target green:target blue:target alpha:a0];
                }
                if (lum > 0.90 && a0 > 0.9) {
                    return [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:a0];
                }
            }
        }
    }

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
    if (view.tag == NETagNoTheme) return;
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
        if (tv.backgroundView.backgroundColor) {
            UIColor *mapped = NEMapColor(tv.backgroundView.backgroundColor, light);
            if (mapped != tv.backgroundView.backgroundColor) tv.backgroundView.backgroundColor = mapped;
        }
    } else if ([view isKindOfClass:[UISearchBar class]]) {
        UISearchBar *sb = (UISearchBar *)view;
        UITextField *tf = [sb valueForKey:@"searchField"];
        if ([tf isKindOfClass:[UITextField class]]) {
            tf.backgroundColor = NE_CARD;
            tf.textColor = NE_TEXT;
            tf.attributedPlaceholder = [[NSAttributedString alloc]
                initWithString:tf.placeholder ?: @""
                    attributes:@{NSForegroundColorAttributeName: NE_TEXT_DIM}];
        }
    } else if ([view isKindOfClass:[UITableViewCell class]]) {
        UITableViewCell *cell = (UITableViewCell *)view;
        if (cell.textLabel.textColor) {
            UIColor *mapped = NEMapColor(cell.textLabel.textColor, light);
            if (mapped != cell.textLabel.textColor) cell.textLabel.textColor = mapped;
        }
        if (cell.detailTextLabel.textColor) {
            UIColor *mapped = NEMapColor(cell.detailTextLabel.textColor, light);
            if (mapped != cell.detailTextLabel.textColor) cell.detailTextLabel.textColor = mapped;
        }
        if (cell.selectedBackgroundView.backgroundColor) {
            UIColor *mapped = NEMapColor(cell.selectedBackgroundView.backgroundColor, light);
            if (mapped != cell.selectedBackgroundView.backgroundColor) {
                cell.selectedBackgroundView.backgroundColor = mapped;
            }
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
