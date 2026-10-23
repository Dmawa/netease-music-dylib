#import "NEPlayer.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>

NSString *const NEPlayerStateChangedNotification = @"NEPlayerStateChangedNotification";
NSString *const NEPlayerTrackChangedNotification = @"NEPlayerTrackChangedNotification";

@interface NEPlayer ()
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) id timeObserver;
@property (nonatomic, strong, readwrite) NSArray<NESong *> *queue;
@property (nonatomic, assign, readwrite) NSInteger currentIndex;
@property (nonatomic, assign, readwrite) BOOL isPlaying;
@property (nonatomic, assign, readwrite) double currentTime;
@property (nonatomic, assign, readwrite) double duration;
@end

@implementation NEPlayer

+ (instancetype)shared {
    static NEPlayer *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NEPlayer new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = @[];
        _currentIndex = -1;
        [self setupAudioSession];
        [self observeInterruptions];
        [self setupRemoteCommands];
    }
    return self;
}

#pragma mark - 音频会话

- (void)setupAudioSession {
    AVAudioSession *s = [AVAudioSession sharedInstance];
    NSError *err = nil;
    // playback：静音键下仍可出声，且支持后台
    [s setCategory:AVAudioSessionCategoryPlayback error:&err];
    [s setActive:YES error:&err];
}

- (void)observeInterruptions {
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(handleInterruption:)
        name:AVAudioSessionInterruptionNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(handleRouteChange:)
        name:AVAudioSessionRouteChangeNotification object:nil];
}

- (void)handleInterruption:(NSNotification *)note {
    NSNumber *type = note.userInfo[AVAudioSessionInterruptionTypeKey];
    if (type.integerValue == AVAudioSessionInterruptionTypeBegan) {
        [self.player pause];
        self.isPlaying = NO;
        [self notifyState];
    } else if (type.integerValue == AVAudioSessionInterruptionTypeEnded) {
        NSNumber *opt = note.userInfo[AVAudioSessionInterruptionOptionKey];
        if (opt.integerValue & AVAudioSessionInterruptionOptionShouldResume) [self.player play];
    }
}

- (void)handleRouteChange:(NSNotification *)note {
    // 拔耳机自动暂停（符合系统预期，也避免外放吓人）
    NSNumber *reason = note.userInfo[AVAudioSessionRouteChangeReasonKey];
    if (reason.integerValue == AVAudioSessionRouteChangeReasonOldDeviceUnavailable) {
        [self.player pause];
        self.isPlaying = NO;
        [self notifyState];
    }
}

#pragma mark - 远程控制（锁屏 / 耳机）

- (void)setupRemoteCommands {
    MPRemoteCommandCenter *c = [MPRemoteCommandCenter sharedCommandCenter];
    [c.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [self.player play]; self.isPlaying = YES; [self notifyState]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [c.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [self.player pause]; self.isPlaying = NO; [self notifyState]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [c.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [self togglePlayPause]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [c.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [self next]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [c.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [self previous]; return MPRemoteCommandHandlerStatusSuccess;
    }];
}

- (void)updateNowPlaying {
    NESong *song = self.currentSong;
    if (!song) { [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil; return; }

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = song.name ?: @"";
    info[MPMediaItemPropertyArtist] = song.artist ?: @"";
    info[MPMediaItemPropertyPlaybackDuration] = @(self.duration);
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(self.currentTime);
    info[MPNowPlayingInfoPropertyPlaybackRate] = @(self.isPlaying ? 1.0 : 0.0);
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;

    if (song.coverURL.length) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:song.coverURL]];
            UIImage *img = data ? [UIImage imageWithData:data] : nil;
            if (!img) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                MPMediaItemArtwork *art = [[MPMediaItemArtwork alloc] initWithBoundsSize:img.size
                    requestHandler:^UIImage *(CGSize size) { return img; }];
                NSMutableDictionary *cur = [[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo mutableCopy];
                cur[MPMediaItemPropertyArtwork] = art;
                [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = cur;
            });
        });
    }
}

#pragma mark - 播放控制

- (NESong *)currentSong {
    if (self.currentIndex < 0 || self.currentIndex >= (NSInteger)self.queue.count) return nil;
    return self.queue[self.currentIndex];
}

