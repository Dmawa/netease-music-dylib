//  NEPlayer.h
//  播放内核：AVPlayer + 队列 + 后台播放
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "NEApi.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const NEPlayerStateChangedNotification;
extern NSString *const NEPlayerTrackChangedNotification;
/// 播放进度（约 20Hz），只给歌词/进度条用
extern NSString *const NEPlayerProgressNotification;
/// 播放队列变化（增删/清空）
extern NSString *const NEPlayerQueueChangedNotification;

typedef NS_ENUM(NSInteger, NEPlayMode) {
    NEPlayModeListLoop = 0,   // 列表循环
    NEPlayModeSingleLoop,     // 单曲循环
    NEPlayModeShuffle,        // 随机播放
    NEPlayModeSequential,     // 顺序播放
};

@interface NEPlayer : NSObject

+ (instancetype)shared;

@property (nonatomic, strong, readonly) NSArray<NESong *> *queue;
@property (nonatomic, assign, readonly) NSInteger currentIndex;
@property (nonatomic, strong, readonly, nullable) NESong *currentSong;
@property (nonatomic, assign, readonly) BOOL isPlaying;
@property (nonatomic, assign, readonly) double currentTime;
@property (nonatomic, assign, readonly) double duration;

/// 播放整个列表，index 指定起点
- (void)playQueue:(NSArray<NESong *> *)songs atIndex:(NSInteger)index;
- (void)togglePlayPause;
- (void)next;
- (void)previous;
- (void)seekTo:(double)seconds;
- (void)stop;

/// 播放模式（列表循环/单曲循环/随机/顺序），会持久化
@property (nonatomic, assign) NEPlayMode playMode;
- (void)cyclePlayMode;
/// 从队列指定位置播放（播放列表页用）
- (void)playAtIndex:(NSInteger)index;
/// 从队列移除一首（播放列表页用）
- (void)removeSongAtIndex:(NSInteger)index;
- (void)clearQueue;

@end

NS_ASSUME_NONNULL_END