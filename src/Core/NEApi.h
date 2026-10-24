//  NEApi.h
//  网易云 Web 明文接口封装（扫码登录 / 搜索 / 歌单 / 播放 / 歌词）
//  说明：以下接口均已实测可用，无需 weapi 加密。
#import <Foundation/Foundation.h>
#import "NESession.h"
#import "NELyric.h"

NS_ASSUME_NONNULL_BEGIN

/// 统一的简版数据模型，UI 只认这个
@interface NESong : NSObject
@property (nonatomic, copy)   NSString *songID;
@property (nonatomic, copy)   NSString *name;
@property (nonatomic, copy)   NSString *artist;
@property (nonatomic, copy)   NSString *album;
@property (nonatomic, copy)   NSString *coverURL;
@property (nonatomic, assign) NSInteger durationMs;
@property (nonatomic, assign) BOOL      vipOnly;   // 服务端标记需要会员
/// 播放地址（懒加载，请求后才有效）
@property (nonatomic, copy, nullable) NSString *streamURL;
@end

/// 推荐卡片（歌单 / 新歌 / 电台 通用）
@interface NERecommendItem : NSObject
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *coverURL;
/// 0=歌单 1=新歌 2=电台
@property (nonatomic, assign) NSInteger kind;
@end

@interface NEPlaylist : NSObject
@property (nonatomic, copy) NSString *playlistID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *coverURL;
@property (nonatomic, assign) NSInteger trackCount;
@property (nonatomic, assign) NSInteger playCount;
/// 网易云的特殊歌单标记：5 = 我喜欢的音乐
@property (nonatomic, assign) NSInteger specialType;
@property (nonatomic, assign) NSInteger creatorID;
@property (nonatomic, copy)   NSString *creatorName;
@end

typedef void (^NEQRCodeBlock)(NSString * _Nullable unikey, NSError * _Nullable error);
/// 801 等扫码 / 802 已扫待确认 / 803 成功 / 800 过期
typedef void (^NEPollBlock)(NSInteger code, NSString * _Nullable nickname, NSError * _Nullable error);
/// 轮询回调的扩展版：同时回传响应里的原始 Set-Cookie 行（便于确认 MUSIC_U）
typedef void (^NEPollDetailBlock)(NSInteger code, NSString * _Nullable nickname,
                                  NSArray<NSString *> * _Nullable setCookieLines,
                                  NSString * _Nullable message,
                                  NSError * _Nullable error);
typedef void (^NESongsBlock)(NSArray<NESong *> * _Nullable songs, NSError * _Nullable error);
typedef void (^NELyricBlock)(NELyric * _Nullable lyric, NSError * _Nullable error);

@interface NEApi : NSObject

+ (instancetype)shared;

#pragma mark 登录（二维码）
/// 申请一个 unikey，随后可用于生成二维码
- (void)requestQRKey:(NEQRCodeBlock)complete;
/// 轮询扫码状态；返回 code 语义见 NEPollBlock 注释
- (void)pollQRCode:(NSString *)unikey complete:(NEPollBlock)complete;
/// 同 pollQRCode，但额外返回原始 Set-Cookie，用于诊断登录凭证问题
- (void)pollQRCodeDetail:(NSString *)unikey complete:(NEPollDetailBlock)complete;
/// 当前登录账号昵称；未登录回调 nil
- (void)fetchAccount:(void (^)(NSString * _Nullable nickname, NSString * _Nullable avatar, NSError * _Nullable error))complete;
/// 原始 profile（nickname/avatarUrl/userId/vipType 等），设置页用
- (void)fetchProfile:(void (^)(NSDictionary * _Nullable profile, NSError * _Nullable error))complete;
- (BOOL)isLoggedIn;
- (void)logout;

/// 启动时恢复登录态：有本地 Cookie 就向服务端校验一次，
/// 返回 true 表示仍有效（登录状态可跨启动保持）
- (void)restoreSession:(void (^)(BOOL loggedIn, NSString * _Nullable nickname,
                                 NSString * _Nullable avatar))complete;

