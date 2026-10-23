#import "NELyric.h"

@implementation NELyricChar
@end

@implementation NELyricLine
@end

@interface NELyric ()
@property (nonatomic, copy, readwrite) NSArray<NELyricLine *> *lines;
@property (nonatomic, assign, readwrite) BOOL hasWordTiming;
@end

@implementation NELyric

#pragma mark - 工具

/// 判断是否是「作词 : 张国祥」这类元信息行
static BOOL NELyricIsMeta(NSString *text) {
    static NSArray<NSString *> *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[@"作词", @"作曲", @"编曲", @"制作人", @"吉他", @"贝斯", @"鼓",
                 @"录音", @"混音", @"母带", @"和声", @"监制", @"出品", @"发行",
                 @"统筹", @"策划", @"原唱", @"词：", @"曲："];
    });
    // 注意：yrc 文本常带前导空格（"  作词 : xxx"），必须先 trim 再判断
    NSString *t = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!t.length) return YES;
    for (NSString *k in keys) {
        if ([t hasPrefix:k]) return YES;
    }
    // 形如 "作词 : 张国祥" 中间有空格
    for (NSString *k in @[@"作词", @"作曲", @"编曲", @"制作人", @"录音", @"混音"]) {
        if ([t hasPrefix:[k stringByAppendingString:@" "]]) return YES;
    }
    // 形如 "词 : xxx" / "曲 : xxx"
    NSRange colon = [t rangeOfString:@":"];
    if (colon.location != NSNotFound && colon.location <= 6) {
        NSString *head = [t substringToIndex:colon.location];
        head = [head stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        for (NSString *k in @[@"词", @"曲", @"编曲", @"制作人"]) {
            if ([head isEqualToString:k]) return YES;
        }
    }
    return NO;
}

/// 解析 [mm:ss.xxx] 为秒
static double NEParseLRCStamp(NSString *stamp, BOOL *ok) {
    // stamp 形如 "00:12.570" 或 "00:12.57"
    NSArray *colon = [stamp componentsSeparatedByString:@":"];
    if (colon.count < 2) { if (ok) *ok = NO; return 0; }
    double m = [colon[0] doubleValue];
    double s = [colon[1] doubleValue];
    if (ok) *ok = YES;
    return m * 60.0 + s;
}

#pragma mark - LRC / tlyric

/// 解析标准 LRC，返回 [时间, 文本] 数组
static NSArray<NSArray *> *NEParseLRC(NSString *raw) {
    NSMutableArray *out = [NSMutableArray array];
    if (!raw.length) return out;

    for (NSString *line in [raw componentsSeparatedByString:@"\n"]) {
        NSString *l = [line stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        if (![l hasPrefix:@"["]) continue;
        NSRange close = [l rangeOfString:@"]"];
        if (close.location == NSNotFound) continue;

        NSString *stamp = [l substringWithRange:NSMakeRange(1, close.location - 1)];
        NSString *text  = [l substringFromIndex:close.location + 1];

        BOOL ok = NO;
        double t = NEParseLRCStamp(stamp, &ok);
        if (!ok) continue;

        text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!text.length) continue;
        [out addObject:@[@(t), text]];
    }
    return out;
}

#pragma mark - YRC（逐字）

/// 解析 yrc：
///   [11820,2220](11820,120,0)The (11940,420,0)club ...
/// 返回 [起始秒, 时长秒, 文本, 字符数组]
static NSDictionary *NEParseYRCLine(NSString *line) {
    if (![line hasPrefix:@"["]) return nil;
    NSRange close = [line rangeOfString:@"]"];
    if (close.location == NSNotFound) return nil;

    NSArray *head = [[line substringWithRange:NSMakeRange(1, close.location - 1)]
                     componentsSeparatedByString:@","];
    if (head.count < 2) return nil;
    double startMs = [head[0] doubleValue];
    double durMs   = [head[1] doubleValue];

    NSString *body = [line substringFromIndex:close.location + 1];
    NSMutableArray<NELyricChar *> *chars = [NSMutableArray array];
    NSMutableString *plain = [NSMutableString string];

    NSUInteger i = 0;
    NSUInteger len = body.length;
    while (i < len) {
        if ([body characterAtIndex:i] == '(') {
            NSRange endParen = [body rangeOfString:@")"
                                           options:0
                                             range:NSMakeRange(i, len - i)];
            if (endParen.location == NSNotFound) break;
            NSString *meta = [body substringWithRange:
                              NSMakeRange(i + 1, endParen.location - i - 1)];
            NSArray *parts = [meta componentsSeparatedByString:@","];
            double cs = parts.count > 0 ? [parts[0] doubleValue] : 0;
            double cd = parts.count > 1 ? [parts[1] doubleValue] : 0;

            // 括号后面这一段文字属于这个时间点，直到下一个 '('
            NSUInteger textStart = endParen.location + 1;
            NSUInteger nextParen = [body rangeOfString:@"("
                                               options:0
                                                 range:NSMakeRange(textStart, len - textStart)].location;
            NSUInteger textEnd = (nextParen == NSNotFound) ? len : nextParen;
            NSString *seg = [body substringWithRange:NSMakeRange(textStart, textEnd - textStart)];

            if (seg.length) {
                NELyricChar *c = [NELyricChar new];
                c.start = cs / 1000.0;
                c.end   = (cd > 0) ? (cs + cd) / 1000.0 : c.start;
                c.text  = seg;
                [chars addObject:c];
                [plain appendString:seg];
            }
            i = textEnd;
        } else {
            // 没有时间标记的残余文本
            NSUInteger nextParen = [body rangeOfString:@"("
                                               options:0
                                                 range:NSMakeRange(i, len - i)].location;
            NSUInteger textEnd = (nextParen == NSNotFound) ? len : nextParen;
            NSString *seg = [body substringWithRange:NSMakeRange(i, textEnd - i)];
            [plain appendString:seg];
            i = textEnd;
        }
    }

    if (!plain.length) return nil;
    return @{@"start": @(startMs / 1000.0),
             @"dur":   @(durMs / 1000.0),
             @"text":  plain,
             @"chars": chars};
}