- (void)playQueue:(NSArray<NESong *> *)songs atIndex:(NSInteger)index {
    if (!songs.count) return;
    self.queue = songs;
    self.currentIndex = MAX(0, MIN(index, (NSInteger)songs.count - 1));
    [self loadCurrentAndPlay];
}

- (void)loadCurrentAndPlay {
    NESong *song = self.currentSong;
    if (!song) return;

    [[NEApi shared] resolveStreamURLForSong:song complete:^(NSString *url, NSError *error) {
        if (!url) {
            // 解析失败自动跳下一首，避免卡死；队列遍历一圈后停止
            NSLog(@"[NEMusic] 获取播放地址失败: %@", error.localizedDescription);
            [self advanceAutomatically];
            return;
        }
        [self replaceItemWithURL:[NSURL URLWithString:url] song:song];
    }];
}

- (void)replaceItemWithURL:(NSURL *)url song:(NESong *)song {
    [self.player pause];
    [self removeTimeObserver];

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    if (!self.player) {
        self.player = [AVPlayer playerWithPlayerItem:item];
        self.player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
        [self addPeriodicObserver];
    } else {
        [self.player replaceCurrentItemWithPlayerItem:item];
    }

    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(itemDidFinish:)
        name:AVPlayerItemDidPlayToEndTimeNotification object:item];

    [self.player play];
    self.isPlaying = YES;
    self.currentTime = 0;
    self.duration = song.durationMs > 0 ? song.durationMs / 1000.0 : 0;

    [[NSNotificationCenter defaultCenter] postNotificationName:NEPlayerTrackChangedNotification object:self];
    [self notifyState];
    [self updateNowPlaying];
}

- (void)itemDidFinish:(NSNotification *)note {
    [self advanceAutomatically];
}

- (void)advanceAutomatically {
    if (self.currentIndex + 1 < (NSInteger)self.queue.count) {
        self.currentIndex++;
        [self loadCurrentAndPlay];
    } else {
        [self.player pause];
        self.isPlaying = NO;
        self.currentIndex = 0;
        [self notifyState];
    }
}

- (void)togglePlayPause {
    if (!self.player) return;
    if (self.isPlaying) {
        [self.player pause];
        self.isPlaying = NO;
    } else {
        [self.player play];
        self.isPlaying = YES;
    }
    [self notifyState];
    [self updateNowPlaying];
}

- (void)next {
    if (self.currentIndex + 1 >= (NSInteger)self.queue.count) return;
    self.currentIndex++;
    [self loadCurrentAndPlay];
}

- (void)previous {
    // 播放超过 3 秒先回开头，符合常见交互
    if (self.currentTime > 3.0) { [self seekTo:0]; return; }
    if (self.currentIndex <= 0) { [self seekTo:0]; return; }
    self.currentIndex--;
    [self loadCurrentAndPlay];
}

- (void)seekTo:(double)seconds {
    CMTime t = CMTimeMakeWithSeconds(seconds, NSEC_PER_SEC);
    [self.player seekToTime:t toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    self.currentTime = seconds;
    [self notifyState];
    [self updateNowPlaying];
}

- (void)stop {
    [self.player pause];
    [self removeTimeObserver];
    self.player = nil;
    self.queue = @[];
    self.currentIndex = -1;
    self.isPlaying = NO;
    self.currentTime = 0;
    self.duration = 0;
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
    [self notifyState];
}

#pragma mark - 进度观察

- (void)addPeriodicObserver {
    __weak typeof(self) weakSelf = self;
    self.timeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 2)
                                                                  queue:dispatch_get_main_queue()
                                                             usingBlock:^(CMTime time) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.currentTime = CMTimeGetSeconds(time);
        CMTime dur = self.player.currentItem.duration;
        if (CMTIME_IS_NUMERIC(dur)) {
            double d = CMTimeGetSeconds(dur);
            if (d > 0) self.duration = d;
        }
        [self notifyState];
    }];
}

- (void)removeTimeObserver {
    if (self.timeObserver) {
        [self.player removeTimeObserver:self.timeObserver];
        self.timeObserver = nil;
    }
}

- (void)notifyState {
    [[NSNotificationCenter defaultCenter] postNotificationName:NEPlayerStateChangedNotification object:self];
}

@end