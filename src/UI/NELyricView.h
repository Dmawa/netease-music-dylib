//  NELyricView.h
//  歌词滚动视图：整行高亮 + 逐字点亮 + 翻译 + 点击跳转 + 用户滚动后自动回位
#import <UIKit/UIKit.h>
#import "NELyric.h"

NS_ASSUME_NONNULL_BEGIN

@protocol NELyricViewDelegate <NSObject>
@optional
/// 用户点击某一行，请求跳转到该时间
- (void)lyricView:(id)view didSeekToTime:(double)time;
@end

@interface NELyricView : UIView

@property (nonatomic, weak, nullable) id<NELyricViewDelegate> delegate;
@property (nonatomic, strong, nullable) NELyric *lyric;
/// 当前时间，设置后自动滚动与高亮
@property (nonatomic, assign) double currentTime;
/// 是否显示翻译（默认 YES）
@property (nonatomic, assign) BOOL showsTranslation;
/// 是否正在播放：开启后用 CADisplayLink 做 60fps 时间插值
@property (nonatomic, assign) BOOL playing;
/// 字号缩放（默认 1.0），让歌词随窗口大小自适应
@property (nonatomic, assign) CGFloat fontScale;

- (void)reload;

@end

NS_ASSUME_NONNULL_END