#pragma mark - 构建

+ (instancetype)lyricWithLRC:(NSString *)lrc
                      tlyric:(NSString *)tlyric
                         yrc:(NSString *)yrc {
    NELyric *lyric = [NELyric new];
    NSMutableArray<NELyricLine *> *lines = [NSMutableArray array];

    // 1) 翻译表：时间(取整到 10ms) -> 译文
    NSMutableDictionary<NSNumber *, NSString *> *trans = [NSMutableDictionary dictionary];
    for (NSArray *pair in NEParseLRC(tlyric)) {
        NSInteger key = (NSInteger)llround([pair[0] doubleValue] * 100.0);
        trans[@(key)] = pair[1];
    }

    // 2) 优先用 yrc（带逐字）
    NSMutableArray<NSDictionary *> *yrcLines = [NSMutableArray array];
    if (yrc.length) {
        for (NSString *line in [yrc componentsSeparatedByString:@"\n"]) {
            NSDictionary *d = NEParseYRCLine([line stringByTrimmingCharactersInSet:
                                              [NSCharacterSet newlineCharacterSet]]);
            if (d) [yrcLines addObject:d];
        }
    }

    if (yrcLines.count) {
        lyric.hasWordTiming = YES;
        for (NSDictionary *d in yrcLines) {
            NELyricLine *line = [NELyricLine new];
            line.start = [d[@"start"] doubleValue];
            line.end   = line.start + [d[@"dur"] doubleValue];
            line.text  = d[@"text"];
            line.chars = d[@"chars"];
            line.isMeta = NELyricIsMeta(line.text);
            NSInteger key = (NSInteger)llround(line.start * 100.0);
            line.translation = trans[@(key)];
            [lines addObject:line];
        }
        // yrc 缺翻译时，用 lrc 的文本去补
        if (!trans.count) {
            NSArray<NSArray *> *lrcPairs = NEParseLRC(lrc);
            NSMutableDictionary<NSNumber *, NSString *> *byText = [NSMutableDictionary dictionary];
            for (NSArray *p in lrcPairs) byText[p[1]] = p[0];
            for (NELyricLine *line in lines) {
                NSNumber *t = byText[line.text];
                if (t) {
                    NSInteger k = (NSInteger)llround(t.doubleValue * 100.0);
                    if (trans[@(k)]) line.translation = trans[@(k)];
                }
            }
        }
    } else {
        // 3) 退回普通 LRC
        NSArray<NSArray *> *pairs = NEParseLRC(lrc);
        for (NSArray *pair in pairs) {
            NELyricLine *line = [NELyricLine new];
            line.start = [pair[0] doubleValue];
            line.text  = pair[1];
            NSInteger key = (NSInteger)llround(line.start * 100.0);
            line.translation = trans[@(key)];
            line.isMeta = NELyricIsMeta(line.text);
            [lines addObject:line];
        }
    }

    // 4) 按时间排序
    [lines sortUsingComparator:^NSComparisonResult(NELyricLine *a, NELyricLine *b) {
        if (a.start < b.start) return NSOrderedAscending;
        if (a.start > b.start) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    // 5) 回填每行结束时间（下一行开始时间）
    for (NSInteger i = 0; i < (NSInteger)lines.count; i++) {
        NELyricLine *cur = lines[i];
        if (cur.end <= cur.start && i + 1 < (NSInteger)lines.count) {
            cur.end = lines[i + 1].start;
        }
    }

    lyric.lines = lines;
    return lyric;
}

#pragma mark - 查询

- (NSInteger)indexAtTime:(double)time {
    NSInteger lo = 0, hi = (NSInteger)self.lines.count - 1, found = -1;
    while (lo <= hi) {
        NSInteger mid = (lo + hi) / 2;
        NELyricLine *l = self.lines[mid];
        if (l.start <= time) { found = mid; lo = mid + 1; }
        else hi = mid - 1;
    }
    // 跳过元信息行：回退到最近的可高亮行
    NSInteger i = found;
    while (i >= 0 && self.lines[i].isMeta) i--;
    return (i >= 0) ? i : -1;
}

- (NSInteger)charIndexInLine:(NELyricLine *)line atTime:(double)time {
    if (!line.chars.count) return -1;
    NSInteger idx = -1;
    for (NSInteger i = 0; i < (NSInteger)line.chars.count; i++) {
        if (line.chars[i].start <= time) idx = i;
        else break;
    }
    return idx;
}

@end