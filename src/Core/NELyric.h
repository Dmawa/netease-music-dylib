//  NELyric.h
//  歌词模型：统一 lrc / tlyric / yrc 三种格式
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 单个字（仅 yrc 逐字歌词才有）
@interface NELyricChar : NSObject
@property (nonatomic, assign) double start;   // 秒
@property (nonatomic, assign) double end;     // 秒
@property (nonatomic, copy)   NSString *text;
@end

@interface NELyricLine : NSObject
@property (nonatomic, assign) double start;   // 秒
@property (nonatomic, assign) double end;     // 秒（含时长，0 表示未知）
@property (nonatomic, copy)   NSString *text;
/// 翻译（没有则为 nil）
@property (nonatomic, copy, nullable) NSString *translation;
/// 逐字时间，为空表示只有整行时间
@property (nonatomic, copy, nullable) NSArray<NELyricChar *> *chars;
/// 是否是可以高亮演唱的正文（过滤掉「作词 : xxx」这类头信息）
@property (nonatomic, assign) BOOL isMeta;
@end

@interface NELyric : NSObject
@property (nonatomic, copy, readonly) NSArray<NELyricLine *> *lines;
/// 是否含逐字数据
@property (nonatomic, assign, readonly) BOOL hasWordTiming;

/// 同时解析三种格式；任一可为 nil
+ (nullable instancetype)lyricWithLRC:(nullable NSString *)lrc
                             tlyric:(nullable NSString *)tlyric
                                 yrc:(nullable NSString *)yrc;

/// 二分查找：返回当前时间应高亮的行（无可高亮行时返回 -1）
- (NSInteger)indexAtTime:(double)time;
/// 第 line 行在某时刻应点亮到第几个字（-1 表示还没开始）
- (NSInteger)charIndexInLine:(NELyricLine *)line atTime:(double)time;

@end

NS_ASSUME_NONNULL_END