#pragma mark 内容
/// keyword 为空时返回推荐/热门，作为首页兜底
- (void)searchSongs:(NSString *)keyword limit:(NSInteger)limit complete:(NESongsBlock)complete;
- (void)fetchPlaylistDetail:(NSString *)playlistID complete:(NESongsBlock)complete;
- (void)fetchToplist:(NESongsBlock)complete;
/// 我的歌单（需登录）；返回的列表里含「我喜欢的音乐」
- (void)fetchMyPlaylists:(void (^)(NSArray<NEPlaylist *> * _Nullable, NSError * _Nullable))complete;
/// 「我喜欢的音乐」：specialType == 5 的那个歌单，取不到时回调 nil
- (void)fetchLikedPlaylist:(void (^)(NEPlaylist * _Nullable playlist, NSError * _Nullable error))complete;
/// 我创建/收藏的歌单（排除年度歌单等特殊类型）
- (void)fetchMyCollectedPlaylists:(void (^)(NSArray<NEPlaylist *> * _Nullable, NSError * _Nullable))complete;
/// 每日推荐（/api/v3/discovery/recommend/songs，未登录也会返回一份通用推荐）
- (void)fetchDailyRecommendSongs:(NESongsBlock)complete;

#pragma mark 发现页
/// 推荐歌单
- (void)fetchRecommendPlaylists:(NSInteger)limit
                       complete:(void (^)(NSArray<NERecommendItem *> * _Nullable,
                                          NSError * _Nullable))complete;
/// 推荐新歌
- (void)fetchRecommendNewSongs:(NSInteger)limit
                      complete:(void (^)(NSArray<NERecommendItem *> * _Nullable,
                                         NSError * _Nullable))complete;
/// 排行榜（前若干个榜单的名称与封面）
- (void)fetchToplists:(void (^)(NSArray<NERecommendItem *> * _Nullable,
                                NSError * _Nullable))complete;
- (void)fetchPlaylistSongs:(NSString *)playlistID complete:(NESongsBlock)complete;

#pragma mark 播放
/// 解析播放地址；部分曲目需要登录 cookie，未登录会返回 nil url
- (void)resolveStreamURLForSong:(NESong *)song
                     complete:(void (^)(NSString * _Nullable url, NSError * _Nullable error))complete;
- (void)fetchLyricForSong:(NESong *)song complete:(NELyricBlock)complete;

#pragma mark 互动
/// 歌曲评论：返回原始评论字典（含 hotComments + comments，已去重）
- (void)fetchCommentsForSongID:(NSString *)songID
                         limit:(NSInteger)limit
                      complete:(void (^)(NSArray<NSDictionary *> * _Nullable comments,
                                         NSInteger total,
                                         NSError * _Nullable error))complete;
/// 歌曲喜欢状态与总数（/api/song/like/get，需要登录）
- (void)fetchSongLikeState:(NSString *)songID
                  complete:(void (^)(NSInteger likedCount, BOOL liked,
                                     NSError * _Nullable error))complete;
/// 喜欢 / 取消喜欢一首歌（需要登录）
- (void)likeSongID:(NSString *)songID
             liked:(BOOL)liked
          complete:(void (^)(BOOL ok, NSError * _Nullable error))complete;
/// 「我的」页头部（followText/followedText/levelText/listenSongs 等）
/// 播客首页信息流（/api/voice/homepage/block/page，pageCode 如 PODCAST_HOMEPAGE_PODCAST_TAB）
- (void)fetchPodcastHomeWithPageCode:(NSString *)pageCode
                            complete:(void (^)(NSArray<NERecommendItem *> * _Nullable items,
                                               NSError * _Nullable error))complete;
- (void)fetchMineHeaderWithUserID:(NSString *)uid
                         complete:(void (^)(NSDictionary * _Nullable header,
                                            NSError * _Nullable error))complete;
/// 用户详情：等级 + 听歌量（匿名可读）
- (void)fetchUserDetailWithUID:(NSString *)uid
                      complete:(void (^)(NSInteger level, NSInteger listenSongs,
                                         NSError * _Nullable error))complete;
/// 心动模式：以 seedID 为种子要一批歌
- (void)fetchHeartModeSongsWithSeed:(NSString *)seedID
                              limit:(NSInteger)limit
                           complete:(NESongsBlock)complete;

@end

NS_ASSUME_NONNULL_END