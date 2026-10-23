#import "NEPlayer.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

NSString *const NEPlayerStateChangedNotification = @"NEPlayerStateChangedNotification";
NSString *const NEPlayerTrackChangedNotification = @"NEPlayerTrackChangedNotification";
NSString *const NEPlayerProgressNotification = @"NEPlayerProgressNotification";
NSString *const NEPlayerQueueChangedNotification = @"NEPlayerQueueChangedNotification";

static NSString *const kNEPlayModeKey = @"NEPlayerPlayMode";

@interface NEPlayer ()
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) id timeObserver;
@property (nonatomic, strong, readwrite) NSArray<NESong *> *queue;
@property (nonatomic, assign, readwrite) NSInteger currentIndex;
@property (nonatomic, assign, readwrite) BOOL isPlaying;
@property (nonatomic, assign, readwrite) double currentTime;
@property (nonatomic, assign, readwrite) double duration;
/// 恢复播放用：解析到 URL 后要 seek 到的位置
@property (nonatomic, assign) double pendingSeek;
/// 上次落盘时间（CACurrentMediaTime）
@property (nonatomic, assign) CFTimeInterval lastPersistAt;
@end

static NSString *const kNEPlayerStateKey = @"NEPlayerLastState";

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
        _playMode = (NEPlayMode)[[NSUserDefaults standardUserDefaults] integerForKey:kNEPlayModeKey];
        [self setupAudioSession];
        [self observeInterruptions];
        [self setupRemoteCommands];

        // 退到后台/被杀之前把当前队列和进度存下来，下次启动恢复
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(persistState)
                   name:UIApplicationDidEnterBackgroundNotification object:nil];
        [nc addObserver:self selector:@selector(persistState)
                   name:UIApplicationWillTerminateNotification object:nil];

        [self restoreState];
    }
    return self;
}

#pragma mark - 状态持久化

- (void)persistState {
    if (!self.queue.count) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kNEPlayerStateKey];
        return;
    }
    NSMutableArray *songs = [NSMutableArray array];
    for (NESong *s in self.queue) {
        [songs addObject:@{
            @"id": s.songID ?: @"",
            @"name": s.name ?: @"",
            @"artist": s.artist ?: @"",
            @"album": s.album ?: @"",
            @"cover": s.coverURL ?: @"",
            @"duration": @(s.durationMs),
        }];
    }
    [[NSUserDefaults standardUserDefaults] setObject:@{
        @"queue": songs,
        @"index": @(self.currentIndex),
        @"time": @(self.currentTime),
    } forKey:kNEPlayerStateKey];
}

- (void)restoreState {
    NSDictionary *state = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kNEPlayerStateKey];
    if (![state isKindOfClass:[NSDictionary class]]) return;

    NSArray *raw = state[@"queue"];
    if (![raw isKindOfClass:[NSArray class]] || !raw.count) return;

    NSMutableArray<NESong *> *songs = [NSMutableArray array];
    for (NSDictionary *d in raw) {
        if (![d isKindOfClass:[NSDictionary class]]) continue;
        NESong *s = [NESong new];
        s.songID = d[@"id"] ?: @"";
        s.name = d[@"name"] ?: @"";
        s.artist = d[@"artist"] ?: @"";
        s.album = d[@"album"] ?: @"";
        s.coverURL = d[@"cover"] ?: @"";
        s.durationMs = [d[@"duration"] integerValue];
        if (s.songID.length) [songs addObject:s];
    }
    if (!songs.count) return;

    self.queue = songs;
    NSInteger idx = [state[@"index"] integerValue];
    self.currentIndex = MAX(0, MIN(idx, (NSInteger)songs.count - 1));
    self.currentTime = MAX(0, [state[@"time"] doubleValue]);
    self.duration = self.currentSong.durationMs > 0 ? self.currentSong.durationMs / 1000.0 : 0;

    NSLog(@"[NEMusic] 恢复上次播放：%@（%.0f 秒）", self.currentSong.name, self.currentTime);

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:NEPlayerTrackChangedNotification object:self];
        [[NSNotificationCenter defaultCenter] postNotificationName:NEPlayerProgressNotification object:self];
    });
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
        if (opt.integerValue & AVAudioSessionInterruptionOptionShouldResume) {
            [self.player play];
            self.isPlaying = YES;
            [self notifyState];
            [self updateNowPlaying];
        }
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
    [[NSNotificationCenter defaultCenter] postNotificationName:NEPlayerQueueChangedNotification object:self];
    [self loadCurrentAndPlay];
}

