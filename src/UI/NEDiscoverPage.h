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
@end

@interface NEDiscoverPage : UIView
@property (nonatomic, weak, nullable) id<NEDiscoverPageDelegate> delegate;
- (void)reloadData;
@end

NS_ASSUME_NONNULL_END