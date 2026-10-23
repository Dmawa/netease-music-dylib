//  NEDiscoverPage.h
//  发现页：快捷入口 + 推荐歌单 + 推荐新歌
#import <UIKit/UIKit.h>
#import "NEApi.h"

NS_ASSUME_NONNULL_BEGIN

@protocol NEDiscoverPageDelegate <NSObject>
/// 点开推荐歌单
- (void)discoverPage:(id)page didOpenPlaylistID:(NSString *)playlistID title:(NSString *)title;
/// 播放一首新歌
- (void)discoverPage:(id)page didPlaySong:(NESong *)song;
/// 拉到一整批歌曲（每日推荐等），交给面板按列表展示
- (void)discoverPage:(id)page didLoadSongs:(NSArray<NESong *> *)songs title:(NSString *)title;
/// 快捷入口：私人漫游 / 心动模式 / 排行榜
- (void)discoverPageDidRequestRoam:(id)page;
- (void)discoverPageDidRequestHeartMode:(id)page;
- (void)discoverPageDidRequestToplist:(id)page;
@end

@interface NEDiscoverPage : UIView
@property (nonatomic, weak, nullable) id<NEDiscoverPageDelegate> delegate;
- (void)reloadData;
@end

NS_ASSUME_NONNULL_END