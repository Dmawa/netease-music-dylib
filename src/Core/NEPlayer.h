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

@end

NS_ASSUME_NONNULL_END