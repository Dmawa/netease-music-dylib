#import "NELyricView.h"
#import "NEUITheme.h"

/*
 *  性能要点（上一版卡顿的根因都在这里）：
 *   1. 不再每帧遍历所有行：只有「正在唱的行」需要重绘
 *   2. 逐字点亮用「遮罩裁剪」而不是每帧重建富文本：
 *      同一段文字画两遍（亮色打底 + 暗色覆盖），
 *      用已唱宽度裁剪暗色层，等价于逐字点亮但开销极小
 *   3. 文本高度只在布局时算一次并缓存，drawRect 里不做测量
 *   4. 所有 UI 更新合并到 displayLink 一帧内，避免重复 setNeedsDisplay
 */

/// 一行歌词
@interface NELyricLineView : UIView
@property (nonatomic, strong) NELyricLine *line;
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) BOOL showsTranslation;
@property (nonatomic, assign) CGFloat fontSize;
/// 已唱比例 0..1（由父视图每帧写入）
@property (nonatomic, assign) CGFloat highlightProgress;
/// 布局时预先算好的行高，drawRect 直接复用
@property (nonatomic, assign) CGFloat cachedTextHeight;
@property (nonatomic, assign) CGFloat cachedTransHeight;
@end

@implementation NELyricLineView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        self.layer.drawsAsynchronously = YES;   // 离屏绘制，减轻主线程压力
    }
    return self;
}

- (void)setLine:(NELyricLine *)line { _line = line; [self setNeedsDisplay]; }

/// 只在值真的变了才重绘 —— 这是流畅度的关键
- (void)setActive:(BOOL)active {
    if (_active == active) return;
    _active = active;
    [self setNeedsDisplay];
}

- (void)setHighlightProgress:(CGFloat)p {
    p = MAX(0, MIN(1, p));
    if (fabs(_highlightProgress - p) < 0.002) return;
    _highlightProgress = p;
    [self setNeedsDisplay];
}

- (void)setShowsTranslation:(BOOL)v {
    if (_showsTranslation == v) return;
    _showsTranslation = v;
    [self setNeedsDisplay];
}

- (UIFont *)textFont {
    return [UIFont systemFontOfSize:_fontSize
                             weight:self.active ? UIFontWeightSemibold : UIFontWeightMedium];
}

- (NSMutableParagraphStyle *)paragraphStyle {
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    ps.alignment = NSTextAlignmentCenter;
    ps.lineBreakMode = NSLineBreakByWordWrapping;
    return ps;
}

/// 仅供参考：布局阶段调用一次，结果缓存
+ (CGFloat)heightForText:(NSString *)text font:(UIFont *)font width:(CGFloat)width {
    if (!text.length) return 0;
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    ps.alignment = NSTextAlignmentCenter;
    ps.lineBreakMode = NSLineBreakByWordWrapping;
    NSDictionary *attr = @{NSFontAttributeName: font, NSParagraphStyleAttributeName: ps};
    CGRect r = [text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
                                 options:NSStringDrawingUsesLineFragmentOrigin
                              attributes:attr context:nil];
    return ceil(r.size.height);
}

