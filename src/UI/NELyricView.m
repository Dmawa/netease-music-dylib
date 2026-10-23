#import "NELyricView.h"
#import "NEUITheme.h"
#import <CoreText/CoreText.h>

/// 一行歌词的绘制视图：支持逐字点亮（已唱部分高亮，未唱部分灰）
@interface NELyricLineView : UIView
@property (nonatomic, strong) NELyricLine *line;
@property (nonatomic, assign) CGFloat highlightProgress;   // 0..1，无逐字时用整行渐变
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) BOOL showsTranslation;
@property (nonatomic, assign) CGFloat fontSize;
/// 该行当前播放时间（由父视图每帧写入，避免 drawRect 里查全局）
@property (nonatomic, assign) double currentTimeForLine;
@end

@implementation NELyricLineView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}

- (void)setLine:(NELyricLine *)line { _line = line; [self setNeedsDisplay]; }
- (void)setHighlightProgress:(CGFloat)p {
    p = MAX(0, MIN(1, p));
    // 逐字点亮需要 60fps 级别的更新，阈值放得很小（只用来省掉完全无变化的帧）
    if (fabs(_highlightProgress - p) < 0.0005) return;
    _highlightProgress = p;
    [self setNeedsDisplay];
}
- (void)setActive:(BOOL)active { _active = active; [self setNeedsDisplay]; }
- (void)setShowsTranslation:(BOOL)v { _showsTranslation = v; [self setNeedsDisplay]; }
- (void)setFontSize:(CGFloat)s { _fontSize = s; [self setNeedsDisplay]; }

- (UIFont *)textFont {
    return [UIFont systemFontOfSize:_fontSize weight:self.active ? UIFontWeightSemibold : UIFontWeightMedium];
}

- (CGFloat)measuredHeightForWidth:(CGFloat)width {
    if (!self.line) return 0;
    UIFont *f = [self textFont];
    CGFloat h = [self heightForText:self.line.text font:f width:width];
    if (self.showsTranslation && self.line.translation.length) {
        h += [self heightForText:self.line.translation
                            font:[UIFont systemFontOfSize:_fontSize * 0.76]
                           width:width] + 3;
    }
    return ceil(h);
}

- (CGFloat)heightForText:(NSString *)text font:(UIFont *)font width:(CGFloat)width {
    if (!text.length) return 0;
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    ps.alignment = NSTextAlignmentCenter;
    ps.lineBreakMode = NSLineBreakByWordWrapping;
    NSDictionary *attr = @{NSFontAttributeName: font, NSParagraphStyleAttributeName: ps};
    CGRect r = [text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
                                 options:NSStringDrawingUsesLineFragmentOrigin
                              attributes:attr context:nil];
    return r.size.height;
}

- (void)drawRect:(CGRect)rect {
    if (!self.line.text.length) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat w = self.bounds.size.width;

    UIFont *font = [self textFont];
    UIColor *doneColor = NE_TEXT;                       // 已唱：亮白
    UIColor *waitColor = NEColor(0xFFFFFF, 0.34);       // 未唱：暗灰

    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    ps.alignment = NSTextAlignmentCenter;
    ps.lineBreakMode = NSLineBreakByWordWrapping;

    CGFloat textH = [self heightForText:self.line.text font:font width:w];
    CGFloat y = 0;

    // ---- 正文 ----
    NSDictionary *base = @{NSFontAttributeName: font,
                           NSParagraphStyleAttributeName: ps,
                           NSForegroundColorAttributeName: waitColor};

    if (self.active && self.line.chars.count) {
        // 逐字点亮：把整行拆成「已唱」和「未唱」两段，分别绘制
        NSMutableAttributedString *full = [[NSMutableAttributedString alloc]
                                           initWithString:self.line.text attributes:base];
        [full addAttribute:NSForegroundColorAttributeName value:doneColor
                     range:NSMakeRange(0, 0)];

        // 计算已唱字符数
        NSUInteger doneLen = 0;
        for (NELyricChar *c in self.line.chars) {
            if (c.start <= self.currentTimeForLine) doneLen += c.text.length;
            else break;
        }
        doneLen = MIN(doneLen, self.line.text.length);
        if (doneLen > 0) {
            [full addAttribute:NSForegroundColorAttributeName value:doneColor
                         range:NSMakeRange(0, doneLen)];
        }
        [full drawWithRect:CGRectMake(0, y, w, textH)
                   options:NSStringDrawingUsesLineFragmentOrigin context:nil];
    } else if (self.active) {
        // 没有逐字：按整行进度做两段式显示
        NSUInteger total = self.line.text.length;
        NSUInteger doneLen = (NSUInteger)floor(total * self.highlightProgress);
        doneLen = MIN(doneLen, total);
        NSMutableAttributedString *full = [[NSMutableAttributedString alloc]
                                           initWithString:self.line.text attributes:base];
        if (doneLen > 0) {
            [full addAttribute:NSForegroundColorAttributeName value:doneColor
                         range:NSMakeRange(0, doneLen)];
        }
        [full drawWithRect:CGRectMake(0, y, w, textH)
                   options:NSStringDrawingUsesLineFragmentOrigin context:nil];
    } else {
        [self.line.text drawWithRect:CGRectMake(0, y, w, textH)
                             options:NSStringDrawingUsesLineFragmentOrigin
                          attributes:base context:nil];
    }
    y += textH;

    // ---- 翻译 ----
    if (self.showsTranslation && self.line.translation.length) {
        UIFont *tf = [UIFont systemFontOfSize:_fontSize * 0.76];
        CGFloat th = [self heightForText:self.line.translation font:tf width:w];
        NSDictionary *ta = @{NSFontAttributeName: tf,
                             NSParagraphStyleAttributeName: ps,
                             NSForegroundColorAttributeName: NEColor(0xFFFFFF, self.active ? 0.62 : 0.28)};
        [self.line.translation drawWithRect:CGRectMake(0, y + 3, w, th)
                                    options:NSStringDrawingUsesLineFragmentOrigin
                                 attributes:ta context:nil];
    }
}