#pragma mark - 播放模式 / 队列

- (void)setPlayMode:(NEPlayMode)playMode {
    _playMode = playMode;
    [[NSUserDefaults standardUserDefaults] setInteger:playMode forKey:kNEPlayModeKey];
    [self notifyState];
}

- (void)cyclePlayMode {
    self.playMode = (NEPlayMode)((self.playMode + 1) % 4);
}

- (void)playAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.queue.count) return;
    self.currentIndex = index;
    [self loadCurrentAndPlay];
}

- (void)removeSongAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.queue.count) return;

    NSMutableArray *queue = [self.queue mutableCopy];
    BOOL removingCurrent = (index == self.currentIndex);
    [queue removeObjectAtIndex:index];
    self.queue = queue;

    if (!queue.count) {
        [self stop];
        [[NSNotificationCenter defaultCenter] postNotificationName:NEPlayerQueueChangedNotification object:self];
        return;
    }
    if (removingCurrent) {
        if (self.currentIndex >= (NSInteger)queue.count) {
            self.currentIndex = (NSInteger)queue.count - 1;
        }
        [self loadCurrentAndPlay];
    } else if (index < self.currentIndex) {
        self.currentIndex--;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:NEPlayerQueueChangedNotification object:self];
}

- (void)clearQueue {
    [self stop];
    [[NSNotificationCenter defaultCenter] postNotificationName:NEPlayerQueueChangedNotification object:self];
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
    } else {
        [self.player replaceCurrentItemWithPlayerItem:item];
    }
    // 每个 item 都要重新挂观察器：上面刚 remove 过，否则切歌后进度不再更新
    [self addPeriodicObserver];

    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(itemDidFinish:)
        name:AVPlayerItemDidPlayToEndTimeNotification object:item];

    [self.player play];
    self.isPlaying = YES;
    self.currentTime = 0;
    self.duration = song.durationMs > 0 ? song.durationMs / 1000.0 : 0;

    // 从上次退出恢复的曲目：解析到地址后回到原来的进度
    if (self.pendingSeek > 0.5) {
        double seek = self.pendingSeek;
        self.pendingSeek = 0;
        [self.player seekToTime:CMTimeMakeWithSeconds(seek, NSEC_PER_SEC)
                toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
        self.currentTime = seek;
    }
    [self persistState];

    [[NSNotificationCenter defaultCenter] postNotificationName:NEPlayerTrackChangedNotification object:self];
    [self notifyState];
    [self updateNowPlaying];
}

- (void)itemDidFinish:(NSNotification *)note {
    [self advanceAutomatically];
}