- (void)drawRect:(CGRect)rect {
    NSString *text = self.line.text;
    if (!text.length) return;

    CGFloat w = self.bounds.size.width;
    UIFont *font = [self textFont];
    NSMutableParagraphStyle *ps = [self paragraphStyle];
    CGFloat textH = self.cachedTextHeight > 0 ? self.cachedTextHeight
                                              : [NELyricLineView heightForText:text font:font width:w];

    NSDictionary *doneAttr = @{NSFontAttributeName: font,
                               NSParagraphStyleAttributeName: ps,
                               NSForegroundColorAttributeName: NE_TEXT};
    NSDictionary *waitAttr = @{NSFontAttributeName: font,
                               NSParagraphStyleAttributeName: ps,
                               NSForegroundColorAttributeName: NEColor(0xFFFFFF, 0.32)};
    CGRect textRect = CGRectMake(0, 0, w, textH);

    if (!self.active) {
        // 非当前行：只画暗色，一次绘制
        [text drawWithRect:textRect options:NSStringDrawingUsesLineFragmentOrigin
                attributes:waitAttr context:nil];
    } else {
        // 当前行：先铺亮色，再用裁剪把「未唱部分」覆盖成暗色
        [text drawWithRect:textRect options:NSStringDrawingUsesLineFragmentOrigin
                attributes:doneAttr context:nil];

        CGFloat progress = MAX(0, MIN(1, self.highlightProgress));
        if (progress < 0.999) {
            CGContextRef ctx = UIGraphicsGetCurrentContext();
            CGContextSaveGState(ctx);

            // 已唱宽度：从左到右（与网易云一致）
            CGFloat doneW = w * progress;
            // 未唱区域裁剪矩形
            CGRect remaining = CGRectMake(doneW, 0, w - doneW, self.bounds.size.height);
            CGContextClipToRect(ctx, remaining);

            [text drawWithRect:textRect options:NSStringDrawingUsesLineFragmentOrigin
                    attributes:waitAttr context:nil];
            CGContextRestoreGState(ctx);
        }
    }

    // 翻译
    if (self.showsTranslation && self.line.translation.length) {
        UIFont *tf = [UIFont systemFontOfSize:self.fontSize * 0.76];
        CGFloat th = self.cachedTransHeight > 0 ? self.cachedTransHeight
                    : [NELyricLineView heightForText:self.line.translation font:tf width:w];
        NSDictionary *ta = @{NSFontAttributeName: tf,
                             NSParagraphStyleAttributeName: ps,
                             NSForegroundColorAttributeName:
                                 NEColor(0xFFFFFF, self.active ? 0.60 : 0.26)};
        [self.line.translation drawWithRect:CGRectMake(0, textH + 3, w, th)
                                    options:NSStringDrawingUsesLineFragmentOrigin
                                 attributes:ta context:nil];
    }
}

@end

#pragma mark - 歌词容器

@interface NELyricView () <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIView *content;
@property (nonatomic, strong) NSMutableArray<NELyricLineView *> *lineViews;
@property (nonatomic, strong) UILabel *emptyLabel;

@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, assign) NSInteger scrolledIndex;

@property (nonatomic, assign) BOOL userDragging;
@property (nonatomic, assign) NSTimeInterval dragEndAt;

@property (nonatomic, strong, nullable) CADisplayLink *displayLink;
@property (nonatomic, assign) double anchorTime;
@property (nonatomic, assign) CFTimeInterval anchorAt;

@property (nonatomic, assign) CGFloat lastLayoutWidth;
@property (nonatomic, assign) CGFloat lastLayoutHeight;
@property (nonatomic, assign) BOOL layoutDone;
@end

@implementation NELyricView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _showsTranslation = YES;
        _currentIndex = -1;
        _scrolledIndex = -1;
        _lineViews = [NSMutableArray array];

        _scroll = [[UIScrollView alloc] initWithFrame:self.bounds];
        _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _scroll.showsVerticalScrollIndicator = NO;
        _scroll.delegate = self;
        _scroll.alwaysBounceVertical = YES;
        [self addSubview:_scroll];

        _content = [[UIView alloc] initWithFrame:CGRectZero];
        [_scroll addSubview:_content];

        _emptyLabel = [[UILabel alloc] initWithFrame:self.bounds];
        _emptyLabel.text = @"暂无歌词";
        _emptyLabel.textAlignment = NSTextAlignmentCenter;
        _emptyLabel.textColor = NE_TEXT_DIM;
        _emptyLabel.font = [UIFont systemFontOfSize:14];
        _emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _emptyLabel.hidden = YES;
        [self addSubview:_emptyLabel];
    }
    return self;
}

#pragma mark - 数据

- (void)setLyric:(NELyric *)lyric {
    _lyric = lyric;
    [self rebuild];
}

- (void)setShowsTranslation:(BOOL)showsTranslation {
    _showsTranslation = showsTranslation;
    for (NELyricLineView *v in self.lineViews) v.showsTranslation = showsTranslation;
    self.layoutDone = NO;
    [self setNeedsLayout];
}

- (void)setPlaying:(BOOL)playing {
    _playing = playing;
    if (playing) [self startDisplayLink];
    else {
        [self stopDisplayLink];
        // 暂停时用最后已知时间重绘一次
        [self applyHighlight];
    }
}