@end

#pragma mark - 歌词视图

@interface NELyricView () <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIView *content;
@property (nonatomic, strong) NSMutableArray<NELyricLineView *> *lineViews;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, assign) BOOL userDragging;      // 用户正在拖：暂停自动滚动
@property (nonatomic, assign) NSTimeInterval dragEndAt;
@property (nonatomic, assign) CGFloat lastLayoutWidth;
@property (nonatomic, assign) CGFloat lastLayoutHeight;
@property (nonatomic, assign) NSInteger scrolledIndex;
/// 显示链接：把「最近一次已知播放时间」插值成 60fps，避免 0.5s 一跳
@property (nonatomic, strong, nullable) CADisplayLink *displayLink;
@property (nonatomic, assign) double anchorTime;        // 最近一次外部给定的时间
@property (nonatomic, assign) CFTimeInterval anchorAt;  // 该时间对应的机器时刻

@end

@implementation NELyricView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _showsTranslation = YES;
        _currentIndex = -1;
        _lineViews = [NSMutableArray array];

        _scroll = [[UIScrollView alloc] initWithFrame:self.bounds];
        _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _scroll.showsVerticalScrollIndicator = NO;
        _scroll.delegate = self;
        _scroll.alwaysBounceVertical = YES;
        _scroll.decelerationRate = UIScrollViewDecelerationRateFast;
        [self addSubview:_scroll];

        _content = [[UIView alloc] initWithFrame:CGRectZero];
        [_scroll addSubview:_content];

        _emptyLabel = [[UILabel alloc] initWithFrame:self.bounds];
        _emptyLabel.text = @"暂无歌词";
        _emptyLabel.textAlignment = NSTextAlignmentCenter;
        _emptyLabel.textColor = NE_TEXT_DIM;
        _emptyLabel.font = [UIFont systemFontOfSize:14];
        _emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_emptyLabel];
    }
    return self;
}

- (void)setLyric:(NELyric *)lyric {
    _lyric = lyric;
    [self reload];
}

- (void)setShowsTranslation:(BOOL)showsTranslation {
    _showsTranslation = showsTranslation;
    for (NELyricLineView *v in self.lineViews) v.showsTranslation = showsTranslation;
    [self setNeedsLayout];
}

#pragma mark - 构建行视图

- (void)reload {
    for (NELyricLineView *v in self.lineViews) [v removeFromSuperview];
    [self.lineViews removeAllObjects];
    self.currentIndex = -1;
    self.scrolledIndex = -1;

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
    [self setNeedsLayout];
}

- (void)handleTap:(UITapGestureRecognizer *)g {
    NELyricLineView *v = (NELyricLineView *)g.view;
    if (![v isKindOfClass:[NELyricLineView class]]) return;
    if ([self.delegate respondsToSelector:@selector(lyricView:didSeekToTime:)]) {
        [self.delegate lyricView:self didSeekToTime:v.line.start];
    }
    // 点完恢复自动跟随
    self.userDragging = NO;
    self.dragEndAt = 0;
}

#pragma mark - 布局

- (CGFloat)fontSize {
    BOOL wide = self.bounds.size.width > 500;
    return wide ? 19.0 : 16.0;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.scroll.frame = self.bounds;

    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    // 尺寸没变就不重排：避免每次刷新都做全量文本测量
    if (fabs(w - self.lastLayoutWidth) < 0.5 &&
        fabs(h - self.lastLayoutHeight) < 0.5 &&
        self.lineViews.count) {
        return;
    }
    self.lastLayoutWidth = w;
    self.lastLayoutHeight = h;

    CGFloat pad = 24;
    CGFloat textW = MAX(60, w - pad * 2);
    CGFloat gap = 18;
    CGFloat y = 0;

    for (NELyricLineView *v in self.lineViews) {
        v.fontSize = [self fontSize];
        CGFloat h = [v measuredHeightForWidth:textW];
        v.frame = CGRectMake(pad, y, textW, h);
        y += h + gap;
    }

    // 上下留白，让首尾歌词也能滚到中间
    CGFloat half = self.bounds.size.height * 0.5;
    self.content.frame = CGRectMake(0, 0, w, y + half * 2);
    CGFloat cy = half;
    for (NELyricLineView *v in self.lineViews) {
        v.frame = CGRectOffset(v.frame, 0, cy);
        cy += v.bounds.size.height + gap;
    }
    self.scroll.contentSize = self.content.bounds.size;
    self.scroll.contentInset = UIEdgeInsetsZero;
    self.scrolledIndex = -1;

    [self applyTimeToViews];
    [self scrollToCurrentAnimated:NO];
}