- (void)advanceAutomatically {
    NSInteger count = (NSInteger)self.queue.count;
    if (count <= 0) return;

    // 单曲循环
    if (self.playMode == NEPlayModeSingleLoop) {
        [self.player seekTo:CMTimeMakeWithSeconds(0, NSEC_PER_SEC)
            toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
        [self.player play];
        self.isPlaying = YES;
        self.currentTime = 0;
        [self notifyState];
        return;
    }

    // 只有一首：循环模式重播，顺序模式停下
    if (count == 1) {
        if (self.playMode == NEPlayModeListLoop || self.playMode == NEPlayModeShuffle) {
            [self seekTo:0];
            [self.player play];
            self.isPlaying = YES;
            [self notifyState];
        } else {
            [self.player pause];
            self.isPlaying = NO;
            [self notifyState];
        }
        return;
    }

    NSInteger nextIndex = -1;
    if (self.playMode == NEPlayModeShuffle) {
        do { nextIndex = (NSInteger)arc4random_uniform((uint32_t)count); }
        while (nextIndex == self.currentIndex);
    } else {
        nextIndex = self.currentIndex + 1;
    }

    if (nextIndex >= count) {
        if (self.playMode == NEPlayModeListLoop) {
            nextIndex = 0;
        } else {
            // 顺序播放：停到最后一首
            [self.player pause];
            self.isPlaying = NO;
            self.currentTime = self.duration;
            [self notifyState];
            [self updateNowPlaying];
            return;
        }
    }

    self.currentIndex = nextIndex;
    [self loadCurrentAndPlay];
}

- (void)togglePlayPause {
    if (!self.currentSong) return;
    if (!self.player || !self.player.currentItem) {
        // 上次退出时恢复出来的队列还没有真正的播放器：重新解析地址再播
        self.pendingSeek = self.currentTime;
        [self loadCurrentAndPlay];
        return;
    }
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
    NSInteger count = (NSInteger)self.queue.count;
    if (count <= 1) return;

    if (self.playMode == NEPlayModeShuffle) {
        NSInteger idx;
        do { idx = (NSInteger)arc4random_uniform((uint32_t)count); }
        while (idx == self.currentIndex);
        self.currentIndex = idx;
    } else if (self.currentIndex + 1 < count) {
        self.currentIndex++;
    } else if (self.playMode == NEPlayModeListLoop) {
        self.currentIndex = 0;
    } else {
        return;
    }
    [self loadCurrentAndPlay];
}

- (void)previous {
    NSInteger count = (NSInteger)self.queue.count;
    // 播放超过 3 秒先回开头，符合常见交互
    if (self.currentTime > 3.0) { [self seekTo:0]; return; }
    if (count <= 1) { [self seekTo:0]; return; }

    if (self.playMode == NEPlayModeShuffle) {
        NSInteger idx;
        do { idx = (NSInteger)arc4random_uniform((uint32_t)count); }
        while (idx == self.currentIndex);
        self.currentIndex = idx;
    } else if (self.currentIndex > 0) {
        self.currentIndex--;
    } else if (self.playMode == NEPlayModeListLoop) {
        self.currentIndex = count - 1;
    } else {
        [self seekTo:0];
        return;
    }
    [self loadCurrentAndPlay];
}

- (void)seekTo:(double)seconds {
    CMTime t = CMTimeMakeWithSeconds(seconds, NSEC_PER_SEC);
    [self.player seekToTime:t toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    self.currentTime = seconds;
    [self persistState];
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
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kNEPlayerStateKey];
    [self notifyState];
}

#pragma mark - 进度观察

- (void)addPeriodicObserver {
    __weak typeof(self) weakSelf = self;
    self.timeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 20)
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
        // 每 5 秒落一次盘，应用被杀也不会丢太多进度
        CFTimeInterval now = CACurrentMediaTime();
        if (now - self.lastPersistAt > 5.0) {
            self.lastPersistAt = now;
            [self persistState];
        }
        // 进度单独发通知：歌词要按 20Hz 平滑推进，
        // 但整个面板不该每次都全量刷新
        [[NSNotificationCenter defaultCenter] postNotificationName:NEPlayerProgressNotification
                                                            object:self];
    }];
}

- (void)removeTimeObserver {
    // 注意调用顺序：stop() 中必须先 remove 再释放 player
    if (self.timeObserver && self.player) {
        [self.player removeTimeObserver:self.timeObserver];
    }
    self.timeObserver = nil;
}

- (void)notifyState {
    [[NSNotificationCenter defaultCenter] postNotificationName:NEPlayerStateChangedNotification object:self];
}

@end