- (void)rebuild {
    for (NELyricLineView *v in self.lineViews) [v removeFromSuperview];
    [self.lineViews removeAllObjects];
    self.currentIndex = -1;
    self.scrolledIndex = -1;
    self.layoutDone = NO;

    NSArray<NELyricLine *> *lines = self.lyric.lines;
    self.emptyLabel.hidden = lines.count > 0;
    if (!lines.count) {
        self.content.frame = CGRectZero;
        return;
    }
    for (NELyricLine *l in lines) {
        NELyricLineView *v = [[NELyricLineView alloc] initWithFrame:CGRectZero];
        v.line = l;
        v.showsTranslation = self.showsTranslation;
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
                                       initWithTarget:self action:@selector(handleTap:)];
        [v addGestureRecognizer:tap];
        v.userInteractionEnabled = YES;
        [self.content addSubview:v];
        [self.lineViews addObject:v];
    }

    // 立即排版：把 layoutDone 复位后同步走一次 layoutSubviews，
    // 保证歌词加载完当帧就能显示，不需要用户手动刷新
    self.layoutDone = NO;
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

#pragma mark - 布局（只在尺寸变化时做一次）

- (CGFloat)fontSizeForWidth:(CGFloat)w {
    if (w >= 560) return 20;
    if (w >= 380) return 16;
    return 15;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.scroll.frame = self.bounds;

    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    // 页面还没显示时尺寸为 0，此时排版会算出错误高度，
    // 保持 layoutDone = NO，等真正出现时再排一次
    if (w < 1 || h < 1) {
        self.layoutDone = NO;
        return;
    }
    // 注意：歌词是异步加载的，加载完成时 view 尺寸没有变化，
    // 如果这里直接 return，新歌词永远排不上版（所有行高度为 0）。
    // 因此用 layoutDone 标记「是否需要强制重排」。
    if (self.layoutDone &&
        fabs(w - self.lastLayoutWidth) < 0.5 &&
        fabs(h - self.lastLayoutHeight) < 0.5) {
        return;
    }
    self.lastLayoutWidth = w;
    self.lastLayoutHeight = h;

    CGFloat pad = 20;
    CGFloat textW = MAX(60, w - pad * 2);
    CGFloat gap = 16;
    CGFloat fontSize = [self fontSizeForWidth:w];

    CGFloat y = 0;
    NSMutableArray<NSNumber *> *heights = [NSMutableArray array];

    for (NELyricLineView *v in self.lineViews) {
        v.fontSize = fontSize;
        v.showsTranslation = self.showsTranslation;

        CGFloat th = [NELyricLineView heightForText:v.line.text
                                               font:[v textFont] width:textW];
        CGFloat trh = 0;
        if (self.showsTranslation && v.line.translation.length) {
            UIFont *tf = [UIFont systemFontOfSize:fontSize * 0.76];
            trh = [NELyricLineView heightForText:v.line.translation font:tf width:textW];
        }
        v.cachedTextHeight = th;
        v.cachedTransHeight = trh;

        CGFloat total = th + (trh > 0 ? trh + 3 : 0);
        [heights addObject:@(total)];
        v.frame = CGRectMake(pad, y, textW, total);
        y += total + gap;
    }

    // 上下留白，让第一/最后一行也能滚到中间
    CGFloat half = h * 0.45;
    self.content.frame = CGRectMake(0, 0, w, y + half * 2);
    CGFloat cy = half;
    for (NSInteger i = 0; i < (NSInteger)self.lineViews.count; i++) {
        NELyricLineView *v = self.lineViews[i];
        v.frame = CGRectMake(pad, cy, textW, [heights[i] doubleValue]);
        cy += [heights[i] doubleValue] + gap;
    }
    self.scroll.contentSize = self.content.bounds.size;
    self.scroll.contentInset = UIEdgeInsetsZero;

    self.scrolledIndex = -1;
    self.layoutDone = YES;
    [self applyHighlight];
    [self scrollToCurrentAnimated:NO];
}

- (void)handleTap:(UITapGestureRecognizer *)g {
    NELyricLineView *v = (NELyricLineView *)g.view;
    if (![v isKindOfClass:[NELyricLineView class]]) return;
    if ([self.delegate respondsToSelector:@selector(lyricView:didSeekToTime:)]) {
        [self.delegate lyricView:self didSeekToTime:v.line.start];
    }
    self.userDragging = NO;
    self.dragEndAt = 0;
}

#pragma mark - 时间

- (void)setCurrentTime:(double)currentTime {
    _currentTime = currentTime;
    self.anchorTime = currentTime;
    self.anchorAt = CACurrentMediaTime();

    // 如果不播放，就没有 displayLink，需要手动刷新一次
    if (!self.displayLink) [self applyHighlight];
}