#pragma mark - 时间驱动

- (void)setCurrentTime:(double)currentTime {
    // 外部（AVPlayer，20Hz）给一个准确时间，记为锚点。
    // 中间由 displayLink 按真实流逝插值，逐字高亮才连续。
    _currentTime = currentTime;
    self.anchorTime = currentTime;
    self.anchorAt = CACurrentMediaTime();

    [self applyTimeToViews];
    [self followIfNeeded];
}

/// 该不该自动滚动跟随当前行
- (void)followIfNeeded {
    if (self.userDragging) return;
    if (self.dragEndAt > 0 && CACurrentMediaTime() - self.dragEndAt < 4.0) return;
    [self scrollToCurrentAnimated:YES];
}

- (void)setPlaying:(BOOL)playing {
    _playing = playing;
    if (playing) [self startDisplayLink];
    else [self stopDisplayLink];
}

- (void)startDisplayLink {
    if (self.displayLink) return;
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onDisplayTick)];
    self.displayLink.preferredFramesPerSecond = 60;
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopDisplayLink {
    [self.displayLink invalidate];
    self.displayLink = nil;
}

- (void)onDisplayTick {
    // 只做插值，不回写锚点（否则时间永远停在原点）
    double t = self.anchorTime;
    if (self.playing) {
        t += (CACurrentMediaTime() - self.anchorAt);
        if (!isfinite(t) || t < 0) t = 0;
    }
    _currentTime = t;
    [self applyTimeToViews];
}

- (void)willMoveToWindow:(UIWindow *)newWindow {
    [super willMoveToWindow:newWindow];
    if (!newWindow) [self stopDisplayLink];
}

- (void)dealloc {
    [self.displayLink invalidate];
}

- (void)applyTimeToViews {
    if (!self.lyric.lines.count) return;
    NSInteger idx = [self.lyric indexAtTime:self.currentTime];
    BOOL changed = (idx != self.currentIndex);

    for (NSInteger i = 0; i < (NSInteger)self.lineViews.count; i++) {
        NELyricLineView *v = self.lineViews[i];
        NELyricLine *l = v.line;
        BOOL active = (i == idx);
        v.active = active;
        v.currentTimeForLine = self.currentTime;

        if (active) {
            if (l.chars.count) {
                // 逐字：进度用「已唱字数 / 总字数」
                NSInteger ci = [self.lyric charIndexInLine:l atTime:self.currentTime];
                v.highlightProgress = ci < 0 ? 0 :
                    (CGFloat)(ci + 1) / (CGFloat)MAX(1, l.chars.count);
            } else {
                double span = MAX(0.35, l.end - l.start);
                v.highlightProgress = MAX(0, MIN(1, (self.currentTime - l.start) / span));
            }
        } else if (i < idx) {
            v.highlightProgress = 1;
        } else {
            v.highlightProgress = 0;
        }
    }

    if (changed) self.currentIndex = idx;
}

/// 只在「切换行」时滚动一次，而不是每帧都滚。
/// 之前每帧都起一个新动画，动画互相打断，看起来就是卡顿。
- (void)scrollToCurrentAnimated:(BOOL)animated {
    if (self.currentIndex < 0 || self.currentIndex >= (NSInteger)self.lineViews.count) return;
    if (self.scrolledIndex == self.currentIndex) return;
    self.scrolledIndex = self.currentIndex;

    NELyricLineView *v = self.lineViews[self.currentIndex];
    CGFloat target = CGRectGetMidY(v.frame) - self.bounds.size.height * 0.42;
    CGFloat maxY = MAX(0, self.scroll.contentSize.height - self.bounds.size.height);
    target = MAX(-self.scroll.contentInset.top, MIN(target, maxY));

    if (animated) {
        // 用 0.45s 缓动，和网易云的滚动节奏接近
        [UIView animateWithDuration:0.45 delay:0
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:^{
            self.scroll.contentOffset = CGPointMake(0, target);
        } completion:nil];
    } else {
        self.scroll.contentOffset = CGPointMake(0, target);
    }
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    self.userDragging = YES;
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) {
        self.userDragging = NO;
        self.dragEndAt = CACurrentMediaTime();
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    self.userDragging = NO;
    self.dragEndAt = CACurrentMediaTime();
}

@end