- (void)startDisplayLink {
    if (self.displayLink) return;
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    self.displayLink.preferredFrameRateRange =
        CAFrameRateRangeMake(30, 60, 60);      // 支持 ProMotion，省电时自动降
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopDisplayLink {
    [self.displayLink invalidate];
    self.displayLink = nil;
}

- (void)tick {
    double t = self.anchorTime;
    if (self.playing) {
        t += (CACurrentMediaTime() - self.anchorAt);
        if (!isfinite(t) || t < 0) t = 0;
    }
    _currentTime = t;

    NSInteger prev = self.currentIndex;
    [self applyHighlight];

    // 只有切换行才滚动，避免每帧都起动画
    if (self.currentIndex != prev) {
        [self followIfNeeded];
    }
}

/// 只更新「当前行」和「上一行」，其余行一律不碰
- (void)applyHighlight {
    NSInteger n = (NSInteger)self.lineViews.count;
    if (!n) return;

    NSInteger idx = [self.lyric indexAtTime:self.currentTime];
    NSInteger prev = self.currentIndex;

    if (idx == prev) {
        // 同一行：只更新该行进度
        if (idx >= 0 && idx < n) {
            NELyricLineView *v = self.lineViews[idx];
            v.highlightProgress = [self progressForLine:v.line atTime:self.currentTime];
        }
        return;
    }

    // 换行：只重绘「旧行」和「新行」
    if (prev >= 0 && prev < n) {
        NELyricLineView *pv = self.lineViews[prev];
        pv.active = NO;
        pv.highlightProgress = 0;
    }
    if (idx >= 0 && idx < n) {
        NELyricLineView *nv = self.lineViews[idx];
        nv.active = YES;
        nv.highlightProgress = [self progressForLine:nv.line atTime:self.currentTime];
    }
    self.currentIndex = idx;
}

- (CGFloat)progressForLine:(NELyricLine *)line atTime:(double)t {
    if (!line) return 0;
    if (line.chars.count) {
        // 逐字：按「当前字的起止时间」在字内部做线性插值，
        // 这样字与字之间是连续过渡而不是一格一格跳
        double total = line.chars.count;
        double done = 0;
        for (NELyricChar *c in line.chars) {
            double s = c.start;
            double e = (c.end > c.start) ? c.end : c.start + 0.12;
            if (t >= e) { done += 1; continue; }
            if (t <= s) break;
            done += (t - s) / MAX(0.0001, e - s);
            break;
        }
        // 按字数加权，长句子更贴近视觉
        return (CGFloat)MAX(0, MIN(1, done / total));
    }
    double span = (line.end > line.start) ? (line.end - line.start) : 2.0;
    return (CGFloat)MAX(0, MIN(1, (t - line.start) / MAX(0.15, span)));
}

- (void)followIfNeeded {
    if (self.userDragging) return;
    if (self.dragEndAt > 0 && CACurrentMediaTime() - self.dragEndAt < 3.0) return;
    [self scrollToCurrentAnimated:YES];
}

- (void)scrollToCurrentAnimated:(BOOL)animated {
    NSInteger idx = self.currentIndex;
    if (idx < 0 || idx >= (NSInteger)self.lineViews.count) return;
    if (self.scrolledIndex == idx) return;
    self.scrolledIndex = idx;

    NELyricLineView *v = self.lineViews[idx];
    CGFloat target = CGRectGetMidY(v.frame) - self.bounds.size.height * 0.42;
    CGFloat maxY = MAX(0, self.scroll.contentSize.height - self.bounds.size.height);
    target = MAX(0, MIN(target, maxY));

    if (animated) {
        [UIView animateWithDuration:0.42 delay:0
                            options:UIViewAnimationOptionCurveEaseInOut |
                                    UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            self.scroll.contentOffset = CGPointMake(0, target);
        } completion:nil];
    } else {
        self.scroll.contentOffset = CGPointMake(0, target);
    }
}

#pragma mark - 滚动

- (void)scrollViewWillBeginDragging:(UIScrollView *)sv {
    self.userDragging = YES;
}

- (void)scrollViewDidEndDragging:(UIScrollView *)sv willDecelerate:(BOOL)decelerate {
    if (!decelerate) {
        self.userDragging = NO;
        self.dragEndAt = CACurrentMediaTime();
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)sv {
    self.userDragging = NO;
    self.dragEndAt = CACurrentMediaTime();
}

- (void)willMoveToWindow:(UIWindow *)newWindow {
    [super willMoveToWindow:newWindow];
    if (!newWindow) [self stopDisplayLink];
}

- (void)dealloc {
    [_displayLink invalidate];
}

@end